import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:refreezer/service/audio_service.dart';
import 'package:refreezer/settings.dart';
import 'package:refreezer/ui/player_bar.dart';
import 'package:refreezer/utils/mediaitem_converter.dart';

class _Handler extends BaseAudioHandler implements AudioPlayerHandler {
  @override
  Stream<QueueState> get queueStateStream => Stream.value(QueueState.empty);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final size in [const Size(320, 720), const Size(844, 390)]) {
    testWidgets('local music without art survives bottom bar and queue restore on $size', (tester) async {
      tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      settings = Settings.fromJson({});
      final handler = _Handler(); GetIt.I.registerSingleton<AudioPlayerHandler>(handler);
      addTearDown(() => GetIt.I.reset());
      final item = MediaItemConverter.mediaItemFromMap({
        'id': 'local:content://media/external/audio/media/42', 'title': 'Musica locale',
        'artist': 'Artista', 'duration': null, 'artUri': null,
        'extras': {'thumb': null, 'localUri': 'content://media/external/audio/media/42'},
      });
      handler.mediaItem.add(item);
      await tester.pumpWidget(MaterialApp(theme: settings.themeData, home: const Scaffold(
        body: SizedBox.expand(), bottomNavigationBar: PlayerBar())));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Musica locale'), findsOneWidget);
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
      final restored = MediaItemConverter.restoreQueue({'queue': [MediaItemConverter.mediaItemToMap(item)], 'index': 0});
      handler.mediaItem.add(restored.items.single);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test('artwork always resolves to a string including missing or invalid thumbnail', () {
    expect(MediaItemConverter.artworkUrl(const MediaItem(id: '1', title: 'No art')), '');
    final uri = Uri.parse('https://example.com/cover.jpg');
    expect(MediaItemConverter.artworkUrl(MediaItem(id: '2', title: '', artUri: uri, extras: {'thumb': null})), uri.toString());
    expect(MediaItemConverter.artworkUrl(MediaItem(id: '3', title: '', artUri: uri, extras: {'thumb': 123})), uri.toString());
    expect(MediaItemConverter.artworkUrl(MediaItem(id: '4', title: '', extras: {'thumb': uri})), uri.toString());
  });
  test('legacy missing fields and bad rows retain the selected queue occurrence', () {
    final restored = MediaItemConverter.restoreQueue({'queue': [null, {'id': null}, {'id': '42', 'title': null, 'duration': null, 'extras': null}, {'id': '42', 'title': 'Second occurrence'}], 'index': 3, 'position': 9000});
    expect(restored.items, hasLength(2)); expect(restored.index, 1);
    expect(restored.items[restored.index].title, 'Second occurrence');
    expect(restored.position, const Duration(seconds: 9));
    expect(restored.items.first.duration, isNull);
    final missing = MediaItemConverter.restoreQueue({'queue': [{'id': 'a'}, {'id': null}, {'id': 'b'}], 'index': 1, 'position': 9000});
    expect(missing.items[missing.index].id, 'b'); expect(missing.position, Duration.zero);
  });
}
