import 'dart:io';

import 'package:crate/services/device_analyzer.dart';
import 'package:crate/services/library_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('crate_support_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  test('mp3 is included and analyzable', () async {
    final ffmpeg =
        '${Directory.current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}ffmpeg.exe';
    if (!File(ffmpeg).existsSync()) {
      markTestSkipped('ffmpeg.exe not found in tools/');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('crate_mp3_');
    try {
      final wav = '${dir.path}${Platform.pathSeparator}tone.wav';
      final gen = await Process.run(ffmpeg, [
        '-y',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:duration=4',
        '-c:a',
        'pcm_s16le',
        wav,
      ], runInShell: false);
      expect(gen.exitCode, 0, reason: 'ffmpeg tone generation failed');
      final mp3 = '${dir.path}${Platform.pathSeparator}tone.mp3';
      final enc = await Process.run(ffmpeg, [
        '-y',
        '-v',
        'error',
        '-i',
        wav,
        '-codec:a',
        'libmp3lame',
        '-q:a',
        '3',
        '-metadata',
        'title=Test Mp3',
        '-metadata',
        'artist=Test Artist',
        '-metadata',
        'album=Test Album',
        mp3,
      ], runInShell: false);
      expect(enc.exitCode, 0, reason: 'ffmpeg mp3 encode failed');
      expect(File(mp3).existsSync(), isTrue);

      // Scan must include the MP3.
      final library = LibraryRepository();
      final tracks = await library.scanRoots([dir.path]);
      final names = tracks.map((t) => t.path.split(Platform.pathSeparator).last);
      expect(names, contains('tone.mp3'));

      // Analyzer must return a valid analysis for MP3.
      final track = tracks.firstWhere((t) => t.path == mp3);
      final analysis = await DeviceAnalyzer().analyze(track, scanSeconds: 30);
      expect(analysis, isNotNull);
      final bpm = (analysis!['bpm'] as num?)?.toDouble() ?? 0;
      expect(bpm, greaterThan(40));
      expect(bpm, lessThan(220));
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('mp3 opens in media_kit', () async {
    try {
      MediaKit.ensureInitialized();
    } catch (_) {
      markTestSkipped('libmpv is not available (add the Release folder '
          'to PATH or run the Windows build)');
    }
    final ffmpeg =
        '${Directory.current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}ffmpeg.exe';
    final dir = await Directory.systemTemp.createTemp('crate_mp3play_');
    final player = Player();
    try {
      final wav = '${dir.path}${Platform.pathSeparator}tone.wav';
      final gen = await Process.run(ffmpeg, [
        '-y',
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:duration=4',
        '-c:a',
        'pcm_s16le',
        wav,
      ]);
      expect(gen.exitCode, 0);
      final mp3 = '${dir.path}${Platform.pathSeparator}tone.mp3';
      final enc = await Process.run(ffmpeg, [
        '-y',
        '-v',
        'error',
        '-i',
        wav,
        '-codec:a',
        'libmp3lame',
        '-q:a',
        '3',
        mp3,
      ]);
      expect(enc.exitCode, 0);
      // Give the engine a moment to report the duration.
      await player.open(Media(Uri.file(mp3).toString()), play: true);
      for (var i = 0; i < 40 && player.state.duration <= Duration.zero; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(player.state.duration, greaterThan(Duration.zero));
      await player.pause();
    } finally {
      await player.dispose();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
