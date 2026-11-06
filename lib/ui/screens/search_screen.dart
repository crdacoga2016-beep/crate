import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/app_state.dart';
import '../widgets/track_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final wide = MediaQuery.sizeOf(context).width >= 760;
        final pad = wide ? 32.0 : 16.0;
        final query = _query.trim().toLowerCase();
        final results = query.isEmpty
            ? const <int>[]
            : [
                for (var i = 0; i < state.library.length; i++)
                  if (_matches(state.library[i], query)) i
              ];

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, wide ? 30 : 18, pad, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Buscar',
                    style: TextStyle(
                      fontSize: wide ? 32 : 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _controller,
                    autofocus: false,
                    onChanged: (value) => setState(() => _query = value),
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Canciones, artistas, álbumes…',
                      hintStyle: const TextStyle(color: Color(0xFF6E6E80)),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                      filled: true,
                      fillColor: const Color(0xFF15151E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  if (query.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${results.length} resultados',
                      style: const TextStyle(
                        color: Color(0xFF9C9CAD),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: query.isEmpty
                  ? const _SearchHint()
                  : results.isEmpty
                      ? const Center(
                          child: Text(
                            'Sin resultados',
                            style: TextStyle(color: Color(0xFF9C9CAD)),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final index = results[i];
                            final track = state.library[index];
                            return TrackTile(
                              track: track,
                              number: index + 1,
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

  bool _matches(Track track, String query) {
    return track.title.toLowerCase().contains(query) ||
        track.artist.toLowerCase().contains(query) ||
        track.album.toLowerCase().contains(query);
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, size: 48, color: Colors.white24),
          SizedBox(height: 12),
          Text(
            'Busca en tu biblioteca local',
            style: TextStyle(color: Color(0xFF9C9CAD)),
          ),
        ],
      ),
    );
  }
}
