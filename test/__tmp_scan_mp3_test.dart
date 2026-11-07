import 'dart:io';

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

  test('scan G drive music includes mp3', () async {
    final library = LibraryRepository();
    final tracks = await library.scanRoots([r'G:\musica']);
    final byExt = <String, int>{};
    for (final track in tracks) {
      final ext = track.path.split('.').last.toLowerCase();
      byExt[ext] = (byExt[ext] ?? 0) + 1;
    }
    print('total=$byExt total=${tracks.length}');
    final mp3Count = byExt['mp3'] ?? 0;
    expect(mp3Count, greaterThan(0),
        reason: 'no MP3 tracks were scanned from G:\\musica');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
