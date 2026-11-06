import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import '../models/track_analysis.dart';

typedef ScanProgress = void Function(int done, int total, String current);

class LibraryRepository {
  static const Set<String> audioExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.wav',
    '.wma',
    '.aiff',
    '.ape',
  };

  String get defaultRoot {
    if (Platform.isAndroid) return '/storage/emulated/0/Music';
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return Directory.current.path;
    return p.join(home, 'Music');
  }

  List<String> get defaultRoots => const [];

  Future<void> ensurePermission() => _ensureAndroidPermission();

  Future<Directory> _supportDir() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _cacheFile() async =>
      File(p.join((await _supportDir()).path, 'library_cache.json'));

  Future<Directory> _artworkDir() async {
    final dir = Directory(p.join((await _supportDir()).path, 'artwork'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Map<String, dynamic>> _readCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }

  Future<List<Track>> loadCached() async {
    final cache = await _readCache();
    final tracks = <Track>[];
    for (final value in cache.values) {
      if (value is Map<String, dynamic>) {
        try {
          tracks.add(Track.fromJson(value));
        } catch (_) {}
      }
    }
    await _mergeAnalysis(tracks);
    if (!Platform.isAndroid) {
      final before = tracks.length;
      tracks.removeWhere((track) {
        try {
          return !File(track.path).existsSync();
        } catch (_) {
          return true;
        }
      });
      if (tracks.length != before) {
        final valid = tracks.map((track) => track.path).toSet();
        cache.removeWhere((key, _) => !valid.contains(key));
        try {
          await (await _cacheFile()).writeAsString(jsonEncode(cache));
        } catch (_) {}
      }
    }
    final unique = _dedupeTracks(tracks);
    _sort(unique);
    return unique;
  }

  Future<Map<String, TrackAnalysis>> loadAnalysis() async {
    try {
      final file = File(p.join((await _supportDir()).path, 'analysis.json'));
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return {};
      final raw = decoded['tracks'];
      if (raw is! Map) return {};
      final result = <String, TrackAnalysis>{};
      raw.forEach((key, value) {
        if (key is String && value is Map) {
          try {
            result[key] = TrackAnalysis.fromJson(
              Map<String, dynamic>.from(value),
            );
          } catch (_) {}
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> _mergeAnalysis(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final analysis = await loadAnalysis();
    if (analysis.isEmpty) return;

    final byBasename = <String, List<TrackAnalysis>>{};
    final byStem = <String, List<TrackAnalysis>>{};
    for (final entry in analysis.entries) {
      final name = _baseName(entry.key);
      byBasename.putIfAbsent(name.toLowerCase(), () => []).add(entry.value);
      byStem.putIfAbsent(_stem(name), () => []).add(entry.value);
    }

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      var value = analysis[track.path];
      if (value == null) {
        final name = _baseName(track.path);
        List<TrackAnalysis>? candidates = byBasename[name.toLowerCase()];
        candidates ??= byStem[_stem(name)];
        if (candidates != null && candidates.isNotEmpty) {
          if (candidates.length == 1) {
            value = candidates.first;
          } else {
            final trackSeconds = track.duration?.inSeconds ?? 0;
            value = candidates.reduce((a, b) {
              final distanceA = (a.duration - trackSeconds).abs();
              final distanceB = (b.duration - trackSeconds).abs();
              return distanceA <= distanceB ? a : b;
            });
          }
        }
      }
      if (value != null) {
        tracks[i] = track.withAnalysis(value);
      }
    }
  }

  static String _stem(String name) {
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    return dot > 0 ? lower.substring(0, dot) : lower;
  }

  Future<void> saveAnalysis(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final file = File(
        p.join((await _supportDir()).path, 'analysis.json'),
      );
      Map<String, dynamic> root = {
        'version': 1,
        'tracks': <String, dynamic>{},
      };
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          root = decoded;
        }
      }
      final existing = root['tracks'];
      final tracks = existing is Map
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};
      tracks[path] = data;
      root['tracks'] = tracks;
      root['version'] = 1;
      await file.writeAsString(jsonEncode(root));
    } catch (_) {}
  }

  Future<bool> importAnalysis(String sourcePath) async {
    try {
      final source = File(sourcePath);
      final content = await source.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic> ||
          decoded['tracks'] is! Map) {
        return false;
      }
      final destination = File(
        p.join((await _supportDir()).path, 'analysis.json'),
      );
      await destination.writeAsString(content);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }

  Future<List<Track>> scan(
    String root, {
    ScanProgress? onProgress,
  }) {
    return scanRoots([root], onProgress: onProgress);
  }

  Future<List<Track>> scanRoots(
    List<String> roots, {
    ScanProgress? onProgress,
  }) async {
    if (Platform.isAndroid) {
      await _ensureAndroidPermission();
    }
    final files = <File>[];
    final seen = <String>{};
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File &&
              audioExtensions
                  .contains(p.extension(entity.path).toLowerCase())) {
            final key = entity.path.toLowerCase();
            if (seen.add(key)) files.add(entity);
          }
        }
      } catch (_) {}
    }
    files.sort(
      (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
    );

    final cache = await _readCache();
    final artworkDir = await _artworkDir();
    final tracks = <Track>[];

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      onProgress?.call(i, files.length, p.basename(file.path));
      try {
        final stat = await file.stat();
        final cached = cache[file.path];
        if (cached is Map<String, dynamic> &&
            cached['mtime'] == stat.modified.millisecondsSinceEpoch &&
            cached['size'] == stat.size) {
          tracks.add(Track.fromJson(cached));
          continue;
        }
        final track = await _readTrack(file, stat, artworkDir);
        if (track != null) {
          tracks.add(track);
          cache[file.path] = {
            ...track.toJson(),
            'mtime': stat.modified.millisecondsSinceEpoch,
            'size': stat.size,
          };
        }
      } catch (_) {}
    }

    onProgress?.call(files.length, files.length, '');
    try {
      await (await _cacheFile()).writeAsString(jsonEncode(cache));
    } catch (_) {}

    await _mergeAnalysis(tracks);
    final unique = _dedupeTracks(tracks);
    _sort(unique);
    return unique;
  }

  Future<Track?> _readTrack(
    File file,
    FileStat stat,
    Directory artworkDir,
  ) async {
    AudioMetadata? metadata;
    try {
      metadata = readMetadata(file, getImage: true);
    } catch (_) {}

    final fallbackTitle = p.basenameWithoutExtension(file.path);
    final title = _clean(metadata?.title) ?? fallbackTitle;
    final artist = _clean(metadata?.artist) ??
        _clean(metadata?.albumArtist) ??
        'Unknown artist';
    final album = _clean(metadata?.album) ?? 'Unknown album';

    String? artworkPath;
    final pictures = metadata?.pictures ?? const <Picture>[];
    if (pictures.isNotEmpty) {
      try {
        final picture = pictures.firstWhere(
          (pic) => pic.pictureType == PictureType.coverFront,
          orElse: () => pictures.first,
        );
        final id = _hash(file.path);
        final target = File(p.join(artworkDir.path, '$id.img'));
        await target.writeAsBytes(picture.bytes, flush: false);
        artworkPath = target.path;
      } catch (_) {}
    }

    final genres = metadata?.genres ?? const <String>[];
    final year = metadata?.year?.year;
    final duration = metadata?.duration;

    return Track(
      id: _hash(file.path),
      path: file.path,
      title: title,
      artist: artist,
      album: album,
      albumArtist: _clean(metadata?.albumArtist),
      genre: genres.isNotEmpty ? _clean(genres.first) : null,
      year: (year != null && year > 0) ? year : null,
      trackNumber: metadata?.trackNumber,
      discNumber: metadata?.discNumber,
      duration:
          (duration != null && duration > Duration.zero) ? duration : null,
      artworkPath: artworkPath,
      bpm: null,
    );
  }

  Future<void> _ensureAndroidPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel('crate/permissions')
          .invokeMethod<bool>('ensureAudioPermission');
    } catch (_) {}
  }

  static List<Track> _dedupeTracks(List<Track> tracks) {
    final seen = <String>{};
    final result = <Track>[];
    for (final track in tracks) {
      final key = '${track.path.toLowerCase()}|'
          '${track.title.toLowerCase()}|'
          '${track.artist.toLowerCase()}|'
          '${track.album.toLowerCase()}|'
          '${track.duration?.inSeconds ?? 0}';
      if (seen.add(key)) result.add(track);
    }
    return result;
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    var trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains('Ã') ||
        trimmed.contains('Â') ||
        trimmed.contains('â€')) {
      try {
        final repaired = utf8.decode(
          latin1.encode(trimmed),
          allowMalformed: true,
        );
        if (repaired != trimmed) trimmed = repaired;
      } catch (_) {}
    }
    return trimmed;
  }

  static void _sort(List<Track> tracks) {
    tracks.sort((a, b) {
      final byArtist =
          a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      if (byArtist != 0) return byArtist;
      final byAlbum = a.album.toLowerCase().compareTo(b.album.toLowerCase());
      if (byAlbum != 0) return byAlbum;
      final byDisc = (a.discNumber ?? 0).compareTo(b.discNumber ?? 0);
      if (byDisc != 0) return byDisc;
      final byTrack = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      if (byTrack != 0) return byTrack;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }

  static String _hash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
