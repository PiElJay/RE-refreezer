import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/api/definitions.dart';
import 'package:refreezer/settings.dart';
import 'package:refreezer/ui/home_screen.dart';

HomePage recommendations() => HomePage(sections: [HomePageSection(
  title: 'Suggerimenti disponibili', layout: HomePageSectionLayout.ROW, items: [])]);

void main() {
  setUp(() { settings = Settings.fromJson({})..offlineMode = false; });
  testWidgets('missing cache followed by API success shows recommendations', (tester) async {
    final remote = Completer<HomePage>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomePageScreen(
      cacheLoader: () async => throw StateError('No cache'),
      remoteLoader: () => remote.future,
      cacheWriter: (_) async => throw StateError('Storage unavailable'),
    ))));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    remote.complete(recommendations());
    await tester.pumpAndSettle();
    expect(find.text('Suggerimenti disponibili'), findsOneWidget);
    expect(find.text('Riprova'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cached recommendations survive a failed refresh', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomePageScreen(
      cacheLoader: () async => recommendations(),
      remoteLoader: () async => throw StateError('Network failed'),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Suggerimenti disponibili'), findsOneWidget);
    expect(find.text('Riprova'), findsNothing);
  });
  testWidgets('retry recovers without clearing app data', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomePageScreen(
      cacheLoader: () async => throw StateError('No cache'),
      remoteLoader: () async {
        if (++attempts == 1) throw StateError('Network failed');
        return recommendations();
      }, cacheWriter: (_) async {},
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Suggerimenti disponibili'), findsOneWidget);
    expect(find.text('Riprova'), findsNothing);
  });
  testWidgets('late response after leaving homepage is ignored', (tester) async {
    final remote = Completer<HomePage>();
    await tester.pumpWidget(MaterialApp(home: HomePageScreen(
      cacheLoader: () async => throw StateError('No cache'),
      remoteLoader: () => remote.future, cacheWriter: (_) async {},
    )));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    remote.complete(recommendations());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
