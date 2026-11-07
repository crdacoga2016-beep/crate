import 'dart:io';

import 'package:crate/models/track.dart';
import 'package:crate/services/device_analyzer.dart';
import 'package:crate/services/library_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('analyze real mp3 from G drive', () async {
    final mp3 = r'G:\musica\Music\MyAudioEditor\Metallica - One.mp3';
    expect(File(mp3).existsSync(), isTrue, reason: 'mp3 not found: $mp3');
    final track = Track(
      id: 'x',
      path: mp3,
      title: 'Metallica - One',
      artist: 'Metallica',
      album: 'Test',
    );
    final analyzer = DeviceAnalyzer();
    for (final window in [30, 120, 0]) {
      final stopwatch = Stopwatch()..start();
      final data = await analyzer.analyze(track, scanSeconds: window);
      stopwatch.stop();
      print('window=$window ms=${stopwatch.elapsedMilliseconds} bpm=${data?['bpm']} '
          'bar=${data?['barLength']} mixIn=${data?['mixIn']} mixOut=${data?['mixOut']}');
      expect(data, isNotNull, reason: 'analysis failed for window=$window');
      final bpm = (data!['bpm'] as num?)?.toDouble() ?? 0;
      expect(bpm, greaterThan(40));
      expect(bpm, lessThan(220));
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('scan G drive includes mp3 (sanity)', () async {
    final library = LibraryRepository();
    final tracks = await library.scanRoots([r'G:\musica']);
    final mp3 = tracks.where((t) => t.path.endsWith('.mp3')).length;
    print('mp3=$mp3 total=${tracks.length}');
    final metallica =
        tracks.where((t) => t.path.endsWith('Metallica - One.mp3'));
    expect(metallica, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
