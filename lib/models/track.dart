import 'replay_gain.dart';
import 'track_analysis.dart';

class Track {
  final String id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final Duration? duration;
  final String? artworkPath;
  final double? bpm;
  final ReplayGainData? replayGain;
  final TrackAnalysis? analysis;

  const Track({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.duration,
    this.artworkPath,
    this.bpm,
    this.replayGain,
    this.analysis,
  });

  Track withAnalysis(TrackAnalysis? value) {
    return Track(
      id: id,
      path: path,
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      genre: genre,
      year: year,
      trackNumber: trackNumber,
      discNumber: discNumber,
      duration: duration,
      artworkPath: artworkPath,
      bpm: value?.bpm ?? bpm,
      replayGain: replayGain,
      analysis: value,
    );
  }

  double? get effectivePeakDb {
    double? effectivePeakDb = analysis?.peakDb;
    final replayPeakDb = replayGain?.effectiveTrackPeakDb;
    if (replayPeakDb != null &&
        replayPeakDb.isFinite &&
        (effectivePeakDb == null || replayPeakDb > effectivePeakDb)) {
      effectivePeakDb = replayPeakDb;
    }
    return effectivePeakDb;
  }

  String get subtitle => artist;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'title': title,
    'artist': artist,
    'album': album,
    'albumArtist': albumArtist,
    'genre': genre,
    'year': year,
    'trackNumber': trackNumber,
    'discNumber': discNumber,
    'duration': duration?.inSeconds,
    'artworkPath': artworkPath,
    'bpm': bpm,
    'replayGain': replayGain?.toJson(),
  };

  factory Track.fromJson(Map<String, dynamic> json) {
    final seconds = json['duration'];
    return Track(
      id: json['id'] as String,
      path: json['path'] as String,
      title: (json['title'] as String?) ?? 'Unknown',
      artist: (json['artist'] as String?) ?? 'Unknown artist',
      album: (json['album'] as String?) ?? 'Unknown album',
      albumArtist: json['albumArtist'] as String?,
      genre: json['genre'] as String?,
      year: json['year'] as int?,
      trackNumber: json['trackNumber'] as int?,
      discNumber: json['discNumber'] as int?,
      duration: seconds is int ? Duration(seconds: seconds) : null,
      artworkPath: json['artworkPath'] as String?,
      bpm: (json['bpm'] as num?)?.toDouble(),
      replayGain: _replayGainFromJson(json['replayGain']),
    );
  }

  static ReplayGainData? _replayGainFromJson(Object? value) {
    if (value is Map<String, dynamic>) {
      return ReplayGainData.fromJson(value);
    }
    if (value is Map) {
      return ReplayGainData.fromJson(
        value.map((key, entry) => MapEntry(key.toString(), entry)),
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
