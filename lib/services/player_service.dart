import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../util/eq_graph.dart';
import '../util/eq_model.dart';
import '../util/gain_calculation.dart';
import '../util/log.dart';

class _Deck {
  _Deck() : player = Player();

  final Player player;
  String? path;
  double gain = 1;
  double? peakDb;
  EqState eq = EqState.flat;
  double transitionBassCut = 0;
  double transitionHighCut = 0;
  double transitionIntensity = 0.6;

  Future<void> open(String path, {double linearGain = 0}) async {
    this.path = path;
    await player.open(Media(Uri.file(path).toString()), play: false);
    await player.setVolume(mpvVolumeForLinearGain(linearGain));
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
  double _preampDb = 0;
  EqState _currentEq = EqState.flat;
  bool _shelfFiltersUnavailable = false;
  Completer<void>? _fadeCompleter;

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
    double? peakDb,
    Duration startAt = Duration.zero,
  }) async {
    await _cancelTransitions();
    await _incoming.stop();
    _preparedPath = null;
    _bindActive();
    _a.eq = _currentEq;
    await _applyEq(_a);
    _a.gain = clampFinite(gain, 0.0, maximumMpvLinearGain, fallback: 1.0);
    _a.peakDb = peakDb;
    await _configureMpv(_a);
    logLine(
      'deck load: $path (rate $rate, gain ${_a.gain.toStringAsFixed(2)}, '
      'peakDb=$peakDb, start ${startAt.inMilliseconds}ms)',
    );
    await _a.open(path, linearGain: _deckLinearGain(_a));
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

  Future<void> prepareIncoming(
    String path, {
    double rate = 1,
    double? peakDb,
  }) async {
    if (_fadeTimer != null || _preparedPath == path) return;
    await _incoming.stop();
    _preparedPath = null;
    _incoming.eq = _currentEq;
    await _applyEq(_incoming);
    _incoming.peakDb = peakDb;
    await _configureMpv(_incoming);
    await _incoming.open(path, linearGain: 0);
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
    _userVolume = clampFinite(volume, 0.0, 1.0, fallback: 0.0);
    if (_fadeTimer != null) return;
    await _applyDeckVolume(_a);
  }

  Future<void> setPreamp(double db) async {
    _preampDb = clampFinite(db, -12.0, 6.0);
    if (_fadeTimer == null) {
      await _applyDeckVolume(_a);
    }
  }

  Future<void> setTrackGain(double gain, {double? peakDb}) async {
    _a.gain = clampFinite(gain, 0.0, maximumMpvLinearGain, fallback: 1.0);
    _a.peakDb = peakDb;
    if (_fadeTimer == null) {
      await _applyDeckVolume(_a);
    }
  }

  Future<void> setBaseEq({required double bass, required double treble}) async {
    return setEq(EqState.migratedFromLegacy(bassDb: bass, trebleDb: treble));
  }

  Future<void> setEq(EqState eq) async {
    _currentEq = eq.normalized();
    for (final deck in _decks) {
      deck.eq = _currentEq;
      await _applyEq(deck);
    }
    if (_fadeTimer == null) {
      await _applyDeckVolume(_a);
    }
  }

  bool get _preferShelfFilters {
    if (_shelfFiltersUnavailable) return false;
    return defaultTargetPlatform != TargetPlatform.android;
  }

  Future<void> _applyEq(_Deck deck) async {
    var settings = EqSettings(
      baseEq: deck.eq,
      transitionBassCut: deck.transitionBassCut,
      transitionHighCut: deck.transitionHighCut,
      transitionIntensity: deck.transitionIntensity,
      useShelves: _preferShelfFilters,
    );
    var applied = await _setFilter(deck, buildEqFilter(settings));
    if (!applied && settings.useShelves) {
      _shelfFiltersUnavailable = true;
      settings = settings.copyWith(useShelves: false);
      logLine(
        'audio filter fallback: shelf filters unavailable; '
        'using peaking equalizer',
      );
      await _setFilter(deck, buildEqFilter(settings));
    }
  }

  double _eqHeadroomGainFor(_Deck deck) => deck.eq.smartHeadroomGain;

  double _deckLinearGain(_Deck deck, {double fadeGain = 1.0}) {
    var linearGain = combinedLinearGain(
      userVolume: _userVolume,
      trackGain: deck.gain,
      preampDb: _preampDb,
      fadeGain: fadeGain,
      eqHeadroomGain: _eqHeadroomGainFor(deck),
    );
    final peakDb = deck.peakDb;
    if (peakDb != null && peakDb.isFinite) {
      final ceilingGain = dbToLinearGain(peakCeilingDb - peakDb);
      if (linearGain > ceilingGain) linearGain = ceilingGain;
    }
    return linearGain;
  }

  Future<void> _applyDeckVolume(_Deck deck, {double fadeGain = 1.0}) async {
    await deck.player.setVolume(
      mpvVolumeForLinearGain(_deckLinearGain(deck, fadeGain: fadeGain)),
    );
  }

  Future<void> _configureMpv(_Deck deck) async {
    try {
      final platform = deck.player.platform;
      if (platform == null) {
        logLine('audio property error: volume-max platform unavailable');
        return;
      }
      await (platform as dynamic).setProperty('volume-max', '1000');
    } catch (error) {
      logLine('audio property error: volume-max error=$error');
    }
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
    double? incomingPeakDb,
    bool bassSwap = false,
    double eqIntensity = 0.6,
  }) async {
    if (_fadeTimer != null) {
      return _fadeCompleter?.future ?? Future<void>.value();
    }

    final outgoing = _a;
    final incoming = _incoming;

    final prepared = _preparedPath == nextPath;
    incoming.eq = _currentEq;
    incoming.gain = clampFinite(
      incomingGain,
      0.0,
      maximumMpvLinearGain,
      fallback: 1.0,
    );
    incoming.peakDb = incomingPeakDb;
    logLine('deck crossfade -> $nextPath (rate $incomingRate)');
    if (!prepared) {
      await _configureMpv(incoming);
      await incoming.open(nextPath, linearGain: 0);
      await incoming.player.setRate(incomingRate);
    } else {
      await incoming.player.setVolume(0);
      if ((incomingRate - _preparedRate).abs() > 0.001) {
        await incoming.player.setRate(incomingRate);
      }
    }
    _active = 1 - _active;
    _bindActive();
    outgoing.eq = _currentEq;
    incoming.eq = _currentEq;
    await _setTransitionEq(outgoing, bassCut: bassSwap, intensity: eqIntensity);
    await _setTransitionEq(incoming, highCut: bassSwap, intensity: eqIntensity);
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
    final completer = _fadeCompleter = Completer<void>();

    _fadeTimer = Timer.periodic(const Duration(milliseconds: 40), (
      timer,
    ) async {
      step++;
      final x = (step / steps).clamp(0.0, 1.0);
      final gains = equalPowerCrossfadeGains(x);
      final inGain = gains.incoming;
      final outGain = gains.outgoing;

      await _applyDeckVolume(incoming, fadeGain: inGain);
      await _applyDeckVolume(outgoing, fadeGain: outGain);

      if (bassSwap && !bassSwapped && x >= 0.5) {
        bassSwapped = true;
        await _clearTransition(incoming);
        await _setTransitionEq(
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
        await _clearTransition(incoming);
        await _clearTransition(outgoing);
        await _applyDeckVolume(incoming);
        if (identical(_fadeCompleter, completer)) _fadeCompleter = null;
        if (!completer.isCompleted) completer.complete();
      }
    });

    return completer.future;
  }

  Future<void> _setTransitionEq(
    _Deck deck, {
    bool bassCut = false,
    bool highCut = false,
    double intensity = 0.6,
  }) async {
    deck.transitionBassCut = bassCut ? 1.0 : 0.0;
    deck.transitionHighCut = highCut ? 1.0 : 0.0;
    deck.transitionIntensity = clampFinite(intensity, 0.0, 1.0, fallback: 0.6);
    await _applyEq(deck);
  }

  Future<void> _clearTransition(_Deck deck) async {
    deck.transitionBassCut = 0.0;
    deck.transitionHighCut = 0.0;
    await _applyEq(deck);
  }

  Future<bool> _setFilter(_Deck deck, String filter) async {
    try {
      final platform = deck.player.platform;
      if (platform == null) {
        logLine(
          'audio filter error: path=${deck.path} filter=$filter '
          'error=player platform unavailable',
        );
        return false;
      }
      await (platform as dynamic).setProperty('af', filter);
      return true;
    } catch (error) {
      logLine(
        'audio filter error: path=${deck.path} filter=$filter error=$error',
      );
      return false;
    }
  }

  void rampRateTo(double target, Duration duration) {
    _rateTimer?.cancel();
    final steps = math.max(1, (duration.inMilliseconds / 50).ceil());
    final start = _a.player.state.rate;
    var step = 0;
    _rateTimer = Timer.periodic(const Duration(milliseconds: 50), (
      timer,
    ) async {
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
    final completer = _fadeCompleter;
    _fadeCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('crossfade cancelled'));
    }
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
