import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../widgets/cover_art.dart';

Future<void> showQueue(BuildContext context) async {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 760) {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 420,
            height: size.height - 80,
            child: const QueuePanel(),
          ),
        ),
      ),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: size.height * 0.84,
        child: const QueuePanel(),
      ),
    );
  }
}

class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final current = state.current;
        final upNext = state.upNext;

        return Material(
          color: const Color(0xFF15151E),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 10, 8),
                child: Row(
                  children: [
                    const Icon(Icons.queue_music_rounded, size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'Cola de reproducción',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (current != null) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'AHORA SUENA',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        color: Color(0xFF8A8A9A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CoverArt(track: current, size: 46, radius: 8),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                current.artist,
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
                          onPressed: state.togglePlay,
                          icon: const Icon(Icons.pause_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Row(
                  children: [
                    Text(
                      'A CONTINUACIÓN · ${upNext.length}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        color: Color(0xFF8A8A9A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: upNext.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay más canciones en la cola',
                          style: TextStyle(color: Color(0xFF8A8A9A)),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        buildDefaultDragHandles: false,
                        itemCount: upNext.length,
                        onReorderItem: (oldIndex, newIndex) {
                          final base = state.index + 1;
                          state.reorderQueue(
                            base + oldIndex,
                            base + newIndex,
                            adjusted: true,
                          );
                        },
                        itemBuilder: (context, i) {
                          final track = upNext[i];
                          final globalIndex = state.index + 1 + i;
                          return ListTile(
                            key: ValueKey('${track.id}-$i'),
                            onTap: () => state.jumpTo(globalIndex),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            leading: CoverArt(
                              track: track,
                              size: 42,
                              radius: 7,
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9C9CAD),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Icon(
                                    Icons.drag_indicator_rounded,
                                    size: 18,
                                    color: Color(0xFF5A5A6A),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Quitar',
                                  onPressed: () =>
                                      state.removeFromQueue(globalIndex),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
