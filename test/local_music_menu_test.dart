import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/api/definitions.dart';
import 'package:refreezer/ui/menu.dart';

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
}
