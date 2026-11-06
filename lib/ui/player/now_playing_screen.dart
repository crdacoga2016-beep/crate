import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/artwork_color.dart';
import '../../state/app_state.dart';
import '../widgets/cover_art.dart';
import '../widgets/seek_bar.dart';
import 'queue_panel.dart';

void openNowPlaying(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => const NowPlayingScreen(),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    ),
  );
}

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final track = state.current;
        if (track == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Nada en reproducción')),
          );
        }

        return FutureBuilder<Color>(
          future: ArtworkColor.of(
            trackId: track.id,
            artworkPath: track.artworkPath,
          ),
          builder: (context, snapshot) {
            final accent = snapshot.data ?? ArtworkColor.fallback;
            return Scaffold(
              backgroundColor: const Color(0xFF08080C),
              body: Stack(
                children: [
                  _Backdrop(track: track, accent: accent),
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxHeight < 680;
                        final coverSize = math.min(
                          constraints.maxWidth * 0.52,
                          math.min(
                            360.0,
                            constraints.maxHeight * (compact ? 0.33 : 0.42),
                          ),
                        );
                        return Column(
                          children: [
                            _topBar(context),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 20 : 40,
                                  vertical: compact ? 6 : 16,
                                ),
                                child: Column(
                                  children: [
                                    _cover(track, coverSize),
                                    SizedBox(height: compact ? 16 : 26),
                                    Text(
                                      track.title,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: compact ? 22 : 28,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      track.artist,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Color(0xFFC9C9D6),
                                      ),
                                    ),
                                    if (track.album.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        track.album,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF8A8A9A),
                                        ),
                                      ),
                                    ],
                                    if (track.analysis != null) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          _MetaPill(
                                            text:
                                                '${track.analysis!.normalizedBpm.round()} BPM',
                                          ),
                                          if (state.isMixing)
                                            _MetaPill(
                                              text: 'MEZCLANDO',
                                              accent: accent,
                                            ),
                                          if (state.automix)
                                            _MetaPill(
                                              text: 'AutoMix',
                                              accent: accent,
                                            ),
                                        ],
                                      ),
                                    ],
                                    SizedBox(height: compact ? 14 : 26),
                                    SizedBox(
                                      width: compact ? double.infinity : 520,
                                      child: StreamBuilder<Duration>(
                                        stream: state.player.positionStream,
                                        initialData: state.player.position,
                                        builder: (context, positionSnapshot) {
                                          return StreamBuilder<Duration>(
                                            stream: state.player.durationStream,
                                            initialData: state.player.duration,
                                            builder: (context, durationSnapshot) {
                                              return SeekBar(
                                                position:
                                                    positionSnapshot.data ??
                                                        Duration.zero,
                                                duration:
                                                    durationSnapshot.data,
                                                onSeek: state.seek,
                                                accent: accent,
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                    SizedBox(height: compact ? 4 : 10),
                                    _controls(context, state, accent),
                                    SizedBox(height: compact ? 8 : 18),
                                    _bottomRow(context, state, accent, compact),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          ),
          const Spacer(),
          const Text(
            'REPRODUCIENDO',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.8,
              color: Color(0xFF8A8A9A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Cola',
            onPressed: () => showQueue(context),
            icon: const Icon(Icons.queue_music_rounded),
          ),
        ],
      ),
    );
  }

  Widget _cover(Track track, double size) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 60,
            spreadRadius: -8,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: CoverArt(track: track, size: size, radius: 18),
    );
  }

  Widget _controls(BuildContext context, AppState state, Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Aleatorio',
          onPressed: state.toggleShuffle,
          icon: const Icon(Icons.shuffle_rounded),
          color: state.shuffle ? accent : Colors.white70,
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Anterior',
          onPressed: state.previous,
          iconSize: 32,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 12),
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
                minimumSize: const Size(70, 70),
              ),
              onPressed: state.togglePlay,
              iconSize: 38,
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Siguiente',
          onPressed: state.next,
          iconSize: 32,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Repetir',
          onPressed: state.toggleRepeat,
          icon: const Icon(Icons.repeat_rounded),
          color: state.repeat ? accent : Colors.white70,
        ),
      ],
    );
  }

  Widget _bottomRow(
    BuildContext context,
    AppState state,
    Color accent,
    bool compact,
  ) {
    final volumeIcon = state.volume == 0
        ? Icons.volume_off_rounded
        : state.volume < 0.5
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 18,
      runSpacing: 10,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(volumeIcon, size: 20, color: Colors.white70),
            const SizedBox(width: 6),
            SizedBox(
              width: compact ? 96 : 140,
              child: Slider(
                value: state.volume,
                onChanged: state.setVolume,
              ),
            ),
          ],
        ),
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => state.setAutomix(!state.automix),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: state.automix
                  ? accent.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: state.automix
                    ? accent.withValues(alpha: 0.65)
                    : Colors.white12,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: state.automix ? accent : Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  'AutoMix',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: state.automix ? accent : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Cola',
          onPressed: () => showQueue(context),
          icon: const Icon(Icons.queue_music_rounded),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.text, this.accent});

  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? const Color(0xFF9C9CAD);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.track, required this.accent});

  final Track track;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final path = track.artworkPath;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(accent, Colors.black, 0.55)!,
                  const Color(0xFF08080C),
                ],
              ),
            ),
          ),
        ),
        if (path != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.35,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xFF08080C).withValues(alpha: 0.75),
                  const Color(0xFF08080C),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
