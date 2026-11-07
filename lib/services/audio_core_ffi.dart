import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _CrateAudioCoreVersion = Pointer<Uint8> Function();

class AudioCoreFfi {
  const AudioCoreFfi._();

  static DynamicLibrary? _library;
  static _CrateAudioCoreVersion? _version;

  static bool get isAvailable => version != null;

  static String? get version {
    try {
      final nativeVersion = _loadVersion();
      if (nativeVersion == null) return null;
      final pointer = nativeVersion();
      if (pointer == nullptr) return null;
      final bytes = <int>[];
      for (var offset = 0; ; offset++) {
        final value = pointer[offset];
        if (value == 0) break;
        bytes.add(value);
      }
      final result = utf8.decode(bytes);
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  static String get versionLabel {
    final result = version;
    return result ?? 'no disponible';
  }

  static _CrateAudioCoreVersion? _loadVersion() {
    if (_version != null) return _version;
    final library = _library ??= DynamicLibrary.open(_libraryName);
    final function = library
        .lookupFunction<_CrateAudioCoreVersion, _CrateAudioCoreVersion>(
          'crate_audio_core_version',
        );
    _version = function;
    return function;
  }

  static String get _libraryName {
    if (Platform.isWindows) return 'crate_audio_core.dll';
    if (Platform.isAndroid) return 'libcrate_audio_core.so';
    if (Platform.isLinux) return 'libcrate_audio_core.so';
    if (Platform.isMacOS) return 'libcrate_audio_core.dylib';
    return 'crate_audio_core';
  }
}
