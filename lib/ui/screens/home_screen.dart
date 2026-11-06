import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/app_state.dart';
import '../../util/format.dart';
import '../widgets/cover_art.dart';
import '../widgets/track_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (state.loading) {
          return const _CenteredLoader(label: 'Leyendo tu biblioteca…');
        }
        if (state.library.isEmpty && !state.scanning) {
          return _EmptyLibrary(state: state);
        }

        final width = MediaQuery.sizeOf(context).width;
        final wide = width >= 760;
        final pad = wide ? 32.0 : 16.0;
        final artists = state.library.map((t) => t.artist).toSet().length;
        final albums = _groupByAlbum(state.library);
        final songs = state.library.take(12).toList();

        return ListView(
          padding: EdgeInsets.fromLTRB(pad, wide ? 30 : 18, pad, 32),
          children: [
            Text(
              'Tu música',
              style: TextStyle(
                fontSize: wide ? 32 : 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${state.library.length} canciones · $artists artistas · '
              '${albums.length} álbumes · '
              '${formatTotal(state.library.map((t) => t.duration))}',
              style: const TextStyle(color: Color(0xFF9C9CAD), fontSize: 13.5),
            ),
            if (state.scanning) ...[
              const SizedBox(height: 16),
              _ScanCard(state: state),
            ],
            if (state.analyzing) ...[
              const SizedBox(height: 16),
              _AnalysisCard(state: state),
            ],
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  onPressed: () =>
                      state.playTrack(state.library.first, context: state.library),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Reproducir todo'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    side: const BorderSide(color: Color(0xFF2B2B3A)),
                  ),
                  onPressed: () => _shufflePlay(state),
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('Aleatorio'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    side: const BorderSide(color: Color(0xFF2B2B3A)),
                  ),
                  onPressed: state.library.length > 1
                      ? () => state.buildAutoMixQueue()
                      : null,
                  icon: const Icon(Icons.auto_awesome_motion_rounded, size: 18),
                  label: const Text('Set AutoMix'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _AutomixCard(state: state),
            const SizedBox(height: 28),
            const _SectionTitle('Álbumes'),
            const SizedBox(height: 12),
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: albums.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final album = albums[i];
                  return _AlbumCard(
                    album: album,
                    onTap: () => state.playTrack(
                      album.tracks.first,
                      context: album.tracks,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 28),
            const _SectionTitle('Tus canciones'),
            const SizedBox(height: 6),
            ...songs.map(
              (track) => TrackTile(
                track: track,
                number: state.library.indexOf(track) + 1,
                showAlbum: wide,
                current: state.current?.id == track.id,
                playing: state.isPlaying,
                onPlay: () =>
                    state.playTrack(track, context: state.library),
                onPlayNext: () => state.playNext(track),
                onAddToQueue: () => state.addToQueue(track),
              ),
            ),
          ],
        );
      },
    );
  }

  void _shufflePlay(AppState state) {
    final list = List<Track>.of(state.library)..shuffle();
    if (list.isEmpty) return;
    if (!state.shuffle) state.toggleShuffle();
    state.playTrack(list.first, context: list);
  }

  static List<_Album> _groupByAlbum(List<Track> library) {
    final map = <String, List<Track>>{};
    for (final track in library) {
      map.putIfAbsent(track.album, () => []).add(track);
    }
    final albums = map.entries
        .map((entry) => _Album(entry.key, entry.value))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return albums;
  }
}

class _Album {
  _Album(this.name, this.tracks);

  final String name;
  final List<Track> tracks;
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap});

  final _Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 138,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverArt(track: album.tracks.first, size: 126, radius: 10),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                album.tracks.first.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF9C9CAD),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutomixCard extends StatelessWidget {
  const _AutomixCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.26),
            const Color(0xFF14141C),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: accent),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AutoMix',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Mezclas beat-matched entre tus canciones: tempo, '
                  'compases y ecualización alineados como un DJ.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFB9B9C8),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: state.automix,
            onChanged: state.setAutomix,
            activeThumbColor: Colors.white,
            activeTrackColor: accent,
          ),
        ],
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15151E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_search_rounded, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Analizando biblioteca',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${state.scanDone} / ${state.scanTotal}',
                style: const TextStyle(
                  color: Color(0xFF9C9CAD),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.scanFraction,
              minHeight: 4,
              backgroundColor: Colors.white10,
            ),
          ),
          if (state.scanCurrent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              state.scanCurrent,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF8A8A9A),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final value = state.analysisTotal == 0
        ? 0.0
        : state.analysisDone / state.analysisTotal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF15151E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Analizando música',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${state.analysisDone} / ${state.analysisTotal}',
                style: const TextStyle(
                  color: Color(0xFF9C9CAD),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: Colors.white10,
            ),
          ),
          if (state.analysisCurrent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              state.analysisCurrent,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF8A8A9A),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined, size: 56, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'No se encontró música',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              defaultTargetPlatform == TargetPlatform.android
                  ? 'No se encontró música en el teléfono.\n'
                      'Concede el permiso de audio y vuelve a escanear.'
                  : state.musicRoots.isEmpty
                      ? 'No hay carpetas configuradas.'
                      : 'No se encontró música en:\n'
                          '${state.musicRoots.join('\n')}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9C9CAD), height: 1.4),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final path = await FilePicker.getDirectoryPath(
                      dialogTitle: 'Elegir carpeta de música',
                    );
                    if (path != null && path.isNotEmpty) {
                      await state.addRoot(path);
                    }
                  },
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Añadir carpeta'),
                ),
                OutlinedButton.icon(
                  onPressed: state.rescan,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Escanear ahora'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(color: Color(0xFF9C9CAD))),
        ],
      ),
    );
  }
}
