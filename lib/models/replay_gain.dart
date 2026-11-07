import '../util/gain_calculation.dart';

class ReplayGainData {
  const ReplayGainData({
    this.trackGainDb,
    this.trackPeakDb,
    this.albumGainDb,
    this.albumPeakDb,
  });

  final double? trackGainDb;
  final double? trackPeakDb;
  final double? albumGainDb;
  final double? albumPeakDb;

  bool get hasAnyData {
    return trackGainDb != null ||
        trackPeakDb != null ||
        albumGainDb != null ||
        albumPeakDb != null;
  }

  double? get effectiveTrackGainDb => trackGainDb ?? albumGainDb;

  double? get effectiveTrackPeakDb => trackPeakDb ?? albumPeakDb;

  factory ReplayGainData.fromTags({
    String? trackGain,
    String? trackPeak,
    String? albumGain,
    String? albumPeak,
  }) {
    return ReplayGainData(
      trackGainDb: _parseDb(trackGain),
      trackPeakDb: _parsePeakDb(trackPeak),
      albumGainDb: _parseDb(albumGain),
      albumPeakDb: _parsePeakDb(albumPeak),
    );
  }

  factory ReplayGainData.fromJson(Map<String, dynamic> json) {
    return ReplayGainData(
      trackGainDb: _parseDb(json['trackGainDb']?.toString()),
      trackPeakDb: _parseDb(json['trackPeakDb']?.toString()),
      albumGainDb: _parseDb(json['albumGainDb']?.toString()),
      albumPeakDb: _parseDb(json['albumPeakDb']?.toString()),
    );
  }

  Map<String, dynamic> toJson() => {
    'trackGainDb': trackGainDb,
    'trackPeakDb': trackPeakDb,
    'albumGainDb': albumGainDb,
    'albumPeakDb': albumPeakDb,
  };

  static double? _parseDb(String? value) {
    if (value == null) return null;
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'dB$', caseSensitive: false), '')
        .trim()
        .replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static double? _parsePeakDb(String? value) {
    if (value == null) return null;
    if (value.toLowerCase().contains('db')) return _parseDb(value);
    final cleaned = value.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || !parsed.isFinite || parsed <= 0.0) return null;
    final converted = linearGainToDb(parsed);
    return converted.isFinite ? converted : null;
  }
}
