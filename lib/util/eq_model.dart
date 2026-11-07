import 'dart:convert';
import 'dart:math' as math;

import 'gain_calculation.dart';

const List<int> eqBandFrequencies = [
  31,
  62,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

const double eqMinimumGainDb = -12.0;
const double eqMaximumGainDb = 12.0;
const double eqGainStepDb = 0.5;
const double eqBandQ = 1.0;
const double smartHeadroomSafetyDb = 0.5;
const double speakerPreampBoostDb = 3.0;
const double bluetoothPreampBoostDb = 2.0;
const Set<int> speakerHeadroomIgnoredFrequencies = {31, 62};
const double eqResponseDefaultSampleRate = 48000.0;

enum AudioOutputProfile { speaker, headphones, bluetooth, usb }

extension AudioOutputProfileDetails on AudioOutputProfile {
  String get key => name;

  String get label {
    return switch (this) {
      AudioOutputProfile.speaker => 'Altavoz',
      AudioOutputProfile.headphones => 'Auriculares',
      AudioOutputProfile.bluetooth => 'Bluetooth',
      AudioOutputProfile.usb => 'USB',
    };
  }
}

AudioOutputProfile audioOutputProfileFromKey(String? value) {
  for (final profile in AudioOutputProfile.values) {
    if (profile.key == value) return profile;
  }
  return AudioOutputProfile.speaker;
}

double quantizeEqGain(double value) {
  if (!value.isFinite) return 0.0;
  final steps = (value / eqGainStepDb).round() * eqGainStepDb;
  return steps.clamp(eqMinimumGainDb, eqMaximumGainDb).toDouble();
}

class EqPreset {
  const EqPreset({
    required this.id,
    required this.label,
    required this.gainsDb,
  });

  final String id;
  final String label;
  final List<double> gainsDb;
}

const List<EqPreset> eqPresets = [
  EqPreset(
    id: 'flat',
    label: 'Flat',
    gainsDb: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  ),
  EqPreset(
    id: 'natural',
    label: 'Natural',
    gainsDb: [0.0, 0.5, 0.5, -0.5, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5],
  ),
  EqPreset(
    id: 'soft_bass',
    label: 'Graves suaves',
    gainsDb: [2.0, 2.5, 1.5, 0.5, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5],
  ),
  EqPreset(
    id: 'vocal',
    label: 'Vocal',
    gainsDb: [0.0, 0.0, -1.0, -1.5, 0.5, 1.5, 2.5, 2.0, 0.5, -0.5],
  ),
  EqPreset(
    id: 'bluetooth',
    label: 'Bluetooth',
    gainsDb: [0.5, 1.0, 0.5, -0.5, 0.0, 0.5, 1.0, 1.0, 0.5, 0.5],
  ),
  EqPreset(
    id: 'bluetooth_live',
    label: 'Bluetooth Live',
    gainsDb: [0.0, 0.0, 2.0, 2.5, 0.5, 0.0, 0.0, 2.0, 1.0, 0.0],
  ),
  EqPreset(
    id: 'speaker_powerful',
    label: 'Altavoz Potente',
    gainsDb: [0.0, 0.0, 4.0, 5.0, 0.0, 0.0, 2.0, 2.5, 1.0, 0.0],
  ),
];

EqPreset? eqPresetById(String id) {
  for (final preset in eqPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

class EqState {
  const EqState({
    required this.gainsDb,
    this.bypass = false,
    this.selectedPresetId = 'custom',
  });

  static const flat = EqState(
    gainsDb: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    selectedPresetId: 'flat',
  );

  final List<double> gainsDb;
  final bool bypass;
  final String selectedPresetId;

  List<double> get effectiveGainsDb {
    if (bypass) return const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    return gainsDb;
  }

  double maximumResponseDbFor(AudioOutputProfile profile) {
    final ignoredFrequencies = profile == AudioOutputProfile.speaker
        ? speakerHeadroomIgnoredFrequencies
        : const <int>{};
    return maximumEqResponseDb(
      effectiveGainsDb,
      ignoredFrequencies: ignoredFrequencies,
    );
  }

  double get maximumResponseDb =>
      maximumResponseDbFor(AudioOutputProfile.headphones);

  double smartHeadroomDbFor(AudioOutputProfile profile) {
    final maximum = maximumResponseDbFor(profile);
    if (maximum <= 0.0) return 0.0;
    return -(maximum + smartHeadroomSafetyDb);
  }

  double get smartHeadroomDb =>
      smartHeadroomDbFor(AudioOutputProfile.headphones);

  double smartHeadroomGainFor(AudioOutputProfile profile) =>
      dbToLinearGain(smartHeadroomDbFor(profile));

  double get smartHeadroomGain =>
      smartHeadroomGainFor(AudioOutputProfile.headphones);

  double effectivePreampDbFor(
    double manualPreampDb,
    AudioOutputProfile profile,
  ) {
    final boost = switch (profile) {
      AudioOutputProfile.speaker => speakerPreampBoostDb,
      AudioOutputProfile.bluetooth => bluetoothPreampBoostDb,
      AudioOutputProfile.headphones => 0.0,
      AudioOutputProfile.usb => 0.0,
    };
    return manualPreampDb + boost;
  }

  EqState copyWith({
    List<double>? gainsDb,
    bool? bypass,
    String? selectedPresetId,
  }) {
    return EqState(
      gainsDb: gainsDb ?? this.gainsDb,
      bypass: bypass ?? this.bypass,
      selectedPresetId: selectedPresetId ?? this.selectedPresetId,
    ).normalized();
  }

  EqState normalized() {
    final normalizedGains = List<double>.generate(
      eqBandFrequencies.length,
      (index) => quantizeEqGain(index < gainsDb.length ? gainsDb[index] : 0.0),
    );
    return EqState(
      gainsDb: normalizedGains,
      bypass: bypass,
      selectedPresetId: selectedPresetId,
    );
  }

  EqState withBypass(bool value) => copyWith(bypass: value);

  factory EqState.fromPreset(String presetId) {
    final preset = eqPresetById(presetId);
    if (preset == null) return flat;
    return EqState(
      gainsDb: preset.gainsDb,
      selectedPresetId: preset.id,
    ).normalized();
  }

  factory EqState.migratedFromLegacy({
    required double bassDb,
    required double trebleDb,
  }) {
    final safeBass = clampFinite(bassDb, eqMinimumGainDb, eqMaximumGainDb);
    final safeTreble = clampFinite(trebleDb, eqMinimumGainDb, eqMaximumGainDb);
    if (safeBass == 0.0 && safeTreble == 0.0) return flat;
    final gains = List<double>.filled(eqBandFrequencies.length, 0.0);
    gains[0] = safeBass * 0.5;
    gains[1] = safeBass;
    gains[2] = safeBass * 0.5;
    gains[8] = safeTreble * 0.5;
    gains[9] = safeTreble * 0.5;
    return EqState(gainsDb: gains).normalized();
  }

  double responseDbAtHz(
    double frequencyHz, {
    double sampleRate = eqResponseDefaultSampleRate,
  }) {
    return eqResponseDbAtHz(
      effectiveGainsDb,
      frequencyHz: frequencyHz,
      sampleRate: sampleRate,
    );
  }

  Map<String, dynamic> toJson() => {
    'gainsDb': gainsDb,
    'bypass': bypass,
    'selectedPresetId': selectedPresetId,
  };

  String encode() => jsonEncode(toJson());

  factory EqState.fromJson(Map<String, dynamic> json) {
    final rawGains = json['gainsDb'];
    final gains = <double>[];
    if (rawGains is List) {
      for (final value in rawGains) {
        if (value is num) gains.add(value.toDouble());
      }
    }
    return EqState(
      gainsDb: gains,
      bypass: json['bypass'] == true,
      selectedPresetId: json['selectedPresetId']?.toString() ?? 'custom',
    ).normalized();
  }

  factory EqState.decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return flat;
    try {
      final value = jsonDecode(encoded);
      if (value is Map<String, dynamic>) return EqState.fromJson(value);
    } catch (_) {}
    return flat;
  }
}

class EqABSnapshot {
  const EqABSnapshot({required this.processed, required this.bypassed});

  final EqState processed;
  final EqState bypassed;

  EqState state(bool useBypass) => useBypass ? bypassed : processed;

  double differenceDbAt({
    required double frequencyHz,
    double sampleRate = eqResponseDefaultSampleRate,
  }) {
    return processed.responseDbAtHz(frequencyHz, sampleRate: sampleRate) -
        bypassed.responseDbAtHz(frequencyHz, sampleRate: sampleRate);
  }
}

EqABSnapshot eqABSnapshotFor(EqState state) {
  return EqABSnapshot(processed: state, bypassed: state.withBypass(true));
}

double eqResponseDbAtHz(
  List<double> gainsDb, {
  required double frequencyHz,
  double sampleRate = eqResponseDefaultSampleRate,
  double q = eqBandQ,
  Set<int> ignoredFrequencies = const <int>{},
}) {
  if (frequencyHz <= 0.0 || sampleRate <= 0.0) return 0.0;
  var response = 0.0;
  for (var index = 0; index < eqBandFrequencies.length; index++) {
    final gainDb = index < gainsDb.length
        ? quantizeEqGain(gainsDb[index])
        : 0.0;
    if (ignoredFrequencies.contains(eqBandFrequencies[index])) continue;
    if (gainDb.abs() < 0.05) continue;
    response += peakingResponseDb(
      frequencyHz: frequencyHz,
      centerFrequencyHz: eqBandFrequencies[index].toDouble(),
      gainDb: gainDb,
      sampleRate: sampleRate,
      q: q,
    );
  }
  return response;
}

double peakingResponseDb({
  required double frequencyHz,
  required double centerFrequencyHz,
  required double gainDb,
  required double sampleRate,
  required double q,
}) {
  if (frequencyHz <= 0.0 ||
      centerFrequencyHz <= 0.0 ||
      sampleRate <= 0.0 ||
      q <= 0.0) {
    return 0.0;
  }
  final omega = 2.0 * math.pi * frequencyHz / sampleRate;
  if (omega <= 0.0 || omega >= math.pi) return 0.0;
  final centerOmega = 2.0 * math.pi * centerFrequencyHz / sampleRate;
  if (centerOmega <= 0.0 || centerOmega >= math.pi) return 0.0;

  final amplitudeGain = math.pow(10.0, gainDb / 40.0).toDouble();
  final alpha = math.sin(centerOmega) / (2.0 * q);
  final cosine = math.cos(omega);
  final sine = math.sin(omega);
  final cosine2 = math.cos(2.0 * omega);
  final sine2 = math.sin(2.0 * omega);

  final b0 = 1.0 + alpha * amplitudeGain;
  final b1 = -2.0 * math.cos(centerOmega);
  final b2 = 1.0 - alpha * amplitudeGain;
  final a0 = 1.0 + alpha / amplitudeGain;
  final a1 = -2.0 * math.cos(centerOmega);
  final a2 = 1.0 - alpha / amplitudeGain;

  final numeratorReal = b0 + b1 * cosine + b2 * cosine2;
  final numeratorImag = -(b1 * sine + b2 * sine2);
  final denominatorReal = a0 + a1 * cosine + a2 * cosine2;
  final denominatorImag = -(a1 * sine + a2 * sine2);
  final denominatorMagnitude = math.sqrt(
    denominatorReal * denominatorReal + denominatorImag * denominatorImag,
  );
  if (denominatorMagnitude <= 1e-18) return 0.0;
  final numeratorMagnitude = math.sqrt(
    numeratorReal * numeratorReal + numeratorImag * numeratorImag,
  );
  final magnitude = numeratorMagnitude / denominatorMagnitude;
  if (!magnitude.isFinite || magnitude <= 0.0) return 0.0;
  return 20.0 * math.log(magnitude) / math.ln10;
}

double maximumEqResponseDb(
  List<double> gainsDb, {
  double sampleRate = eqResponseDefaultSampleRate,
  double minimumFrequency = 20.0,
  double maximumFrequency = 20000.0,
  int points = 720,
  Set<int> ignoredFrequencies = const <int>{},
}) {
  if (points < 1) return 0.0;
  final safeMinimum = minimumFrequency <= 0.0 ? 20.0 : minimumFrequency;
  final safeMaximum = maximumFrequency <= safeMinimum
      ? safeMinimum * 2.0
      : maximumFrequency;
  final ratio = safeMaximum / safeMinimum;
  var maximum = double.negativeInfinity;
  for (var index = 0; index <= points; index++) {
    final frequency = safeMinimum * math.pow(ratio, index / points).toDouble();
    final response = eqResponseDbAtHz(
      gainsDb,
      frequencyHz: frequency,
      sampleRate: sampleRate,
      ignoredFrequencies: ignoredFrequencies,
    );
    if (response > maximum) maximum = response;
  }
  return maximum == double.negativeInfinity ? 0.0 : maximum;
}
