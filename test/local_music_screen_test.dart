import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/service/local_music.dart';
import 'package:refreezer/ui/local_music_screen.dart';
class _Library extends LocalMusicLibrary {
  List<LocalSong> songs = [];
  @override
  Future<List<LocalSong>> load() async => songs;
  @override
  Future<Map<String, dynamic>> discover({bool folder = false}) async => {
    'items': [
      {'uri': 'content://media/external/audio/media/1', 'path': 'Music/',
        'name': 'Test.flac', 'title': 'Un brano già scaricato', 'artist': 'Artista',
        'album': 'Album', 'durationMs': 190000, 'size': 4000000, 'isMusic': true},
      {'uri': 'content://media/external/audio/media/2', 'path': 'WhatsApp Voice Notes/',
        'name': 'PTT-20261012.opus', 'durationMs': 190000, 'size': 4000000, 'isMusic': true},
    ]
  };
  @override
  Future<int> importSongs(List<LocalSong> incoming) async { songs = [...songs, ...incoming]; return incoming.length; }
}
void main() {
  for (final size in [const Size(320,720), const Size(844,390), const Size(1024,768)]) {
    testWidgets('scan, preview and import on $size with large text', (tester) async {
      tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final library = _Library();
      await tester.pumpWidget(MaterialApp(theme: ThemeData(useMaterial3: true),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!),
        home: LocalMusicScreen(library: library)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Scansiona telefono'));
      await tester.tap(find.text('Scansiona telefono')); await tester.pumpAndSettle();
      expect(find.text('1 nuovi brani · 1 esclusi o già presenti.'), findsOneWidget);
      expect(find.text('PTT-20261012.opus'), findsNothing);
      await tester.ensureVisible(find.text('Importa 1 brani'));
      await tester.tap(find.text('Importa 1 brani')); await tester.pumpAndSettle();
      expect(library.songs.single.uri, 'content://media/external/audio/media/1');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
