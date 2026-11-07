import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:music_analysis/decoders/wav_decoder.dart';
import 'package:music_analysis/utils/fft.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import '../services/audio_core_ffi.dart';

class DeviceAnalyzer {
  static const MethodChannel _channel = MethodChannel('crate/analysis');

  Future<Map<String, dynamic>?> analyze(
    Track track, {
    int scanSeconds = 30,
  }) async {
    String? wavPath;
    double? fullDuration;
    try {
      if (Platform.isAndroid) {
        try {
          final native = await _channel.invokeMethod<Map<Object?, Object?>>(
            'analyzeNative',
            {'path': track.path, 'scanSeconds': scanSeconds},
          );
          if (native != null) {
            final mapped = native.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            if (_isValidNative(mapped)) return mapped;
          }
        } catch (_) {}
        final result = await _channel.invokeMethod<Map<Object?, Object?>>(
          'decodeToWav',
          {'path': track.path, 'scanSeconds': scanSeconds},
        );
        wavPath = result?['path'] as String?;
        fullDuration = (result?['duration'] as num?)?.toDouble();
        if (fullDuration == null || fullDuration <= 0) {
          fullDuration = track.duration != null
              ? track.duration!.inMilliseconds / 1000.0
              : null;
        }
      } else if (Platform.isWindows) {
        wavPath = await _decodeWithFfmpeg(track.path);
      } else {
        return null;
      }
      if (wavPath == null) return null;
      final current = wavPath;
      return await Isolate.run(
        () => analyzeWavFile(current, fullDuration, scanSeconds),
      );
    } catch (_) {
      return null;
    } finally {
      if (wavPath != null) {
        try {
          await File(wavPath).delete();
        } catch (_) {}
      }
    }
  }

  Future<String?> _decodeWithFfmpeg(String input) async {
    final ffmpeg = _findFfmpeg();
    if (ffmpeg == null) return null;
    final temp = await getTemporaryDirectory();
    final output = File(
      p.join(
        temp.path,
        'crate_analysis_${DateTime.now().microsecondsSinceEpoch}.wav',
      ),
    );
    final result = await Process.run(ffmpeg, [
      '-y',
      '-v',
      'error',
      '-i',
      input,
      '-vn',
      '-ac',
      '2',
      '-c:a',
      'pcm_s16le',
      output.path,
    ]);
    if (result.exitCode != 0 || !await output.exists()) {
      try {
        await output.delete();
      } catch (_) {}
      return null;
    }
    return output.path;
  }

  String? _findFfmpeg() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      p.join(exeDir, 'ffmpeg.exe'),
      p.join(exeDir, 'tools', 'ffmpeg.exe'),
      p.join(Directory.current.path, 'tools', 'ffmpeg.exe'),
      r'C:\Users\GamerPC\Projects\Crate\tools\ffmpeg.exe',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  static bool _isValidNative(Map<String, dynamic> data) {
    final bpm = (data['bpm'] as num?)?.toDouble() ?? 0;
    final bar = (data['barLength'] as num?)?.toDouble() ?? 0;
    final mixIn = (data['mixIn'] as num?)?.toDouble() ?? 0;
    final mixOut = (data['mixOut'] as num?)?.toDouble() ?? 0;
    final features = data['features'];
    return bpm >= 40 &&
        bpm <= 220 &&
        bar > 0.1 &&
        mixOut > mixIn &&
        features is List &&
        features.length >= 8;
  }
}

Future<Map<String, dynamic>?> analyzeWavFile(
  String path, [
  double? fullDuration,
  int scanSeconds = 30,
]) async {
  try {
    final bytes = await File(path).readAsBytes();
    final decoded = await WavDecoder().decode(bytes);
    final measuredTruePeakDb = _measureTruePeakDb(bytes);
    var samples = decoded.audioData;
    var sampleRate = decoded.sampleRate;
    if (samples.isEmpty || sampleRate <= 0) return null;

    const targetRate = 11025;
    if (sampleRate > targetRate) {
      samples = _downsample(samples, sampleRate, targetRate);
      sampleRate = targetRate;
    }

    final wavDuration = samples.length / sampleRate;
    final duration = (fullDuration != null && fullDuration > wavDuration)
        ? fullDuration
        : wavDuration;
    final rms = _rmsStats(samples, sampleRate, wavDuration);
    final leadIn = rms.leadIn;
    final audibleEnd = (fullDuration != null && fullDuration > wavDuration)
        ? fullDuration
        : rms.audibleEnd;

    final wholeTrack = scanSeconds <= 0;
    final analysisSeconds = wholeTrack
        ? math.max(10.0, rms.audibleEnd - rms.leadIn)
        : scanSeconds.toDouble();
    final excerptStart = wholeTrack
        ? math.max(0.0, rms.leadIn)
        : math.max(rms.leadIn, wavDuration * 0.15);
    var excerptEnd = math.min(wavDuration, excerptStart + analysisSeconds);
    if (rms.audibleEnd > excerptStart && rms.audibleEnd < excerptEnd) {
      excerptEnd = rms.audibleEnd;
    }
    if (excerptEnd - excerptStart < 10) {
      excerptEnd = math.min(wavDuration, excerptStart + 10);
    }
    final startIndex = (excerptStart * sampleRate)
        .floor()
        .clamp(0, samples.length)
        .toInt();
    final endIndex = (excerptEnd * sampleRate)
        .ceil()
        .clamp(startIndex, samples.length)
        .toInt();
    final excerpt = startIndex < endIndex
        ? samples.sublist(startIndex, endIndex)
        : samples;

    final spectral = _spectralFeatures(excerpt, sampleRate);
    final tempo = _estimateTempo(spectral.flux, sampleRate);

    final barLength = 4 * 60 / tempo.bpm;
    final phase = (excerptStart + tempo.phaseSeconds) % barLength;
    final downbeats = <double>[];
    for (var t = phase; t < duration; t += barLength) {
      downbeats.add(t);
    }
    var mixIn = leadIn;
    for (final downbeat in downbeats) {
      if (downbeat >= leadIn) {
        mixIn = downbeat;
        break;
      }
    }
    var mixOut = audibleEnd;
    final limit = audibleEnd - 8 * barLength;
    for (final downbeat in downbeats) {
      if (downbeat <= limit) {
        mixOut = downbeat;
      } else {
        break;
      }
    }
    if (mixOut <= mixIn + barLength) {
      mixOut = audibleEnd;
    }

    final features = <double>[
      ...List<double>.filled(12, 0),
      (tempo.bpm / 200).clamp(0.0, 2.0),
      rms.energy,
      (spectral.centroid / 8000).clamp(0.0, 2.0),
      spectral.flatness.clamp(0.0, 1.0),
      (spectral.rolloff / 8000).clamp(0.0, 2.0),
      spectral.zcr.clamp(0.0, 1.0),
    ];

    double rounded(double value, int places) {
      final factor = math.pow(10, places).toDouble();
      return (value * factor).round() / factor;
    }

    return {
      'version': 4,
      'bpm': rounded(tempo.bpm, 3),
      'beatsPerBar': 4,
      'barLength': rounded(barLength, 4),
      'downbeats': [for (final value in downbeats) rounded(value, 3)],
      'downbeatPhase': rounded(phase, 3),
      'duration': rounded(duration, 3),
      'leadIn': rounded(leadIn, 3),
      'audibleEnd': rounded(audibleEnd, 3),
      'mixIn': rounded(mixIn, 3),
      'mixOut': rounded(mixOut, 3),
      'beatlessIntro': false,
      'beatlessOutro': false,
      'energy': rounded(rms.energy, 4),
      'lufs': null,
      'peakDb': rounded(rms.peakDb, 2),
      'truePeakDb': rounded(measuredTruePeakDb ?? rms.peakDb, 2),
      'keyRoot': 0,
      'isMinor': false,
      'key': '',
      'camelot': '',
      'keyConfidence': 0.0,
      'features': [for (final value in features) rounded(value, 5)],
    };
  } catch (_) {
    return null;
  }
}

double? _measureTruePeakDb(Uint8List bytes) {
  try {
    final decoded = _readPcm16Wave(bytes);
    if (decoded == null) return null;
    if (decoded.channels <= 1) {
      return AudioCoreFfi.measureTruePeakDb(
        decoded.interleaved,
        decoded.sampleRate,
      );
    }
    double? bestPeakDb;
    final frames = decoded.interleaved.length ~/ decoded.channels;
    for (var channel = 0; channel < decoded.channels; channel++) {
      final mono = Float32List(frames);
      for (var frame = 0; frame < frames; frame++) {
        mono[frame] = decoded.interleaved[frame * decoded.channels + channel];
      }
      final channelPeakDb = AudioCoreFfi.measureTruePeakDb(
        mono,
        decoded.sampleRate,
      );
      if (channelPeakDb != null &&
          (bestPeakDb == null || channelPeakDb > bestPeakDb)) {
        bestPeakDb = channelPeakDb;
      }
    }
    return bestPeakDb;
  } catch (_) {
    return null;
  }
}

({Float32List interleaved, int sampleRate, int channels})? _readPcm16Wave(
  Uint8List bytes,
) {
  if (bytes.length < 44) return null;
  final data = ByteData.sublistView(bytes);
  final channels = data.getUint16(22, Endian.little);
  final sampleRate = data.getUint32(24, Endian.little);
  final bitsPerSample = data.getUint16(34, Endian.little);
  if (channels <= 0 || sampleRate <= 0 || bitsPerSample != 16) return null;
  var dataOffset = -1;
  var dataSize = 0;
  for (var index = 12; index + 8 <= bytes.length; index++) {
    if (bytes[index] == 0x64 &&
        bytes[index + 1] == 0x61 &&
        bytes[index + 2] == 0x74 &&
        bytes[index + 3] == 0x61) {
      dataOffset = index + 8;
      dataSize = data.getUint32(index + 4, Endian.little);
      break;
    }
  }
  if (dataOffset < 0 || dataOffset >= bytes.length) return null;
  final availableBytes = bytes.length - dataOffset;
  final frameBytes = 2 * channels;
  final frames = (dataSize <= 0 ? availableBytes : dataSize) ~/ frameBytes;
  if (frames <= 0) return null;
  final sampleCount = frames * channels;
  if (sampleCount <= 0) return null;
  final interleaved = Float32List(sampleCount);
  for (var frame = 0; frame < frames; frame++) {
    for (var channel = 0; channel < channels; channel++) {
      final offset = dataOffset + ((frame * channels + channel) * 2);
      interleaved[frame * channels + channel] =
          data.getInt16(offset, Endian.little) / 32768.0;
    }
  }
  return (interleaved: interleaved, sampleRate: sampleRate, channels: channels);
}

({
  List<double> flux,
  double centroid,
  double flatness,
  double rolloff,
  double zcr,
})
_spectralFeatures(Float32List samples, int sampleRate) {
  const frameSize = 2048;
  const hop = 512;
  const spectrumSize = frameSize ~/ 2;
  final window = _hann(frameSize);
  final real = Float64List(frameSize);
  final imaginary = Float64List(frameSize);
  final previous = Float64List(spectrumSize);
  final current = Float64List(spectrumSize);
  final flux = <double>[];
  var hasPrevious = false;
  var centroidSum = 0.0;
  var flatnessSum = 0.0;
  var rolloffSum = 0.0;
  var zcrSum = 0.0;
  var frames = 0;

  for (var start = 0; start + frameSize <= samples.length; start += hop) {
    var zeroCrossings = 0;
    var previousPositive = samples[start] >= 0;
    for (var i = 0; i < frameSize; i++) {
      final sample = samples[start + i];
      final positive = sample >= 0;
      if (positive != previousPositive) zeroCrossings++;
      previousPositive = positive;
      real[i] = sample * window[i];
      imaginary[i] = 0;
    }
    FFT.transform(real, imaginary);

    var magnitudeSum = 0.0;
    var logSum = 0.0;
    var weighted = 0.0;
    var energySum = 0.0;
    for (var bin = 0; bin < spectrumSize; bin++) {
      final magnitude = math.sqrt(
        real[bin] * real[bin] + imaginary[bin] * imaginary[bin],
      );
      current[bin] = magnitude;
      magnitudeSum += magnitude;
      logSum += math.log(magnitude + 1e-9);
      weighted += magnitude * bin * sampleRate / frameSize;
      energySum += magnitude * magnitude;
    }

    if (hasPrevious) {
      var difference = 0.0;
      for (var bin = 0; bin < spectrumSize; bin++) {
        final delta = current[bin] - previous[bin];
        if (delta > 0) difference += delta;
      }
      flux.add(difference);
    } else {
      flux.add(0);
      hasPrevious = true;
    }

    centroidSum += magnitudeSum > 0 ? weighted / magnitudeSum : 0;
    flatnessSum += magnitudeSum > 0
        ? math.exp(logSum / spectrumSize) / (magnitudeSum / spectrumSize)
        : 0;

    var cumulative = 0.0;
    var rolloff = 0.0;
    final target = energySum * 0.85;
    for (var bin = 0; bin < spectrumSize; bin++) {
      cumulative += current[bin] * current[bin];
      if (cumulative >= target) {
        rolloff = bin * sampleRate / frameSize;
        break;
      }
    }
    rolloffSum += rolloff;
    zcrSum += zeroCrossings / frameSize;
    frames++;
    previous.setAll(0, current);
  }

  final divisor = frames == 0 ? 1 : frames;
  return (
    flux: flux,
    centroid: centroidSum / divisor,
    flatness: flatnessSum / divisor,
    rolloff: rolloffSum / divisor,
    zcr: zcrSum / divisor,
  );
}

({double bpm, double phaseSeconds}) _estimateTempo(
  List<double> flux,
  int sampleRate,
) {
  const hop = 512;
  if (flux.length < 16) {
    return (bpm: 120, phaseSeconds: 0);
  }
  final frameRate = sampleRate / hop;
  final mean = flux.reduce((a, b) => a + b) / flux.length;
  final normalized = [for (final value in flux) value - mean];
  final minLag = math.max(1, (frameRate * 60 / 200).round());
  final maxLag = math.min(normalized.length - 2, (frameRate * 60 / 60).round());
  if (maxLag < minLag) {
    return (bpm: 120, phaseSeconds: 0);
  }
  final correlations = List<double>.filled(maxLag + 1, 0);
  for (var lag = minLag; lag <= maxLag; lag++) {
    var sum = 0.0;
    for (var i = 0; i < normalized.length - lag; i++) {
      sum += normalized[i] * normalized[i + lag];
    }
    correlations[lag] = sum / (normalized.length - lag);
  }

  final candidates = <({double bpm, double corr, double beat, int lag})>[];
  for (var lag = minLag; lag <= maxLag; lag++) {
    if (lag > minLag && correlations[lag] < correlations[lag - 1]) continue;
    if (lag < maxLag && correlations[lag] < correlations[lag + 1]) continue;
    var bestBeat = 0.0;
    for (var phase = 0; phase < lag; phase++) {
      var sum = 0.0;
      var count = 0;
      for (var position = phase; position < flux.length; position += lag) {
        sum += flux[position];
        count++;
      }
      final score = count == 0 ? 0.0 : sum / count;
      if (score > bestBeat) bestBeat = score;
    }
    candidates.add((
      bpm: frameRate * 60 / lag,
      corr: correlations[lag],
      beat: bestBeat,
      lag: lag,
    ));
  }
  if (candidates.isEmpty) {
    return (bpm: 120, phaseSeconds: 0);
  }
  final maxCorr = candidates.map((c) => c.corr).reduce(math.max);
  final maxBeat = candidates.map((c) => c.beat).reduce(math.max);
  var best = candidates.first;
  var bestScore = -1.0;
  for (final candidate in candidates) {
    final prior = _tempoPrior(candidate.bpm);
    final score =
        (0.55 * candidate.corr / maxCorr + 0.45 * candidate.beat / maxBeat) *
        prior;
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }

  var bestPhase = 0;
  var bestPhaseScore = -1.0;
  for (var phase = 0; phase < best.lag; phase++) {
    var sum = 0.0;
    var count = 0;
    for (var position = phase; position < flux.length; position += best.lag) {
      sum += flux[position];
      count++;
    }
    final score = count == 0 ? 0.0 : sum / count;
    if (score > bestPhaseScore) {
      bestPhaseScore = score;
      bestPhase = phase;
    }
  }
  return (bpm: best.bpm, phaseSeconds: bestPhase * hop / sampleRate);
}

double _tempoPrior(double bpm) {
  final x = math.log(bpm / 120) / math.ln2;
  return math.exp(-0.5 * (x / 0.65) * (x / 0.65));
}

({double leadIn, double audibleEnd, double energy, double peakDb}) _rmsStats(
  Float32List samples,
  int sampleRate,
  double duration,
) {
  const frameSize = 2048;
  const hop = 512;
  final rms = <double>[];
  var maxRms = 0.0;
  var peak = 0.0;
  for (var start = 0; start + frameSize <= samples.length; start += hop) {
    var sum = 0.0;
    for (var i = 0; i < frameSize; i++) {
      final sample = samples[start + i];
      sum += sample * sample;
      final absolute = sample.abs();
      if (absolute > peak) peak = absolute;
    }
    final value = math.sqrt(sum / frameSize);
    rms.add(value);
    if (value > maxRms) maxRms = value;
  }
  final threshold = maxRms * 0.02;
  var first = -1;
  var last = -1;
  for (var i = 0; i < rms.length; i++) {
    if (rms[i] >= threshold) {
      if (first < 0) first = i;
      last = i;
    }
  }
  final leadIn = first < 0 ? 0.0 : first * hop / sampleRate;
  final audibleEnd = last < 0
      ? duration
      : math.min(duration, (last * hop + frameSize) / sampleRate);
  var energySum = 0.0;
  for (final value in rms) {
    energySum += value;
  }
  final energy = maxRms > 0
      ? (energySum / rms.length / maxRms).clamp(0.0, 1.0)
      : 0.0;
  final peakDb = peak > 0 ? 20 * math.log(peak) / math.ln10 : -96.0;
  return (
    leadIn: leadIn,
    audibleEnd: audibleEnd,
    energy: energy.toDouble(),
    peakDb: peakDb,
  );
}

Float32List _downsample(Float32List samples, int sourceRate, int targetRate) {
  if (sourceRate <= targetRate) return samples;
  final factor = sourceRate / targetRate;
  final length = (samples.length / factor).floor();
  final result = Float32List(length);
  for (var i = 0; i < length; i++) {
    final start = (i * factor).floor();
    final end = math.min(samples.length, ((i + 1) * factor).ceil());
    var sum = 0.0;
    for (var j = start; j < end; j++) {
      sum += samples[j];
    }
    result[i] = end > start ? sum / (end - start) : 0;
  }
  return result;
}

Float64List _hann(int size) {
  final window = Float64List(size);
  for (var i = 0; i < size; i++) {
    window[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (size - 1)));
  }
  return window;
}
