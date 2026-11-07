import '../services/audio_core_ffi.dart';

enum NativeAudioEngineAvailability { unavailable }

class NativeAudioEngineStatus {
  const NativeAudioEngineStatus(this.availability, this.message);

  final NativeAudioEngineAvailability availability;
  final String message;
}

class NativeAudioEngineProbe {
  const NativeAudioEngineProbe._();

  static bool get customAudioOutputSupported => false;

  static String get statusMessage {
    if (!AudioCoreFfi.isAvailable) {
      return 'Crate Audio Core no disponible; la música sigue con media_kit.';
    }
    return 'Custom libmpv AO pendiente; la música sigue con media_kit.';
  }

  static NativeAudioEngineStatus get status {
    return NativeAudioEngineStatus(
      NativeAudioEngineAvailability.unavailable,
      statusMessage,
    );
  }
}
