import 'dart:io';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class ArtworkColor {
  static const Color fallback = Color(0xFF8B5CF6);
  static final Map<String, Color> _cache = {};

  static Color ofSync(String trackId) => _cache[trackId] ?? fallback;

  static Future<Color> of({
    required String trackId,
    String? artworkPath,
  }) async {
    final cached = _cache[trackId];
    if (cached != null) return cached;
    if (artworkPath == null) {
      _cache[trackId] = fallback;
      return fallback;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        FileImage(File(artworkPath)),
        size: const Size(80, 80),
        maximumColorCount: 8,
      );
      final color = palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.mutedColor?.color ??
          fallback;
      _cache[trackId] = color;
      return color;
    } catch (_) {
      _cache[trackId] = fallback;
      return fallback;
    }
  }
}
