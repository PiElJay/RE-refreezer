import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../api/definitions.dart';
import '../service/audio_service.dart';
import '../service/offline_music.dart';
import 'local_music_screen.dart';
import 'tiles.dart';
import 'menu.dart';

class OfflineTracksScreen extends StatefulWidget {
  final OfflineMusicLibrary? library;
  const OfflineTracksScreen({super.key, this.library});
  @override
  State<OfflineTracksScreen> createState() => _OfflineTracksScreenState();
}

class _OfflineTracksScreenState extends State<OfflineTracksScreen> {
  late final OfflineMusicLibrary _library = widget.library ?? OfflineMusicLibrary();
  late Future<List<Track>> _tracks;
  void _refresh() {
    if (mounted) setState(() => _tracks = _library.load());
  }

  @override
  void initState() {
    super.initState();
    _tracks = _library.load();
    _library.local.addListener(_refresh);
  }

  @override
  void dispose() {
    _library.local.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Brani offline'), actions: [
      IconButton(tooltip: 'Importa dal dispositivo', icon: const Icon(Icons.add_rounded),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LocalMusicScreen(library: _library.local)))),
    ]),
    body: FutureBuilder<List<Track>>(
      future: _tracks,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(child: Text('Impossibile leggere i brani offline'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final tracks = snapshot.data!;
        if (tracks.isEmpty)
          return const Center(
            child: Text(
              'Importa la musica dal dispositivo o scarica un brano per ascoltarlo offline',
            ),
          );
        return ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return TrackTile(
              track,
              key: ValueKey('${track.id}:$index'),
              onTap: () => GetIt.I<AudioPlayerHandler>().playFromTrackList(
                tracks,
                track.id!,
                QueueSource(source: 'offline', text: 'Brani offline'),
                selectedIndex: index,
              ),
              onHold: () =>
                  MenuSheet().defaultTrackMenu(track, context: context),
            );
          },
        );
      },
    ),
  );
}
