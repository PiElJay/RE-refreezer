import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/settings.dart';
import 'package:refreezer/ui/quality_notice.dart';
import 'package:refreezer/ui/settings_screen.dart';

void main() {
  test('fresh remote settings use 128 while existing and offline formats survive', () {
    final fresh = Settings.fromJson({});
    expect(fresh.wifiQuality, AudioQuality.MP3_128);
    expect(fresh.mobileQuality, AudioQuality.MP3_128);
    expect(fresh.downloadQuality, AudioQuality.MP3_128);
    expect(fresh.offlineQuality, AudioQuality.FLAC);
    final saved = Settings.fromJson({'wifiQuality': 'FLAC', 'downloadQuality': 'ASK'});
    expect(saved.wifiQuality, AudioQuality.FLAC);
    expect(saved.downloadQuality, AudioQuality.ASK);
  });

  for (final quality in [AudioQuality.MP3_320, AudioQuality.FLAC]) {
    testWidgets('$quality requires explicit confirmation, dismissal cancels', (tester) async {
      bool? choice;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
        builder: (context) => TextButton(onPressed: () async {
          choice = await confirmOnlineQuality(context, quality);
        }, child: const Text('Choose')),
      ))));
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.textContaining('richiede un abbonamento'), findsOneWidget);
      expect(choice, isNull);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(choice, isFalse);
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seleziona comunque'));
      await tester.pumpAndSettle();
      expect(choice, isTrue);
    });
  }

  testWidgets('128 requires no subscription confirmation', (tester) async {
    bool? choice;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(onPressed: () async {
        choice = await confirmOnlineQuality(context, AudioQuality.MP3_128);
      }, child: const Text('Choose')),
    ))));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(choice, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancelled WiFi selection keeps saved 128 and fits a narrow screen', (tester) async {
    settings = Settings.fromJson({});
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: QualityPicker('wifi'),
    ))));
    await tester.tap(find.byType(Radio<AudioQuality>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(settings.wifiQuality, AudioQuality.MP3_128);
    expect(tester.widget<Radio<AudioQuality>>(find.byType(Radio<AudioQuality>).first).groupValue,
      AudioQuality.MP3_128);
    expect(tester.takeException(), isNull);
  });
}
