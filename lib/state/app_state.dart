import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/native_audio_engine.dart';
import '../models/track.dart';
import '../models/track_analysis.dart';
import '../services/device_analyzer.dart';
import '../services/library_repository.dart';
import '../services/media_notification.dart';
import '../services/player_service.dart';
import '../util/eq_model.dart';
import '../util/gain_calculation.dart';
import '../util/log.dart';

typedef _FeatureStats = ({List<double> means, List<double> stds});

class AppState extends ChangeNotifier {
  AppState({required this.repository, required this.player});

  final LibraryRepository repository;
  final PlayerService player;

  List<Track> library = [];
  bool loading = true;
  bool scanning = false;
  int scanDone = 0;
  int scanTotal = 0;
  String scanCurrent = '';
  String? error;

  List<Track> queue = [];
  int index = -1;

  bool automix = true;
  bool crossfade = true;
  bool gapless = true;
  bool normalize = true;
  bool useReplayGain = true;
  bool useNativeLimiter = false;
  bool skipSilence = true;
  bool smartShuffle = false;
  bool autoAnalyze = true;
  int analysisScanSeconds = 30;
  bool analyzing = false;
  bool notificationPermission = false;
  bool notificationsEnabled = false;
  bool notificationChannelBlocked = false;
  int notificationChannelImportance = -1;
  String? notificationError;
  int analysisDone = 0;
  int analysisTotal = 0;
  String analysisCurrent = '';
  String transitionStyle = 'auto';
  bool shuffle = false;
  bool repeat = false;
  double crossfadeSeconds = 8;
  List<String> musicRoots = [];
  double volume = 1;
  double preampDb = 0;
  AudioOutputProfile eqOutput = AudioOutputProfile.speaker;
  Map<AudioOutputProfile, EqState> eqProfiles = {
    for (final profile in AudioOutputProfile.values) profile: EqState.flat,
  };

  Track? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;

  List<Track> get upNext => index >= 0 && index + 1 < queue.length
      ? queue.sublist(index + 1)
      : const [];

  double get scanFraction =>
      scanTotal == 0 ? 0 : (scanDone / scanTotal).clamp(0, 1);

  SharedPreferences? _prefs;
  List<Track>? _preShuffle;
  final math.Random _random = math.Random();
  final Set<String> _smartPlayed = {};
  final Set<String> _analysisFailed = {};
  final DeviceAnalyzer _analyzer = DeviceAnalyzer();
  final MediaNotification _mediaNotification = MediaNotification.instance;
  StreamSubscription<void>? _playerSub;
  StreamSubscription<bool>? _playingSub;
  Timer? _mixTimer;
  Timer? _eqApplyTimer;
  DateTime _lastMediaPush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _mixing = false;
  bool _wasMixing = false;
  int? _preloadedIndex;
  bool _advancing = false;
  bool _disposed = false;

  bool get isPlaying => player.playing;
  bool get isMixing => player.isMixing || _mixing;
  EqState get currentEq => eqProfiles[eqOutput] ?? EqState.flat;
  List<double> get eqGainsDb => currentEq.gainsDb;
  bool get eqBypass => currentEq.bypass;
  double get eqMaxResponseDb => currentEq.maximumResponseDbFor(eqOutput);
  double get eqSmartHeadroomDb => currentEq.smartHeadroomDbFor(eqOutput);
  double get eqSmartHeadroomGain => currentEq.smartHeadroomGainFor(eqOutput);
  String get selectedEqPresetId => currentEq.selectedPresetId;
  NativeAudioEngineStatus get nativeAudioEngineStatus =>
      NativeAudioEngineProbe.status;

  Future<void> init() async {
    await _mediaNotification.init(
      onPlay: () => player.play(),
      onPause: () => player.pause(),
      onToggle: togglePlay,
      onNext: next,
      onPrevious: previous,
      onStop: stopPlayback,
      onSeek: seek,
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(refreshNotificationStatus());
    }
    _prefs = await SharedPreferences.getInstance();
    final storedRoots = _prefs!.getStringList('musicRoots');
    if (storedRoots != null && storedRoots.isNotEmpty) {
      musicRoots = storedRoots;
    } else {
      final legacy = _prefs!.getString('musicRoot');
      musicRoots = legacy != null ? [legacy] : const [];
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      const oldDefaults = [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Android/media',
      ];
      if (musicRoots.length == oldDefaults.length &&
          musicRoots.every(oldDefaults.contains)) {
        musicRoots = [];
      }
      await repository.ensurePermission();
    }
    await _prefs!.setStringList('musicRoots', musicRoots);
    automix = _prefs!.getBool('automix') ?? true;
    crossfade = _prefs!.getBool('crossfade') ?? true;
    gapless = _prefs!.getBool('gapless') ?? true;
    normalize = _prefs!.getBool('normalize') ?? true;
    useReplayGain = _prefs!.getBool('useReplayGain') ?? true;
    useNativeLimiter = _prefs!.getBool('useNativeLimiter') ?? false;
    skipSilence = _prefs!.getBool('skipSilence') ?? true;
    smartShuffle = _prefs!.getBool('smartShuffle') ?? false;
    autoAnalyze = _prefs!.getBool('autoAnalyze') ?? true;
    analysisScanSeconds = _prefs!.getInt('analysisScanSeconds') ?? 30;
    if (analysisScanSeconds != 0) {
      analysisScanSeconds = analysisScanSeconds.clamp(15, 300);
    }
    transitionStyle = _prefs!.getString('transitionStyle') ?? 'auto';
    crossfadeSeconds = _prefs!.getDouble('crossfadeSeconds') ?? 8;
    final storedVolume = _prefs!.getDouble('volume');
    volume = clampFinite(storedVolume ?? 1.0, 0.0, 1.0, fallback: 1.0);
    if (storedVolume == null || volume != storedVolume) {
      await _prefs!.setDouble('volume', volume);
    }
    final storedPreampDb = _prefs!.getDouble('preampDb');
    preampDb = clampFinite(storedPreampDb ?? -1.0, -12.0, 6.0, fallback: -1.0);
    if (storedPreampDb == null || preampDb != storedPreampDb) {
      await _prefs!.setDouble('preampDb', preampDb);
    }
    final storedBassDb = _prefs!.getDouble('bassDb');
    final legacyBassDb = clampFinite(storedBassDb ?? 0.0, -12.0, 12.0);
    final storedTrebleDb = _prefs!.getDouble('trebleDb');
    final legacyTrebleDb = clampFinite(storedTrebleDb ?? 0.0, -12.0, 12.0);
    await _loadEqProfiles(bassDb: legacyBassDb, trebleDb: legacyTrebleDb);

    library = (await repository.loadCached())
        .where((track) => _isUnderAnyRoot(track.path))
        .toList();
    loading = false;
    logLine('library: ${library.length} tracks, roots=$musicRoots');
    _safeNotify();
    if (autoAnalyze) {
      unawaited(_autoAnalyzeWindow());
    }

    _playerSub = player.completedStream.listen((_) {
      if (!_mixing) next();
    });
    _playingSub = player.playingStream.listen((playing) {
      _safeNotify();
      _publishMediaState();
      if ((!playing || defaultTargetPlatform != TargetPlatform.android) &&
          autoAnalyze) {
        unawaited(_autoAnalyzeWindow());
      }
    });
    _mixTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _checkAutoMix();
      _mediaTick();
    });
    await player.setVolume(volume);
    await player.setPreamp(preampDb);
    player.setUseNativeLimiter(useNativeLimiter);
    await player.setEq(currentEq, outputProfile: eqOutput);
    _publishMediaState();

    if (const bool.fromEnvironment('CRATE_AUTOPLAY') && library.isNotEmpty) {
      unawaited(playTrack(library.first));
      Timer(const Duration(seconds: 5), () {
        logLine(
          'autoplay check: playing=${player.playing} '
          'pos=${player.position} dur=${player.duration}',
        );
      });
    }

    if (const bool.fromEnvironment('CRATE_MIX_TEST') && library.isNotEmpty) {
      Timer(const Duration(seconds: 6), () async {
        var track = current;
        if (track?.analysis == null) {
          final analyzed = library.where((t) => t.analysis != null).toList();
          if (analyzed.isNotEmpty) {
            track = analyzed.first;
            await playTrack(track, context: library);
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
        final analysis = track?.analysis;
        if (track == null || analysis == null) {
          logLine('mix test: sin análisis para ${track?.title}');
          return;
        }
        final fade = _fadeSecondsFor(track);
        final target = analysis.audibleEnd - fade - 1.5;
        logLine(
          'mix test: seek ${target.toStringAsFixed(2)}s '
          '(end=${analysis.audibleEnd}, fade=${fade.toStringAsFixed(2)}, '
          'bpm=${analysis.bpm}, mixIn=${analysis.mixIn})',
        );
        await player.seek(Duration(milliseconds: (target * 1000).round()));
      });
      Timer(const Duration(seconds: 22), () {
        logLine(
          'mix test result: index=$index current=${current?.title} '
          'playing=${player.playing} mixing=$isMixing '
          'pos=${player.position} rate=${player.rate}',
        );
      });
    }
  }

  Future<void> rescan() async {
    if (scanning) return;
    scanning = true;
    scanDone = 0;
    scanTotal = 0;
    scanCurrent = '';
    error = null;
    _safeNotify();

    try {
      final tracks = await repository.scanRoots(
        musicRoots,
        onProgress: (done, total, current) {
          scanDone = done;
          scanTotal = total;
          scanCurrent = current;
          _safeNotify();
        },
      );
      library = tracks;
      _smartPlayed.clear();
      _reconcileQueue();
    } catch (e) {
      error = 'No se pudo leer la biblioteca: $e';
    }

    scanning = false;
    loading = false;
    _safeNotify();
    if (autoAnalyze) {
      unawaited(_autoAnalyzeWindow());
    }
  }

  void _reconcileQueue() {
    final byPath = {for (final t in library) t.path: t};
    final currentPath = current?.path;
    final rebuilt = <Track>[];
    for (final t in queue) {
      final match = byPath[t.path];
      if (match != null) rebuilt.add(match);
    }
    queue = rebuilt;
    if (currentPath != null) {
      index = queue.indexWhere((t) => t.path == currentPath);
    } else {
      index = queue.isEmpty ? -1 : index.clamp(0, queue.length - 1);
    }
  }

  Future<void> playTrack(Track track, {List<Track>? context}) async {
    final source = context ?? library;
    final position = source.indexWhere((t) => t.id == track.id);
    queue = List<Track>.of(source);
    index = position >= 0 ? position : 0;
    _preShuffle = null;
    await _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final track = current;
    if (track == null) {
      unawaited(_mediaNotification.clear());
      return;
    }
    _mixing = false;
    _preloadedIndex = null;
    _safeNotify();
    _publishMediaState();
    try {
      await player.load(
        track.path,
        gain: _gainFor(track),
        peakDb: _peakDbFor(track),
        startAt: _startOffsetFor(track),
      );
      _publishMediaState();
    } catch (_) {
      error = 'No se pudo reproducir "${track.title}"';
      _safeNotify();
    }
  }

  Future<void> togglePlay() async {
    if (current == null) {
      if (library.isNotEmpty) await playTrack(library.first);
      return;
    }
    if (player.playing) {
      await player.pause();
    } else {
      if (defaultTargetPlatform == TargetPlatform.android) {
        unawaited(_mediaNotification.ensurePermission());
      }
      if (player.completed) {
        await player.seek(Duration.zero);
      }
      await player.play();
    }
    _safeNotify();
    _publishMediaState();
  }

  Future<void> next() async {
    if (smartShuffle && library.length > 1) {
      final pick = _smartNextTrack();
      if (pick != null) {
        await playTrack(pick, context: library);
        return;
      }
    }
    if (queue.isEmpty) return;
    if (index + 1 < queue.length) {
      index++;
      await _loadCurrent();
    } else if (repeat) {
      index = 0;
      await _loadCurrent();
    } else {
      await player.pause();
      await player.seek(Duration.zero);
      _safeNotify();
      _publishMediaState();
    }
  }

  Future<void> previous() async {
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
      _safeNotify();
      _publishMediaState();
      return;
    }
    if (index > 0) {
      index--;
      await _loadCurrent();
    } else {
      await player.seek(Duration.zero);
      _safeNotify();
      _publishMediaState();
    }
  }

  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= queue.length) return;
    index = i;
    await _loadCurrent();
  }

  void playNext(Track track) {
    if (queue.isEmpty || index < 0) {
      queue = [track];
      index = 0;
    } else {
      queue.insert(index + 1, track);
    }
    _safeNotify();
  }

  void addToQueue(Track track) {
    queue.add(track);
    if (index < 0) index = 0;
    _safeNotify();
  }

  void removeFromQueue(int i) {
    if (i < 0 || i >= queue.length) return;
    final wasCurrent = i == index;
    queue.removeAt(i);
    if (queue.isEmpty) {
      index = -1;
      player.pause();
      unawaited(_mediaNotification.clear());
    } else if (i < index) {
      index--;
    } else if (wasCurrent) {
      index = index.clamp(0, queue.length - 1);
      _loadCurrent();
    }
    _safeNotify();
  }

  void reorderQueue(int oldIndex, int newIndex, {bool adjusted = false}) {
    if (oldIndex < 0 || oldIndex >= queue.length) return;
    if (!adjusted && newIndex > oldIndex) newIndex--;
    newIndex = newIndex.clamp(0, queue.length - 1);
    final currentTrack = current;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    if (currentTrack != null) {
      index = queue.indexWhere((t) => t.id == currentTrack.id);
    }
    _safeNotify();
  }

  Future<void> _loadEqProfiles({
    required double bassDb,
    required double trebleDb,
  }) async {
    final saved = <AudioOutputProfile, String?>{};
    var hasAnySaved = false;
    for (final profile in AudioOutputProfile.values) {
      final encoded = _prefs!.getString('eqProfile_${profile.key}');
      saved[profile] = encoded;
      hasAnySaved = hasAnySaved || encoded != null;
    }
    final migrated = EqState.migratedFromLegacy(
      bassDb: bassDb,
      trebleDb: trebleDb,
    );
    for (final profile in AudioOutputProfile.values) {
      final encoded = saved[profile];
      eqProfiles[profile] = encoded == null
          ? (hasAnySaved ? EqState.flat : migrated)
          : EqState.decode(encoded);
    }
    eqOutput = audioOutputProfileFromKey(_prefs!.getString('eqOutput'));
    await _persistEqState();
  }

  Future<void> _persistEqState() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString('eqOutput', eqOutput.key);
    for (final profile in AudioOutputProfile.values) {
      await prefs.setString(
        'eqProfile_${profile.key}',
        (eqProfiles[profile] ?? EqState.flat).encode(),
      );
    }
  }

  Future<void> _applyCurrentEq() async {
    try {
      await player.setEq(currentEq, outputProfile: eqOutput);
    } catch (error) {
      logLine('eq apply error: $error');
    }
  }

  void _queueEqUpdate() {
    _eqApplyTimer?.cancel();
    unawaited(_persistEqState());
    _eqApplyTimer = Timer(const Duration(milliseconds: 60), () {
      unawaited(_applyCurrentEq());
    });
  }

  void selectEqOutput(AudioOutputProfile profile) {
    eqOutput = profile;
    if (profile == AudioOutputProfile.speaker) {
      eqProfiles[profile] = EqState.fromPreset('speaker_powerful');
    }
    _queueEqUpdate();
    _safeNotify();
  }

  void setEqBand(int index, double value) {
    if (index < 0 || index >= eqBandFrequencies.length) return;
    final gains = List<double>.of(currentEq.gainsDb);
    gains[index] = quantizeEqGain(value);
    eqProfiles[eqOutput] = currentEq.copyWith(
      gainsDb: gains,
      selectedPresetId: 'custom',
    );
    _queueEqUpdate();
    _safeNotify();
  }

  void applyEqPreset(String presetId) {
    final preset = eqPresetById(presetId);
    if (preset == null) return;
    eqProfiles[eqOutput] = EqState.fromPreset(presetId);
    _queueEqUpdate();
    _safeNotify();
  }

  void setEqBypass(bool value) {
    eqProfiles[eqOutput] = currentEq.withBypass(value);
    _queueEqUpdate();
    _safeNotify();
  }

  void resetEq() {
    applyEqPreset('flat');
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
    _publishMediaState();
  }

  Future<void> setVolume(double value) async {
    volume = clampFinite(value, 0.0, 1.0, fallback: 0.0);
    await player.setVolume(volume);
    _prefs?.setDouble('volume', volume);
    _safeNotify();
  }

  void setPreamp(double value) {
    preampDb = clampFinite(value, -12.0, 6.0);
    _prefs?.setDouble('preampDb', preampDb);
    player.setPreamp(preampDb);
    _safeNotify();
  }

  double _gainFor(Track? track) {
    final analysis = track?.analysis;
    final replayGain = useReplayGain ? track?.replayGain : null;
    return trackGainFor(
      normalize: normalize,
      lufs: analysis?.lufs,
      peakDb: analysis?.peakDb,
      truePeakDb: analysis?.truePeakDb,
      replayGainDb: replayGain?.effectiveTrackGainDb,
      replayGainPeakDb: replayGain?.effectiveTrackPeakDb,
    );
  }

  double? _peakDbFor(Track track) {
    var peakDb = track.analysis?.truePeakDb ?? track.analysis?.peakDb;
    final replayPeakDb = useReplayGain
        ? track.replayGain?.effectiveTrackPeakDb
        : null;
    if (replayPeakDb != null &&
        replayPeakDb.isFinite &&
        (peakDb == null || replayPeakDb > peakDb)) {
      peakDb = replayPeakDb;
    }
    return peakDb;
  }

  double _fadeSecondsFor(Track track) {
    var seconds = crossfadeSeconds;
    final analysis = track.analysis;
    if (analysis != null) {
      final bar = analysis.normalizedBarLength;
      if (bar > 0.2) {
        final bars = (seconds / bar).round().clamp(4, 8);
        seconds = bars * bar;
      }
    }
    return seconds.clamp(4.0, 24.0);
  }

  _TransitionStyle _styleFor(Track track) {
    final forced = _forcedStyle();
    if (forced != null) return forced;
    // Multi-genre: decide by the audio itself (tempo/energy), never by tags.
    final analysis = track.analysis;
    if (analysis != null) {
      final bpm = analysis.normalizedBpm;
      if (analysis.energy >= 0.72 && bpm >= 115) {
        return _TransitionStyle.dance;
      }
      if (analysis.energy <= 0.4 || bpm < 90) {
        return _TransitionStyle.ballad;
      }
      if (bpm >= 125) return _TransitionStyle.hipHop;
    }
    return _TransitionStyle.smooth;
  }

  _TransitionStyle? _forcedStyle() {
    switch (transitionStyle) {
      case 'latin':
        return _TransitionStyle.latin;
      case 'dance':
        return _TransitionStyle.dance;
      case 'hipHop':
        return _TransitionStyle.hipHop;
      case 'pop':
        return _TransitionStyle.pop;
      case 'ballad':
        return _TransitionStyle.ballad;
      case 'smooth':
        return _TransitionStyle.smooth;
      default:
        return null;
    }
  }

  void setTransitionStyle(String value) {
    transitionStyle = value;
    _prefs?.setString('transitionStyle', value);
    _safeNotify();
  }

  double _effectiveFadeSeconds(Track outTrack, Track inTrack) {
    var seconds = _fadeSecondsFor(outTrack);
    final outAnalysis = outTrack.analysis;
    final inAnalysis = inTrack.analysis;
    final bar = (outAnalysis != null && outAnalysis.normalizedBarLength > 0.2)
        ? outAnalysis.normalizedBarLength
        : 2.0;
    final style = _styleFor(outTrack);
    if (style == _TransitionStyle.dance || style == _TransitionStyle.latin) {
      seconds = math.max(seconds, 8 * bar);
    } else if (style == _TransitionStyle.hipHop) {
      seconds = math.min(seconds, 4 * bar);
    } else if (style == _TransitionStyle.ballad) {
      seconds = math.max(seconds, 10 * bar);
    }

    if (outAnalysis != null && inAnalysis != null) {
      final ratio =
          (outAnalysis.normalizedBpm > 0 && inAnalysis.normalizedBpm > 0)
          ? outAnalysis.normalizedBpm / inAnalysis.normalizedBpm
          : 1.0;
      if ((ratio - 1).abs() > 0.08) {
        seconds = math.min(seconds, 4 * bar);
      }
    }
    return seconds.clamp(2.0, 24.0);
  }

  Duration _startOffsetFor(Track track) {
    if (!skipSilence) return Duration.zero;
    final leadIn = track.analysis?.leadIn ?? 0;
    if (leadIn <= 0.25) return Duration.zero;
    final milliseconds = (leadIn * 1000).round() - 120;
    return Duration(milliseconds: milliseconds > 0 ? milliseconds : 0);
  }

  void _maybeSkipSilence() {
    if (!skipSilence || _advancing || !player.playing) return;
    final analysis = current?.analysis;
    if (analysis == null || analysis.audibleEnd <= 0) return;
    final end = Duration(milliseconds: (analysis.audibleEnd * 1000).round());
    if (player.position < end - const Duration(milliseconds: 200)) return;
    _advancing = true;
    unawaited(next().whenComplete(() => _advancing = false));
  }

  void _checkAutoMix() {
    final nowMixing = player.isMixing || _mixing;
    if (nowMixing != _wasMixing) {
      _wasMixing = nowMixing;
      _safeNotify();
    }
    if (!automix || !crossfade) {
      _maybeSkipSilence();
      return;
    }
    if (_mixing || player.isMixing) return;
    if (crossfadeSeconds <= 0 || !player.playing) return;
    final outTrack = current;
    if (outTrack == null) return;
    final nextIndex = _nextIndex();
    if (nextIndex < 0) return;

    final nextTrack = queue[nextIndex];
    final fadeSeconds = _effectiveFadeSeconds(outTrack, nextTrack);
    final analysis = outTrack.analysis;
    Duration end;
    if (analysis != null && analysis.version >= 2 && analysis.mixOut > 0) {
      end = Duration(milliseconds: (analysis.mixOut * 1000).round());
    } else if (analysis != null && analysis.audibleEnd > 0) {
      end = Duration(milliseconds: (analysis.audibleEnd * 1000).round());
    } else {
      end = player.duration;
    }
    if (end <= Duration.zero) return;
    final remaining = end - player.position;
    final window = Duration(milliseconds: (fadeSeconds * 1000).round());
    final preloadWindow = Duration(
      milliseconds: ((fadeSeconds + 15) * 1000).round(),
    );
    if (remaining <= preloadWindow &&
        remaining > window &&
        _preloadedIndex != nextIndex) {
      var preloadRate = 1.0;
      final outA = outTrack.analysis;
      final inA = nextTrack.analysis;
      if (outA != null &&
          inA != null &&
          outA.normalizedBpm > 0 &&
          inA.normalizedBpm > 0) {
        final ratio = outA.normalizedBpm / inA.normalizedBpm;
        if ((ratio - 1).abs() <= 0.08) {
          preloadRate = ratio.clamp(0.92, 1.08).toDouble();
        }
      }
      unawaited(
        player.prepareIncoming(
          nextTrack.path,
          rate: preloadRate,
          peakDb: _peakDbFor(nextTrack),
        ),
      );
      _preloadedIndex = nextIndex;
    }
    if (remaining > window || remaining <= const Duration(milliseconds: 120)) {
      return;
    }
    _startCrossfade(nextIndex, fadeSeconds);
  }

  int _nextIndex() {
    if (queue.isEmpty) return -1;
    if (index + 1 < queue.length) return index + 1;
    if (repeat) return 0;
    return -1;
  }

  Future<void> _startCrossfade(int nextIndex, double fadeSeconds) async {
    if (_mixing) return;
    _preloadedIndex = null;
    final outTrack = current;
    if (outTrack == null) return;
    final inTrack = queue[nextIndex];

    _mixing = true;
    var targetRate = 1.0;
    final style = _styleFor(outTrack);
    var eqIntensity = 0.6;
    if (style == _TransitionStyle.dance) {
      eqIntensity = 0.85;
    } else if (style == _TransitionStyle.hipHop) {
      eqIntensity = 1.0;
    } else if (style == _TransitionStyle.latin) {
      eqIntensity = 0.5;
    } else if (style == _TransitionStyle.ballad) {
      eqIntensity = 0.3;
    } else if (style == _TransitionStyle.pop) {
      eqIntensity = 0.65;
    }
    final outAnalysis = outTrack.analysis;
    final inAnalysis = inTrack.analysis;
    if (outAnalysis != null && inAnalysis != null) {
      final ratio =
          (outAnalysis.normalizedBpm > 0 && inAnalysis.normalizedBpm > 0)
          ? outAnalysis.normalizedBpm / inAnalysis.normalizedBpm
          : 1.0;
      if ((ratio - 1).abs() <= 0.08) {
        targetRate = ratio.clamp(0.92, 1.08).toDouble();
      }
    }
    logLine(
      'transition: style=${style.name} '
      'fade=${fadeSeconds.toStringAsFixed(1)}s '
      'eq=${eqIntensity.toStringAsFixed(2)}',
    );
    var incomingStart = Duration.zero;
    if (inAnalysis != null &&
        inAnalysis.mixIn > 0.05 &&
        (inAnalysis.duration <= 0 ||
            inAnalysis.mixIn < inAnalysis.duration - 5)) {
      var startMs = inAnalysis.mixIn * 1000;

      if (outAnalysis != null &&
          outAnalysis.downbeats.isNotEmpty &&
          outAnalysis.barLength > 0.2) {
        final positionSeconds = player.position.inMilliseconds / 1000.0;
        double? lastDownbeat;
        for (final downbeat in outAnalysis.downbeats) {
          if (downbeat <= positionSeconds + 0.001) {
            lastDownbeat = downbeat;
          } else {
            break;
          }
        }
        if (lastDownbeat != null) {
          var offset = positionSeconds - lastDownbeat;
          if (offset > outAnalysis.barLength / 2) {
            offset -= outAnalysis.barLength;
          }
          startMs += offset * 1000;
        }
      }

      if (inAnalysis.barLength > 0.2) {
        while (startMs < 0) {
          startMs += inAnalysis.barLength * 1000;
        }
      }
      final maxStart = inAnalysis.duration > 0
          ? (inAnalysis.duration - 5) * 1000
          : double.infinity;
      if (startMs > maxStart) {
        startMs = inAnalysis.mixIn * 1000;
      }
      incomingStart = Duration(milliseconds: startMs.round());
    }

    index = nextIndex;
    _safeNotify();

    try {
      await player.crossfadeTo(
        inTrack.path,
        duration: Duration(milliseconds: (fadeSeconds * 1000).round()),
        incomingRate: targetRate,
        incomingStart: incomingStart,
        incomingGain: _gainFor(inTrack),
        incomingPeakDb: _peakDbFor(inTrack),
        bassSwap: true,
        eqIntensity: eqIntensity,
      );
      if ((targetRate - 1).abs() > 0.001) {
        player.rampRateTo(1, const Duration(milliseconds: 2200));
      }
    } catch (_) {
      error = 'No se pudo mezclar con "${inTrack.title}"';
    } finally {
      _mixing = false;
      _safeNotify();
    }
  }

  Future<void> buildAutoMixQueue() async {
    if (library.isEmpty) return;
    final stats = _computeFeatureStats();
    final start = current ?? library.first;
    final rest = List<Track>.of(library)
      ..removeWhere((track) => track.id == start.id);

    final ordered = <Track>[start];
    var last = start;
    while (rest.isNotEmpty) {
      var bestIndex = 0;
      var bestCost = double.infinity;
      for (var i = 0; i < rest.length; i++) {
        final cost = _transitionCost(last, rest[i], stats);
        if (cost < bestCost) {
          bestCost = cost;
          bestIndex = i;
        }
      }
      final next = rest.removeAt(bestIndex);
      ordered.add(next);
      last = next;
    }

    queue = ordered;
    index = 0;
    _preShuffle = null;
    _mixing = false;
    _safeNotify();
    await _loadCurrent();
  }

  double _transitionCost(Track a, Track b, [_FeatureStats? stats]) {
    final aa = a.analysis;
    final bb = b.analysis;
    if (aa == null ||
        bb == null ||
        aa.normalizedBpm <= 0 ||
        bb.normalizedBpm <= 0) {
      return 1.0;
    }
    var cost = ((aa.normalizedBpm - bb.normalizedBpm).abs() / 12)
        .clamp(0.0, 4.0)
        .toDouble();
    cost += (aa.energy - bb.energy).abs() * 3;
    if (smartShuffle && stats != null) {
      final similarity = _featureSimilarity(a, b, stats);
      if (similarity != null) {
        cost += (1 - similarity) * 2.0;
      }
    }
    return cost;
  }

  _FeatureStats? _computeFeatureStats() {
    final usable = library.where((track) {
      final features = track.analysis?.features;
      return features != null && features.length >= 8;
    }).toList();
    if (usable.length < 2) return null;

    final dimensions = usable.first.analysis!.features.length;
    final means = List<double>.filled(dimensions, 0);
    var count = 0;
    for (final track in usable) {
      final features = track.analysis!.features;
      if (features.length != dimensions) continue;
      for (var i = 0; i < dimensions; i++) {
        means[i] += features[i];
      }
      count++;
    }
    if (count < 2) return null;
    for (var i = 0; i < dimensions; i++) {
      means[i] /= count;
    }

    final variances = List<double>.filled(dimensions, 0);
    for (final track in usable) {
      final features = track.analysis!.features;
      if (features.length != dimensions) continue;
      for (var i = 0; i < dimensions; i++) {
        final delta = features[i] - means[i];
        variances[i] += delta * delta;
      }
    }
    final stds = List<double>.filled(dimensions, 1);
    for (var i = 0; i < dimensions; i++) {
      final value = math.sqrt(variances[i] / count);
      stds[i] = value < 1e-6 ? 1 : value;
    }
    return (means: means, stds: stds);
  }

  double? _featureSimilarity(Track a, Track b, _FeatureStats stats) {
    final fa = a.analysis?.features;
    final fb = b.analysis?.features;
    if (fa == null || fb == null) return null;
    if (fa.length != stats.means.length || fb.length != stats.means.length) {
      return null;
    }
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < fa.length; i++) {
      final va = (fa[i] - stats.means[i]) / stats.stds[i];
      final vb = (fb[i] - stats.means[i]) / stats.stds[i];
      dot += va * vb;
      normA += va * va;
      normB += vb * vb;
    }
    if (normA <= 0 || normB <= 0) return null;
    return dot / math.sqrt(normA * normB);
  }

  Future<({bool ok, int entries, int matches, int total})> importAnalysis(
    String sourcePath,
  ) async {
    final imported = await repository.importAnalysis(sourcePath);
    if (!imported) {
      return (ok: false, entries: 0, matches: 0, total: library.length);
    }
    final analysis = await repository.loadAnalysis();
    await reloadAnalysis();
    final matches = library.where((t) => t.analysis != null).length;
    return (
      ok: true,
      entries: analysis.length,
      matches: matches,
      total: library.length,
    );
  }

  Future<void> reloadAnalysis() async {
    final cached = await repository.loadCached();
    final filtered = cached
        .where((track) => _isUnderAnyRoot(track.path))
        .toList();
    if (filtered.isEmpty) {
      await rescan();
      return;
    }
    library = filtered;
    _smartPlayed.clear();
    _reconcileQueue();
    _safeNotify();
    if (autoAnalyze) {
      unawaited(_autoAnalyzeWindow());
    }
  }

  Future<void> _autoAnalyzeWindow() async {
    if (!autoAnalyze || analyzing) return;
    if (defaultTargetPlatform == TargetPlatform.android && player.playing) {
      return;
    }
    final targets = <Track>[];
    final currentTrack = current;
    if (currentTrack != null) {
      targets.add(currentTrack);
      for (var i = index + 1; i < queue.length && targets.length < 4; i++) {
        targets.add(queue[i]);
      }
    } else {
      targets.addAll(library.take(3));
    }
    final pending = targets
        .where((t) => t.analysis == null && !_analysisFailed.contains(t.id))
        .toList();
    await _analyzeTracks(pending);
  }

  Future<void> _analyzeTracks(List<Track> pending) async {
    if (analyzing || pending.isEmpty) return;
    analyzing = true;
    analysisDone = 0;
    analysisTotal = pending.length;
    analysisCurrent = '';
    _safeNotify();

    for (final track in pending) {
      if (_disposed) break;
      if (defaultTargetPlatform == TargetPlatform.android && player.playing) {
        break;
      }
      analysisCurrent = track.title;
      logLine('analysis start: ${track.path}');
      _safeNotify();
      final data = await _analyzer.analyze(
        track,
        scanSeconds: analysisScanSeconds,
      );
      if (data != null) {
        await repository.saveAnalysis(track.path, data);
        final analysis = TrackAnalysis.fromJson(data);
        final libraryIndex = library.indexWhere((t) => t.id == track.id);
        if (libraryIndex >= 0) {
          library[libraryIndex] = library[libraryIndex].withAnalysis(analysis);
        }
        final queueIndex = queue.indexWhere((t) => t.id == track.id);
        if (queueIndex >= 0) {
          queue[queueIndex] = queue[queueIndex].withAnalysis(analysis);
          if (queueIndex == index) {
            await player.setTrackGain(
              _gainFor(queue[queueIndex]),
              peakDb: _peakDbFor(queue[queueIndex]),
            );
          }
        }
        logLine(
          'analysis done: ${track.path} '
          'bpm=${data['bpm']} scan=${analysisScanSeconds}s',
        );
      } else {
        _analysisFailed.add(track.id);
        logLine('analysis failed: ${track.path}');
      }
      analysisDone++;
      _safeNotify();
    }

    analyzing = false;
    analysisCurrent = '';
    _safeNotify();
  }

  Future<void> analyzeNow({bool force = false}) async {
    if (defaultTargetPlatform == TargetPlatform.android && player.playing) {
      return;
    }
    _analysisFailed.clear();
    final pending = force
        ? List<Track>.of(library)
        : library
              .where(
                (t) => t.analysis == null && !_analysisFailed.contains(t.id),
              )
              .toList();
    await _analyzeTracks(pending);
  }

  void setAnalysisScanSeconds(int value) {
    if (value != 0) {
      analysisScanSeconds = value.clamp(15, 300);
    } else {
      analysisScanSeconds = 0;
    }
    _prefs?.setInt('analysisScanSeconds', analysisScanSeconds);
    _safeNotify();
  }

  void setAutoAnalyze(bool value) {
    autoAnalyze = value;
    _prefs?.setBool('autoAnalyze', value);
    if (value) {
      unawaited(_autoAnalyzeWindow());
    }
    _safeNotify();
  }

  int get analysisPending => library.where((t) => t.analysis == null).length;

  static bool _isUnderRoot(String path, String root) {
    final normalizedPath = path.replaceAll('\\', '/').toLowerCase();
    final normalizedRoot = root
        .replaceAll('\\', '/')
        .toLowerCase()
        .replaceAll(RegExp(r'/+$'), '');
    if (normalizedRoot.isEmpty) return true;
    return normalizedPath == normalizedRoot ||
        normalizedPath.startsWith('$normalizedRoot/');
  }

  void setSmartShuffle(bool value) {
    smartShuffle = value;
    _smartPlayed.clear();
    _prefs?.setBool('smartShuffle', value);
    _safeNotify();
  }

  Track? _smartNextTrack() {
    final currentTrack = current;
    if (currentTrack == null) return null;
    final currentFeatures = currentTrack.analysis?.features;
    if (currentFeatures == null || currentFeatures.length < 8) return null;

    final dimensions = currentFeatures.length;
    final usable = library.where((track) {
      final features = track.analysis?.features;
      return features != null && features.length == dimensions;
    }).toList();
    if (usable.length < 2) return null;

    final means = List<double>.filled(dimensions, 0);
    for (final track in usable) {
      final features = track.analysis!.features;
      for (var i = 0; i < dimensions; i++) {
        means[i] += features[i];
      }
    }
    for (var i = 0; i < dimensions; i++) {
      means[i] /= usable.length;
    }

    final variances = List<double>.filled(dimensions, 0);
    for (final track in usable) {
      final features = track.analysis!.features;
      for (var i = 0; i < dimensions; i++) {
        final delta = features[i] - means[i];
        variances[i] += delta * delta;
      }
    }
    final deviations = List<double>.filled(dimensions, 1);
    for (var i = 0; i < dimensions; i++) {
      final value = math.sqrt(variances[i] / usable.length);
      deviations[i] = value < 1e-6 ? 1 : value;
    }

    List<double> normalize(List<double> features) => [
      for (var i = 0; i < dimensions; i++)
        (features[i] - means[i]) / deviations[i],
    ];

    final currentVector = normalize(currentFeatures);
    final currentNorm = _vectorNorm(currentVector);
    if (currentNorm == 0) return null;

    List<_ScoredTrack> score({required bool useHistory}) {
      final scored = <_ScoredTrack>[];
      for (final track in usable) {
        if (track.id == currentTrack.id) continue;
        if (useHistory && _smartPlayed.contains(track.id)) continue;
        final vector = normalize(track.analysis!.features);
        final vectorNorm = _vectorNorm(vector);
        if (vectorNorm == 0) continue;
        final similarity =
            _dotProduct(currentVector, vector) / (currentNorm * vectorNorm);
        scored.add(
          _ScoredTrack(track, similarity + _random.nextDouble() * 0.06),
        );
      }
      scored.sort((a, b) => b.score.compareTo(a.score));
      return scored;
    }

    var candidates = score(useHistory: true);
    if (candidates.isEmpty) {
      _smartPlayed.clear();
      candidates = score(useHistory: false);
    }
    if (candidates.isEmpty) return null;

    final top = candidates.take(math.min(5, candidates.length)).toList();
    final choice = top[_random.nextInt(top.length)].track;
    _smartPlayed.add(currentTrack.id);
    _smartPlayed.add(choice.id);
    return choice;
  }

  double _dotProduct(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  double _vectorNorm(List<double> vector) =>
      math.sqrt(_dotProduct(vector, vector));

  void toggleShuffle() {
    shuffle = !shuffle;
    if (queue.isNotEmpty && index >= 0) {
      if (shuffle) {
        _preShuffle = List<Track>.of(queue);
        final head = queue.sublist(0, index + 1);
        final tail = queue.sublist(index + 1)..shuffle();
        queue = [...head, ...tail];
      } else if (_preShuffle != null) {
        final currentId = current?.id;
        queue = List<Track>.of(_preShuffle!);
        index = queue.indexWhere((t) => t.id == currentId);
        if (index < 0) index = 0;
        _preShuffle = null;
      }
    }
    _safeNotify();
  }

  void toggleRepeat() {
    repeat = !repeat;
    _safeNotify();
  }

  void setAutomix(bool value) {
    automix = value;
    _prefs?.setBool('automix', value);
    _safeNotify();
  }

  void setCrossfade(bool value) {
    crossfade = value;
    _prefs?.setBool('crossfade', value);
    _safeNotify();
  }

  void setGapless(bool value) {
    gapless = value;
    _prefs?.setBool('gapless', value);
    _safeNotify();
  }

  Future<void> setNormalize(bool value) async {
    normalize = value;
    _prefs?.setBool('normalize', value);
    final track = current;
    if (track != null) {
      await player.setTrackGain(_gainFor(track), peakDb: _peakDbFor(track));
    }
    _safeNotify();
  }

  Future<void> setUseReplayGain(bool value) async {
    useReplayGain = value;
    _prefs?.setBool('useReplayGain', value);
    final track = current;
    if (track != null) {
      await player.setTrackGain(_gainFor(track), peakDb: _peakDbFor(track));
    }
    _safeNotify();
  }

  void setUseNativeLimiter(bool value) {
    useNativeLimiter = value;
    _prefs?.setBool('useNativeLimiter', value);
    player.setUseNativeLimiter(value);
    _safeNotify();
  }

  void setSkipSilence(bool value) {
    skipSilence = value;
    _prefs?.setBool('skipSilence', value);
    _safeNotify();
  }

  void setCrossfadeSeconds(double value) {
    crossfadeSeconds = value;
    _prefs?.setDouble('crossfadeSeconds', value);
    _safeNotify();
  }

  Future<void> setMusicRoot(String root) async {
    musicRoots = [root];
    _prefs?.setStringList('musicRoots', musicRoots);
    _safeNotify();
    await rescan();
  }

  Future<void> addRoot(String root) async {
    final normalized = root.trim();
    if (normalized.isEmpty) return;
    if (musicRoots.any((existing) => _samePath(existing, normalized))) {
      return;
    }
    if (musicRoots.any((existing) => _isUnderRoot(normalized, existing))) {
      return;
    }
    final filtered = musicRoots
        .where((existing) => !_isUnderRoot(existing, normalized))
        .toList();
    musicRoots = [...filtered, normalized];
    await _prefs?.setStringList('musicRoots', musicRoots);
    _safeNotify();
    await rescan();
  }

  Future<void> removeRoot(String root) async {
    musicRoots = musicRoots
        .where((existing) => !_samePath(existing, root))
        .toList();
    await _prefs?.setStringList('musicRoots', musicRoots);
    _safeNotify();
    await rescan();
  }

  bool _isUnderAnyRoot(String path) {
    return musicRoots.any((root) => _isUnderRoot(path, root));
  }

  static bool _samePath(String a, String b) {
    String normalize(String value) => value
        .replaceAll('\\', '/')
        .toLowerCase()
        .replaceAll(RegExp(r'/+$'), '');
    return normalize(a) == normalize(b);
  }

  void clearError() {
    error = null;
    _safeNotify();
  }

  Future<void> stopPlayback() async {
    await player.pause();
    await player.seek(Duration.zero);
    await _mediaNotification.clear();
    _safeNotify();
  }

  void _mediaTick() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (current == null) return;
    final now = DateTime.now();
    if (now.difference(_lastMediaPush) < const Duration(seconds: 2)) return;
    _lastMediaPush = now;
    _publishMediaState();
  }

  void _publishMediaState() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _lastMediaPush = DateTime.now();
    final track = current;
    if (track == null) {
      unawaited(_mediaNotification.clear());
      return;
    }
    final duration = player.duration > Duration.zero
        ? player.duration
        : (track.duration ?? Duration.zero);
    unawaited(
      _mediaNotification.update(
        title: track.title,
        artist: track.artist,
        album: track.album,
        artworkPath: track.artworkPath,
        duration: duration,
        position: player.position,
        playing: player.playing,
        speed: player.rate,
        canNext: index + 1 < queue.length || repeat,
        canPrevious: index > 0,
      ),
    );
  }

  Future<void> refreshNotificationStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final status = await _mediaNotification.status();
      notificationPermission = status.permissionGranted;
      notificationsEnabled = status.enabled;
      notificationChannelBlocked = status.channelBlocked;
      notificationChannelImportance = status.channelImportance;
      notificationError = null;
    } catch (errorValue) {
      notificationError = errorValue.toString();
    }
    _safeNotify();
  }

  Future<void> requestNotificationPermission({bool force = false}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _mediaNotification.ensurePermission(force: force);
    await refreshNotificationStatus();
  }

  Future<bool> testNotification() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final ok = await _mediaNotification.postTestNotification();
    await refreshNotificationStatus();
    return ok;
  }

  Future<void> openNotificationSettings() => _mediaNotification.openSettings();

  bool get notificationReady =>
      notificationPermission &&
      notificationsEnabled &&
      !notificationChannelBlocked;

  String get notificationSummary {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return 'Solo disponible en Android';
    }
    if (notificationError != null) {
      return 'Error: $notificationError';
    }
    if (!notificationPermission) {
      return 'Permiso de notificaciones no concedido';
    }
    if (!notificationsEnabled) {
      return 'Notificaciones desactivadas en el sistema';
    }
    if (notificationChannelBlocked) {
      return 'Canal de reproducción bloqueado';
    }
    return 'Notificación y pantalla bloqueada listas';
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _mixTimer?.cancel();
    _eqApplyTimer?.cancel();
    _playerSub?.cancel();
    _playingSub?.cancel();
    player.dispose();
    super.dispose();
  }
}

class _ScoredTrack {
  _ScoredTrack(this.track, this.score);

  final Track track;
  final double score;
}

enum _TransitionStyle { smooth, dance, hipHop, latin, pop, ballad }
