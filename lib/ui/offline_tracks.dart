import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../api/download.dart';
import '../api/definitions.dart';
import '../service/audio_service.dart';
import 'tiles.dart';
import 'menu.dart';

class OfflineTracksScreen extends StatefulWidget {
  const OfflineTracksScreen({super.key});
  @override
  State<OfflineTracksScreen> createState() => _OfflineTracksScreenState();
}

class _OfflineTracksScreenState extends State<OfflineTracksScreen> {
  late Future<List<Track>> _tracks;
  Future<List<Track>> _load() async {
    final tracks = await downloadManager.allOfflineTracks();
    final available = <Track>[];
    for (final track in tracks) {
      if (await downloadManager.checkOffline(track: track))
        available.add(track);
    }
    return available;
  }

  @override
  void initState() {
    super.initState();
    _tracks = _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Disponibili offline')),
    body: FutureBuilder<List<Track>>(
      future: _tracks,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(child: Text('Impossibile leggere i download'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final tracks = snapshot.data!;
        if (tracks.isEmpty)
          return const Center(
            child: Text(
              'Scarica un brano per ascoltarlo anche in modalità aereo',
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
                QueueSource(source: 'offline', text: 'Download'),
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
