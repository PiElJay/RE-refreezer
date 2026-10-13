import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:get_it/get_it.dart';
import 'package:refreezer/service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/api/definitions.dart';
import 'package:refreezer/ui/menu.dart';

class QueueMenuHandler extends BaseAudioHandler implements AudioPlayerHandler {
  final appended = <String>[];
  final next = <String>[];
  bool fail = false;
  @override
  Future<void> addQueueItem(MediaItem item) async {
    if (fail) throw StateError('Unavailable');
    appended.add(item.id);
  }
  @override
  Future<void> insertQueueItem(int index, MediaItem item) async {
    if (fail) throw StateError('Unavailable');
    expect(index, -1);
    next.add(item.id);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('local track menu never offers Deezer, download or cloud actions', (tester) async {
    tester.view.physicalSize = const Size(320, 720); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => MenuSheet().defaultTrackMenu(
        Track(id: 'local:content://media/external/audio/media/42', localUri: 'content://media/external/audio/media/42', title: 'Musica locale'),
        context: context), child: const Text('Apri opzioni'))))));
    await tester.tap(find.text('Apri opzioni')); await tester.pumpAndSettle();
    expect(find.text('Musica locale'), findsOneWidget);
    expect(find.byIcon(Icons.playlist_play), findsOneWidget);
    expect(find.byIcon(Icons.playlist_add), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.offline_pin), findsNothing);
    expect(find.byIcon(Icons.online_prediction), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final next in [false, true]) {
    testWidgets('queue menu dispatches ${next ? "play next" : "append"} and confirms', (tester) async {
      final handler = QueueMenuHandler();
      GetIt.I.registerSingleton<AudioPlayerHandler>(handler);
      addTearDown(() => GetIt.I.reset());
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: TextButton(onPressed: () => MenuSheet().defaultTrackMenu(
          Track(id: 'local:42', localUri: 'file:///song.mp3', title: 'Song'), context: context),
          child: const Text('Menu'))))));
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      final action = find.byIcon(next ? Icons.playlist_play : Icons.playlist_add);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(next ? handler.next : handler.appended, ['local:42']);
      expect(next ? handler.appended : handler.next, isEmpty);
      expect(find.text(next ? 'Il brano verrà riprodotto subito dopo' : 'Brano aggiunto alla fine della coda'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

}
