class TrackAnalysis {
  const TrackAnalysis({
    required this.bpm,
    required this.barLength,
    required this.downbeats,
    required this.downbeatPhase,
    required this.duration,
    required this.leadIn,
    required this.audibleEnd,
    required this.mixIn,
    required this.mixOut,
    required this.energy,
    required this.keyRoot,
    required this.isMinor,
    required this.key,
    required this.camelot,
    this.beatsPerBar = 4,
    this.lufs,
    this.peakDb,
    this.truePeakDb,
    this.keyConfidence = 0,
    this.version = 1,
    this.features = const [],
    this.beatlessIntro = false,
    this.beatlessOutro = false,
  });

  final double bpm;
  final int beatsPerBar;
  final double barLength;
  final List<double> downbeats;
  final double downbeatPhase;
  final double duration;
  final double leadIn;
  final double audibleEnd;
  final double mixIn;
  final double mixOut;
  final double energy;
  final double? lufs;
  final double? peakDb;
  final double? truePeakDb;
  final int keyRoot;
  final bool isMinor;
  final String key;
  final String camelot;
  final double keyConfidence;
  final int version;
  final List<double> features;
  final bool beatlessIntro;
  final bool beatlessOutro;

  double get normalizedBpm {
    var value = bpm;
    if (value <= 0) return 0;
    while (value < 90) {
      value *= 2;
    }
    while (value > 180) {
      value /= 2;
    }
    return value;
  }

  double get normalizedBarLength {
    final normalized = normalizedBpm;
    if (normalized <= 0) return barLength;
    return beatsPerBar * 60 / normalized;
  }

  factory TrackAnalysis.fromJson(Map<String, dynamic> json) {
    final downbeatsRaw = json['downbeats'];
    final downbeats = <double>[];
    if (downbeatsRaw is List) {
      for (final value in downbeatsRaw) {
        if (value is num) downbeats.add(value.toDouble());
      }
    }
    return TrackAnalysis(
      bpm: (json['bpm'] as num?)?.toDouble() ?? 0,
      beatsPerBar: (json['beatsPerBar'] as num?)?.toInt() ?? 4,
      barLength: (json['barLength'] as num?)?.toDouble() ?? 0,
      downbeats: downbeats,
      downbeatPhase: (json['downbeatPhase'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      leadIn: (json['leadIn'] as num?)?.toDouble() ?? 0,
      audibleEnd: (json['audibleEnd'] as num?)?.toDouble() ?? 0,
      mixIn: (json['mixIn'] as num?)?.toDouble() ?? 0,
      mixOut: (json['mixOut'] as num?)?.toDouble() ?? 0,
      energy: (json['energy'] as num?)?.toDouble() ?? 0,
      lufs: (json['lufs'] as num?)?.toDouble(),
      peakDb: (json['peakDb'] as num?)?.toDouble(),
      truePeakDb: (json['truePeakDb'] as num?)?.toDouble(),
      keyRoot: (json['keyRoot'] as num?)?.toInt() ?? 0,
      isMinor: json['isMinor'] == true,
      key: json['key'] as String? ?? '',
      camelot: json['camelot'] as String? ?? '',
      keyConfidence: (json['keyConfidence'] as num?)?.toDouble() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 1,
      features:
          (json['features'] as List?)
              ?.whereType<num>()
              .map((value) => value.toDouble())
              .toList() ??
          const [],
      beatlessIntro: json['beatlessIntro'] == true,
      beatlessOutro: json['beatlessOutro'] == true,
    );
  }
}
