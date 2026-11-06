import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../widgets/track_tile.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final wide = MediaQuery.sizeOf(context).width >= 760;
        final pad = wide ? 32.0 : 16.0;

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, wide ? 30 : 18, pad, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Biblioteca',
                          style: TextStyle(
                            fontSize: wide ? 32 : 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${state.library.length} canciones · '
                          '${state.library.map((t) => t.artist).toSet().length} artistas',
                          style: const TextStyle(
                            color: Color(0xFF9C9CAD),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Escanear de nuevo',
                    onPressed: state.scanning ? null : state.rescan,
                    icon: state.scanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onPressed: state.library.isEmpty
                        ? null
                        : () => state.playTrack(
                              state.library.first,
                              context: state.library,
                            ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Reproducir'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.library.isEmpty
                  ? const Center(
                      child: Text(
                        'Tu biblioteca está vacía',
                        style: TextStyle(color: Color(0xFF9C9CAD)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: state.library.length,
                      itemBuilder: (context, i) {
                        final track = state.library[i];
                        return TrackTile(
                          track: track,
                          number: i + 1,
                          showAlbum: wide,
                          current: state.current?.id == track.id,
                          playing: state.isPlaying,
                          onPlay: () => state.playTrack(
                            track,
                            context: state.library,
                          ),
                          onPlayNext: () => state.playNext(track),
                          onAddToQueue: () => state.addToQueue(track),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
