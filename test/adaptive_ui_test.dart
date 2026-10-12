import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:refreezer/api/cache.dart';
import 'package:refreezer/service/audio_service.dart';
import 'package:refreezer/settings.dart';
import 'package:refreezer/ui/dashboard.dart';
import 'package:refreezer/ui/modern_player.dart';
import 'package:refreezer/ui/search.dart';

class _Handler extends BaseAudioHandler implements AudioPlayerHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Handler handler;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('refreezer-ui-');
    await File(
      '${directory.path}/homescreen.json',
    ).writeAsString('{"sections":[]}');
    settings = Settings.fromJson({})..offlineMode = true;
    cache = Cache.fromJson({});
    handler = _Handler();
    GetIt.I.registerSingleton<AudioPlayerHandler>(handler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDown(() async {
    await GetIt.I.reset();
    await directory.delete(recursive: true);
  });
  for (final size in [
    const Size(320, 720),
    const Size(844, 390),
    const Size(1024, 768),
  ]) {
    testWidgets('dashboard and player fit $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget app(Widget home) => MaterialApp(
        theme: settings.themeData,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: home,
      );
      await tester.pumpWidget(app(const MusicDashboard()));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      handler.mediaItem.add(
        const MediaItem(
          id: '42',
          title: 'Un titolo molto lungo per verificare il player',
          artist: 'Un artista con un nome lungo',
          duration: Duration(minutes: 4),
        ),
      );
      await tester.pumpWidget(
        app(ModernPlayer(positionStream: Stream.value(Duration.zero))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Deezer'), findsOneWidget);
      expect(tester.takeException(), isNull);
      cache.searchQueries = ['Massive Attack'];
      await tester.pumpWidget(app(const SearchScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Ricerche recenti'), findsOneWidget);
      expect(find.text('Massive Attack'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
}
