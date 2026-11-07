import 'package:crate/services/audio_core_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Audio Core FFI devuelve un resultado seguro', () {
    expect(AudioCoreFfi.versionLabel, anyOf('no disponible', '0.1.0'));
  });
}
