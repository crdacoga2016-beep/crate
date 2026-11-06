import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NotificationStatus {
  const NotificationStatus({
    required this.enabled,
    required this.permissionGranted,
    required this.channelExists,
    required this.channelImportance,
    required this.channelBlocked,
  });

  final bool enabled;
  final bool permissionGranted;
  final bool channelExists;
  final int channelImportance;
  final bool channelBlocked;

  static const empty = NotificationStatus(
    enabled: false,
    permissionGranted: false,
    channelExists: false,
    channelImportance: -1,
    channelBlocked: false,
  );
}

/// Bridges Flutter playback with the native Android MediaSession and its
/// foreground notification (notification shade, lock screen, Bluetooth...).
class MediaNotification {
  MediaNotification._();

  static final MediaNotification instance = MediaNotification._();
  static const MethodChannel _media = MethodChannel('crate/media');
  static const MethodChannel _permissions = MethodChannel('crate/permissions');

  bool _supported = false;
  bool _initialized = false;
  bool _permissionAsked = false;
  bool _permissionGranted = false;

  Future<void> Function()? _onPlay;
  Future<void> Function()? _onPause;
  Future<void> Function()? _onToggle;
  Future<void> Function()? _onNext;
  Future<void> Function()? _onPrevious;
  Future<void> Function()? _onStop;
  Future<void> Function(Duration position)? _onSeek;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onToggle,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
    required Future<void> Function() onStop,
    required Future<void> Function(Duration position) onSeek,
  }) async {
    _onPlay = onPlay;
    _onPause = onPause;
    _onToggle = onToggle;
    _onNext = onNext;
    _onPrevious = onPrevious;
    _onStop = onStop;
    _onSeek = onSeek;

    if (!isSupported || _initialized) return;
    _supported = true;
    _initialized = true;

    _media.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPlay':
          await _onPlay?.call();
          break;
        case 'onPause':
          await _onPause?.call();
          break;
        case 'onToggle':
          await _onToggle?.call();
          break;
        case 'onNext':
          await _onNext?.call();
          break;
        case 'onPrevious':
          await _onPrevious?.call();
          break;
        case 'onStop':
          await _onStop?.call();
          break;
        case 'onSeek':
          final value = call.arguments;
          if (value is num) {
            await _onSeek?.call(Duration(milliseconds: value.toInt()));
          }
          break;
      }
    });
  }

  Future<void> update({
    required String title,
    required String artist,
    required String album,
    required String? artworkPath,
    required Duration duration,
    required Duration position,
    required bool playing,
    double speed = 1,
    bool canNext = false,
    bool canPrevious = false,
  }) async {
    if (!_supported) return;
    try {
      await _media.invokeMethod<void>('update', <String, Object?>{
        'title': title,
        'artist': artist,
        'album': album,
        'artworkPath': artworkPath,
        'durationMs': duration.inMilliseconds,
        'positionMs': position.inMilliseconds,
        'playing': playing,
        'speed': speed,
        'canNext': canNext,
        'canPrevious': canPrevious,
      });
    } catch (error) {
      debugPrint('media notification update error: $error');
    }
  }

  Future<void> clear() async {
    if (!_supported) return;
    try {
      await _media.invokeMethod<void>('stop');
    } catch (error) {
      debugPrint('media notification stop error: $error');
    }
  }

  Future<bool> ensurePermission({bool force = false}) async {
    if (!_supported) return true;
    if (_permissionGranted) return true;
    if (_permissionAsked && !force) return _permissionGranted;
    _permissionAsked = true;
    try {
      final granted =
          await _permissions.invokeMethod<bool>('ensureNotificationPermission') ??
              false;
      _permissionGranted = granted;
      return granted;
    } catch (error) {
      debugPrint('notification permission error: $error');
      return false;
    }
  }

  Future<NotificationStatus> status() async {
    if (!_supported) return NotificationStatus.empty;
    try {
      final raw = await _permissions
          .invokeMapMethod<String, Object?>('notificationStatus');
      if (raw == null) return NotificationStatus.empty;
      return NotificationStatus(
        enabled: raw['enabled'] as bool? ?? false,
        permissionGranted: raw['permissionGranted'] as bool? ?? false,
        channelExists: raw['channelExists'] as bool? ?? false,
        channelImportance: (raw['channelImportance'] as num?)?.toInt() ?? -1,
        channelBlocked: raw['channelBlocked'] as bool? ?? false,
      );
    } catch (error) {
      debugPrint('notification status error: $error');
      return NotificationStatus.empty;
    }
  }

  Future<void> openSettings() async {
    if (!_supported) return;
    try {
      await _permissions.invokeMethod<void>('openNotificationSettings');
    } catch (error) {
      debugPrint('open notification settings error: $error');
    }
  }

  Future<bool> postTestNotification() async {
    if (!_supported) return false;
    try {
      return await _permissions.invokeMethod<bool>('postTestNotification') ??
          false;
    } catch (error) {
      debugPrint('test notification error: $error');
      return false;
    }
  }
}
