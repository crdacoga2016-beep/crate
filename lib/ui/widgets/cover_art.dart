import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/track.dart';

class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.track,
    this.size = 48,
    this.radius = 8,
    this.fit = BoxFit.cover,
  });

  final Track? track;
  final double size;
  final double radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final path = track?.artworkPath;
    final placeholder = _placeholder();

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: path == null
            ? placeholder
            : Image.file(
                File(path),
                fit: fit,
                cacheWidth: (size * 2).round().clamp(48, 1024),
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }

  Widget _placeholder() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B2B3A), Color(0xFF17171F)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * 0.4,
          color: Colors.white24,
        ),
      ),
    );
  }
}
