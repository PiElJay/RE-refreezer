import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/api/cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('older caches load without query history and retain existing data', () {
    final cache = Cache.fromJson({
      'libraryTracks': ['42'],
      'searchHistory2': [],
    });
    expect(cache.searchQueries, isEmpty);
    expect(cache.libraryTracks, ['42']);
  });
  test('query history survives JSON round-trip', () {
    final cache = Cache.fromJson({
      'searchQueries': ['Massive Attack', 'Muse'],
    });
    final restored = Cache.fromJson(cache.toJson());
    expect(restored.searchQueries, ['Massive Attack', 'Muse']);
  });
  test(
    'concurrent searches persist the latest bounded deduplicated history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'refreezer-history-',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
      try {
        final history = Cache.fromJson({});
        await Future.wait(
          List.generate(40, (index) => history.rememberQuery('Track $index')),
        );
        expect(history.searchQueries.length, 30);
        expect(history.searchQueries.first, 'Track 39');
        await history.rememberQuery('  TRACK 20  ');
        await history.rememberQuery('');
        await history.rememberQuery('https://deezer.com/track/42');
        final restored = await Cache.load();
        expect(restored.searchQueries, history.searchQueries);
        expect(restored.searchQueries.first, 'TRACK 20');
        expect(restored.searchQueries.length, 30);
        expect(
          restored.searchQueries
              .where((query) => query.toLowerCase() == 'track 20')
              .length,
          1,
        );
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );
}
