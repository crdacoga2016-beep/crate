import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../util/format.dart';
import 'cover_art.dart';

class TrackTile extends StatefulWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.number,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    this.current = false,
    this.playing = false,
    this.showAlbum = true,
  });

  final Track track;
  final int number;
  final VoidCallback onPlay;
  final VoidCallback onPlayNext;
  final VoidCallback onAddToQueue;
  final bool current;
  final bool playing;
  final bool showAlbum;

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final titleColor = widget.current ? accent : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onPlay,
        borderRadius: BorderRadius.circular(10),
        hoverColor: Colors.white.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: widget.current
                    ? Icon(
                        widget.playing ? Icons.graphic_eq : Icons.volume_up_rounded,
                        size: 18,
                        color: accent,
                      )
                    : _hover
                        ? const Icon(Icons.play_arrow_rounded, size: 18)
                        : Text(
                            '${widget.number}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF6E6E80),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
              ),
              const SizedBox(width: 10),
              CoverArt(track: widget.track, size: 44, radius: 7),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight:
                            widget.current ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9C9CAD),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showAlbum)
                SizedBox(
                  width: 180,
                  child: Text(
                    widget.track.album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8A8A9A),
                      fontSize: 12.5,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                child: Text(
                  formatDuration(widget.track.duration),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF8A8A9A),
                    fontSize: 12.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                color: const Color(0xFF1B1B25),
                icon: Icon(
                  Icons.more_vert,
                  size: 22,
                  color: _hover ? Colors.white : Colors.white54,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'play':
                      widget.onPlay();
                    case 'next':
                      widget.onPlayNext();
                    case 'queue':
                      widget.onAddToQueue();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'play',
                    child: Text('Reproducir'),
                  ),
                  PopupMenuItem(
                    value: 'next',
                    child: Text('Reproducir a continuación'),
                  ),
                  PopupMenuItem(
                    value: 'queue',
                    child: Text('Añadir a la cola'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
