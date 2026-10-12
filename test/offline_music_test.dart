import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:audio_service/audio_service.dart';
import 'package:refreezer/api/definitions.dart';
import 'package:refreezer/api/download.dart';
import 'package:refreezer/service/audio_service.dart';
import 'package:refreezer/service/local_music.dart';
import 'package:refreezer/service/offline_music.dart';
import 'package:refreezer/ui/offline_tracks.dart';

LocalSong song(int id) => LocalSong(uri: 'content://media/external/audio/media/$id',
  name: '$id.flac', title: 'Brano importato $id', artist: 'Artista', album: 'Album',
  durationMs: 180000, size: 4000000);

class _Handler extends BaseAudioHandler implements AudioPlayerHandler {
  List<Track>? played;
  int? selected;
  @override
  Future<void> playFromTrackList(List<Track> tracks, String id, QueueSource source,
    {int? selectedIndex}) async { played = tracks; selected = selectedIndex; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Downloads extends DownloadManager {
  @override
  Future<bool> checkOffline({Album? album, Track? track, Playlist? playlist}) async => true;
}

void main() {
  late Directory directory;
  late LocalMusicLibrary local;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vybe-offline-');
    local = LocalMusicLibrary(fileProvider: () async => File('${directory.path}/music.json'));
  });
  tearDown(() async { local.dispose(); await directory.delete(recursive: true); });

  test('offline view combines completed downloads and persisted imports once', () async {
    await local.importSongs([song(1)]);
    final tracks = await OfflineMusicLibrary(local: local,
      downloads: () async => [Track(id: '42'), Track(id: '42'), Track(id: 'missing')],
      available: (track) async => track.id != 'missing').load();
    expect(tracks.map((track) => track.id), ['42', song(1).toTrack().id]);
    expect(tracks.last.localUri, song(1).uri);
    expect(tracks.last.offline, isTrue);
  });

  test('local music remains visible if the download database fails', () async {
    await local.importSongs([song(1)]);
    final tracks = await OfflineMusicLibrary(local: local,
      downloads: () async => throw StateError('fixture database unavailable')).load();
    expect(tracks.single.localUri, song(1).uri);
  });

  test('valid downloads remain visible if the local index cannot be read', () async {
    await File('${directory.path}/music.json').writeAsString('corrupt fixture');
    final tracks = await OfflineMusicLibrary(local: local,
      downloads: () async => [Track(id: '42')], available: (_) async => true).load();
    expect(tracks.single.id, '42');
  });

  test('both unreadable indexes report an error instead of an empty library', () async {
    await File('${directory.path}/music.json').writeAsString('corrupt fixture');
    await expectLater(OfflineMusicLibrary(local: local,
      downloads: () async => throw StateError('fixture database unavailable')).load(),
      throwsA(isA<OfflineMusicReadException>()));
  });

  testWidgets('an import updates Brani offline and plays its precise queue position', (tester) async {
    final handler = _Handler();
    GetIt.I.registerSingleton<AudioPlayerHandler>(handler);
    final previous = downloadManager;
    downloadManager = _Downloads();
    addTearDown(() async { downloadManager = previous; await GetIt.I.reset(); });
    final library = OfflineMusicLibrary(local: local, downloads: () async => [], available: (_) async => true);
    await tester.pumpWidget(MaterialApp(home: OfflineTracksScreen(library: library)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Importa la musica'), findsOneWidget);
    await local.importSongs([song(1), song(2)]);
    await tester.pumpAndSettle();
    expect(find.text('Brano importato 1'), findsOneWidget);
    expect(find.text('Brano importato 2'), findsOneWidget);
    await tester.tap(find.text('Brano importato 2'));
    await tester.pumpAndSettle();
    expect(handler.selected, 1);
    expect(handler.played![handler.selected!].localUri, song(2).uri);
    await local.remove(song(1).uri);
    await tester.pumpAndSettle();
    expect(find.text('Brano importato 1'), findsNothing);
    expect(find.text('Brano importato 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
