import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../player/now_playing_screen.dart';
import '../player/queue_panel.dart';
import '../widgets/cover_art.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final track = state.current;
        if (track == null) return const SizedBox.shrink();

        return Material(
          color: const Color(0xFF101017),
          child: InkWell(
            onTap: () => openNowPlaying(context),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFF23232F)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _progress(context, state),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                    child: Row(
                      children: [
                        CoverArt(track: track, size: 50, radius: 8),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF9C9CAD),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Anterior',
                          onPressed: state.previous,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        StreamBuilder<bool>(
                          stream: state.player.playingStream,
                          initialData: state.player.playing,
                          builder: (context, snapshot) {
                            final playing = snapshot.data ?? false;
                            return IconButton.filled(
                              tooltip: playing ? 'Pausa' : 'Reproducir',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: state.togglePlay,
                              icon: Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Siguiente',
                          onPressed: state.next,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                        IconButton(
                          tooltip: 'AutoMix',
                          onPressed: () => state.setAutomix(!state.automix),
                          icon: Icon(
                            Icons.auto_awesome_rounded,
                            color: state.automix
                                ? Theme.of(context).colorScheme.primary
                                : const Color(0xFF6E6E80),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cola',
                          onPressed: () => showQueue(context),
                          icon: const Icon(Icons.queue_music_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _progress(BuildContext context, AppState state) {
    return StreamBuilder<Duration>(
      stream: state.player.positionStream,
      initialData: state.player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = state.player.duration;
        final fraction = duration.inMilliseconds == 0
            ? 0.0
            : (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);
        return LinearProgressIndicator(
          value: fraction,
          minHeight: 2,
          backgroundColor: Colors.white10,
          valueColor: AlwaysStoppedAnimation(
            Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}
