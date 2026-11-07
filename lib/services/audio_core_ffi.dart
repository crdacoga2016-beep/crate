import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

typedef _CrateAudioCoreVersion = Pointer<Uint8> Function();
typedef _CrateAudioCoreProcessLimiterNative = Float Function(
  Pointer<Float> buffer,
  Int32 numSamples,
  Float ceilingDb,
);
typedef _CrateAudioCoreProcessLimiter = double Function(
  Pointer<Float> buffer,
  int numSamples,
  double ceilingDb,
);
typedef _CrateAudioCoreProcessLimiterAdvancedNative = Float Function(
  Pointer<Float> buffer,
  Int32 numSamples,
  Float ceilingDb,
  Float lookaheadMs,
  Float attackMs,
  Float releaseMs,
  Int32 sampleRate,
);
typedef _CrateAudioCoreProcessLimiterAdvanced = double Function(
  Pointer<Float> buffer,
  int numSamples,
  double ceilingDb,
  double lookaheadMs,
  double attackMs,
  double releaseMs,
  int sampleRate,
);
typedef _SystemMallocNative = Pointer<Void> Function(UintPtr);
typedef _SystemMalloc = Pointer<Void> Function(int);
typedef _SystemFreeNative = Void Function(Pointer<Void>);
typedef _SystemFree = void Function(Pointer<Void>);

class AudioCoreFfi {
  const AudioCoreFfi._();

  static DynamicLibrary? _library;
  static DynamicLibrary? _systemLibrary;
  static _SystemMalloc? _mallocFunction;
  static _SystemFree? _freeFunction;
  static _CrateAudioCoreVersion? _version;
  static _CrateAudioCoreProcessLimiter? _processLimiter;
  static _CrateAudioCoreProcessLimiterAdvanced? _processLimiterAdvanced;

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

  static double? processLimiter(Float32List samples, double ceilingDb) {
    if (samples.isEmpty || !ceilingDb.isFinite) return null;
    try {
      final function = _loadProcessLimiter();
      if (function == null) return null;
      final pointer = _allocateNative(samples.length * 4);
      if (pointer == null) return null;
      final floatPointer = pointer.cast<Float>();
      try {
        floatPointer.asTypedList(samples.length).setAll(0, samples);
        final appliedGain = function.call(
          floatPointer,
          samples.length,
          ceilingDb,
        );
        samples.setAll(0, floatPointer.asTypedList(samples.length));
        return appliedGain;
      } finally {
        _freeNative(pointer);
      }
    } catch (_) {
      return null;
    }
  }

  static double? processLimiterAdvanced(
    Float32List samples, {
    double ceilingDb = -1.0,
    double lookaheadMs = 5.0,
    double attackMs = 1.0,
    double releaseMs = 50.0,
    int sampleRate = 48000,
  }) {
    if (samples.isEmpty || sampleRate <= 0) return null;
    if (!ceilingDb.isFinite || !lookaheadMs.isFinite) return null;
    if (!attackMs.isFinite || !releaseMs.isFinite) return null;
    try {
      final function = _loadProcessLimiterAdvanced();
      if (function == null) return null;
      final pointer = _allocateNative(samples.length * 4);
      if (pointer == null) return null;
      final floatPointer = pointer.cast<Float>();
      try {
        floatPointer.asTypedList(samples.length).setAll(0, samples);
        final appliedGain = function.call(
          floatPointer,
          samples.length,
          ceilingDb,
          lookaheadMs,
          attackMs,
          releaseMs,
          sampleRate,
        );
        samples.setAll(0, floatPointer.asTypedList(samples.length));
        return appliedGain;
      } finally {
        _freeNative(pointer);
      }
    } catch (_) {
      return null;
    }
  }

  static Pointer<Void>? _allocateNative(int byteCount) {
    if (byteCount <= 0) return null;
    final library = _systemLibrary ??= DynamicLibrary.open(_systemLibraryName);
    final mallocFunction = _mallocFunction ??= library
        .lookupFunction<_SystemMallocNative, _SystemMalloc>('malloc');
    final pointer = mallocFunction(byteCount);
    return pointer == nullptr ? null : pointer;
  }

  static void _freeNative(Pointer<Void> pointer) {
    final library = _systemLibrary ??= DynamicLibrary.open(_systemLibraryName);
    final freeFunction = _freeFunction ??= library
        .lookupFunction<_SystemFreeNative, _SystemFree>('free');
    freeFunction(pointer);
  }

  static String get _systemLibraryName {
    if (Platform.isWindows) return 'msvcrt.dll';
    return 'libc.so';
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

  static _CrateAudioCoreProcessLimiterAdvanced? _loadProcessLimiterAdvanced() {
    if (_processLimiterAdvanced != null) return _processLimiterAdvanced;
    final library = _library ??= DynamicLibrary.open(_libraryName);
    final function = library
        .lookupFunction<
          _CrateAudioCoreProcessLimiterAdvancedNative,
          _CrateAudioCoreProcessLimiterAdvanced
        >('crate_audio_core_process_limiter_advanced');
    _processLimiterAdvanced = function;
    return function;
  }

  static _CrateAudioCoreProcessLimiter? _loadProcessLimiter() {
    if (_processLimiter != null) return _processLimiter;
    final library = _library ??= DynamicLibrary.open(_libraryName);
    final function = library
        .lookupFunction<
          _CrateAudioCoreProcessLimiterNative,
          _CrateAudioCoreProcessLimiter
        >('crate_audio_core_process_limiter');
    _processLimiter = function;
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
