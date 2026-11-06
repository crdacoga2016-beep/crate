import 'dart:async';
import 'dart:math' as math;

import 'package:media_kit/media_kit.dart';

import '../util/log.dart';

class _Deck {
  _Deck() : player = Player();

  final Player player;
  String? path;
  double gain = 1;

  Future<void> open(String path, {double volume = 0}) async {
    this.path = path;
    await player.open(Media(Uri.file(path).toString()), play: false);
    await player.setVolume(volume);
    await player.setRate(1);
  }

  Future<void> stop() async {
    path = null;
    await player.stop();
  }

  Future<void> dispose() => player.dispose();
}

class PlayerService {
  PlayerService() {
    _bindActive();
    for (final deck in _decks) {
      deck.player.stream.error.listen((error) {
        logLine('engine error: $error');
      });
    }
  }

  final List<_Deck> _decks = [_Deck(), _Deck()];
  int _active = 0;

  double _userVolume = 1;
  Timer? _fadeTimer;
  Timer? _rateTimer;
  String? _preparedPath;
  double _preparedRate = 1;
  double _preampGain = 1;
  double _baseBass = 0;
  double _baseTreble = 0;

  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingCtrl =
      StreamController<bool>.broadcast();
  final StreamController<void> _completedCtrl =
      StreamController<void>.broadcast();

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _playSub;
  StreamSubscription<bool>? _compSub;

  _Deck get _a => _decks[_active];
  _Deck get _incoming => _decks[1 - _active];

  Stream<Duration> get positionStream => _positionCtrl.stream;
  Stream<Duration> get durationStream => _durationCtrl.stream;
  Stream<bool> get playingStream => _playingCtrl.stream;
  Stream<void> get completedStream => _completedCtrl.stream;

  bool get playing => _a.player.state.playing;
  bool get completed => _a.player.state.completed;
  bool get isMixing => _fadeTimer != null;

  Duration get position => _a.player.state.position;
  Duration get duration => _a.player.state.duration;
  double get rate => _a.player.state.rate;

  void _bindActive() {
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _compSub?.cancel();

    final deck = _a;
    if (!_positionCtrl.isClosed) {
      _positionCtrl.add(deck.player.state.position);
      _durationCtrl.add(deck.player.state.duration);
      _playingCtrl.add(deck.player.state.playing);
    }

    _posSub = deck.player.stream.position.listen((value) {
      if (!_positionCtrl.isClosed) _positionCtrl.add(value);
    });
    _durSub = deck.player.stream.duration.listen((value) {
      if (!_durationCtrl.isClosed) _durationCtrl.add(value);
    });
    _playSub = deck.player.stream.playing.listen((value) {
      if (!_playingCtrl.isClosed) _playingCtrl.add(value);
    });
    _compSub = deck.player.stream.completed.listen((value) {
      if (value && identical(deck, _a) && !_completedCtrl.isClosed) {
        _completedCtrl.add(null);
      }
    });
  }

  Future<void> load(
    String path, {
    bool autoPlay = true,
    double rate = 1,
    double gain = 1,
    Duration startAt = Duration.zero,
  }) async {
    await _cancelTransitions();
    await _incoming.stop();
    _preparedPath = null;
    _bindActive();
    await _setEq(_a);
    await _applyBaseEq(_a);
    _a.gain = gain;
    logLine(
      'deck load: $path (rate $rate, gain ${gain.toStringAsFixed(2)}, '
      'start ${startAt.inMilliseconds}ms)',
    );
    await _a.open(path, volume: _userVolume * gain * _preampGain * 100);
    await _a.player.setRate(rate);
    if (autoPlay) await _a.player.play();
    if (startAt > Duration.zero && await _waitReady(_a)) {
      await _a.player.seek(startAt);
    }
  }

  Future<bool> _waitReady(_Deck deck) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      if (deck.player.state.duration > Duration.zero) return true;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return false;
  }

  Future<void> prepareIncoming(String path, {double rate = 1}) async {
    if (_fadeTimer != null || _preparedPath == path) return;
    await _incoming.stop();
    _preparedPath = null;
    await _incoming.open(path, volume: 0);
    await _incoming.player.setRate(rate);
    await _waitReady(_incoming);
    _preparedPath = path;
    _preparedRate = rate;
    logLine('deck preload: $path (rate $rate)');
  }

  Future<void> cancelPreload() async {
    _preparedPath = null;
    await _incoming.stop();
  }

  Future<void> play() => _a.player.play();
  Future<void> pause() => _a.player.pause();
  Future<void> seek(Duration position) => _a.player.seek(position);

  Future<void> setVolume(double volume) async {
    _userVolume = volume.clamp(0, 1);
    if (_fadeTimer != null) return;
    await _a.player.setVolume(_userVolume * _a.gain * _preampGain * 100);
  }

  Future<void> setPreamp(double db) async {
    _preampGain = math.pow(10, db / 20).toDouble();
    if (_fadeTimer == null) {
      await _a.player.setVolume(
        _userVolume * _a.gain * _preampGain * 100,
      );
    }
  }

  Future<void> setBaseEq({
    required double bass,
    required double treble,
  }) async {
    _baseBass = bass;
    _baseTreble = treble;
    if (_fadeTimer != null) return;
    await _applyBaseEq(_a);
  }

  Future<void> _applyBaseEq(_Deck deck) async {
    if (_baseBass.abs() < 0.1 && _baseTreble.abs() < 0.1) {
      await _setFilter(deck, '');
      return;
    }
    final filters = <String>[];
    if (_baseBass.abs() >= 0.1) {
      filters.add(
        'equalizer=f=80:t=q:w=1:g=${_baseBass.toStringAsFixed(1)}',
      );
    }
    if (_baseTreble.abs() >= 0.1) {
      filters.add(
        'equalizer=f=10000:t=q:w=1:g=${_baseTreble.toStringAsFixed(1)}',
      );
    }
    await _setFilter(
      deck,
      'format=s16,lavfi=[${filters.join(',')}]',
    );
  }

  Future<void> stop() async {
    await _cancelTransitions();
    _preparedPath = null;
    await _decks[0].stop();
    await _decks[1].stop();
  }

  Future<void> crossfadeTo(
    String nextPath, {
    required Duration duration,
    double incomingRate = 1,
    Duration incomingStart = Duration.zero,
    double incomingGain = 1,
    bool bassSwap = false,
    double eqIntensity = 0.6,
  }) async {
    if (_fadeTimer != null) return;

    final outgoing = _a;
    final incoming = _incoming;

    _active = 1 - _active;
    _bindActive();

    final prepared = _preparedPath == nextPath;
    incoming.gain = incomingGain;
    logLine('deck crossfade -> $nextPath (rate $incomingRate)');
    if (!prepared) {
      await incoming.open(nextPath, volume: 0);
      await incoming.player.setRate(incomingRate);
    } else {
      await incoming.player.setVolume(0);
      if ((incomingRate - _preparedRate).abs() > 0.001) {
        await incoming.player.setRate(incomingRate);
      }
    }
    if (bassSwap) {
      await _setEq(outgoing, bassCut: true, intensity: eqIntensity);
      await _setEq(incoming, highCut: true, intensity: eqIntensity);
    }
    await incoming.player.play();
    if (incomingStart > Duration.zero) {
      if (prepared) {
        await incoming.player.seek(incomingStart);
      } else if (await _waitReady(incoming)) {
        await incoming.player.seek(incomingStart);
      }
    }
    _preparedPath = null;

    final totalMs = duration.inMilliseconds.clamp(250, 20000);
    final steps = math.max(1, (totalMs / 40).ceil());
    var step = 0;
    var bassSwapped = false;

    _fadeTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) async {
      step++;
      final x = (step / steps).clamp(0.0, 1.0);
      final inGain = math.sin(x * math.pi / 2);
      final outGain = math.cos(x * math.pi / 2);

      await incoming.player.setVolume(
        inGain * _userVolume * incoming.gain * _preampGain * 100,
      );
      await outgoing.player.setVolume(
        outGain * _userVolume * outgoing.gain * _preampGain * 100,
      );

      if (bassSwap && !bassSwapped && x >= 0.5) {
        bassSwapped = true;
        await _setEq(incoming);
        await _setEq(
          outgoing,
          bassCut: true,
          highCut: true,
          intensity: eqIntensity,
        );
      }

      if (step >= steps) {
        timer.cancel();
        _fadeTimer = null;
        await outgoing.stop();
        await outgoing.player.setVolume(
          _userVolume * outgoing.gain * _preampGain * 100,
        );
        await incoming.player.setVolume(
          _userVolume * incoming.gain * _preampGain * 100,
        );
        await _applyBaseEq(incoming);
        await _setEq(outgoing);
      }
    });
  }

  Future<void> _setEq(
    _Deck deck, {
    bool bassCut = false,
    bool highCut = false,
    double intensity = 0.6,
  }) async {
    if (!bassCut && !highCut) {
      await _setFilter(deck, '');
      return;
    }

    final strength = intensity.clamp(0.0, 1.0);
    final filters = <String>[];
    if (bassCut) {
      filters.add(
        'equalizer=f=60:t=q:w=1:g=${(-20.0 * strength).toStringAsFixed(1)}',
      );
      filters.add(
        'equalizer=f=120:t=q:w=1:g=${(-18.0 * strength).toStringAsFixed(1)}',
      );
    }
    if (highCut) {
      filters.add(
        'equalizer=f=7000:t=q:w=1:g=${(-16.0 * strength).toStringAsFixed(1)}',
      );
      filters.add(
        'equalizer=f=11000:t=q:w=1:g=${(-18.0 * strength).toStringAsFixed(1)}',
      );
    }

    await _setFilter(
      deck,
      'format=s16,lavfi=[${filters.join(',')}]',
    );
  }

  Future<void> _setFilter(_Deck deck, String filter) async {
    try {
      final platform = deck.player.platform;
      if (platform == null) return;
      await (platform as dynamic).setProperty('af', filter);
    } catch (_) {}
  }

  void rampRateTo(double target, Duration duration) {
    _rateTimer?.cancel();
    final steps = math.max(1, (duration.inMilliseconds / 50).ceil());
    final start = _a.player.state.rate;
    var step = 0;
    _rateTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      step++;
      final x = (step / steps).clamp(0.0, 1.0);
      final value = start + (target - start) * x;
      await _a.player.setRate(value);
      if (step >= steps) timer.cancel();
    });
  }

  Future<void> _cancelTransitions() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _rateTimer?.cancel();
    _rateTimer = null;
  }

  Future<void> dispose() async {
    await _cancelTransitions();
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _playSub?.cancel();
    await _compSub?.cancel();
    await _decks[0].dispose();
    await _decks[1].dispose();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _playingCtrl.close();
    await _completedCtrl.close();
  }
}
