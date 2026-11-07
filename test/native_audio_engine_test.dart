import 'package:crate/models/native_audio_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el driver de salida nativo aun no esta disponible', () {
    expect(NativeAudioEngineProbe.customAudioOutputSupported, isFalse);
    expect(
      NativeAudioEngineProbe.status.availability,
      NativeAudioEngineAvailability.unavailable,
    );
    expect(NativeAudioEngineProbe.status.message, contains('media_kit'));
  });
}
