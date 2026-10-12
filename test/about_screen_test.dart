import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttericon/font_awesome5_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:refreezer/ui/settings_screen.dart';

void main() {
  testWidgets('Info shows the VYBE logo, PiElJay, repository and unchanged donations', (tester) async {
    PackageInfo.setMockInitialValues(appName: 'VYBE MUSIC', packageName: 'r.r.refreezer.preview',
      version: '1.0.0', buildNumber: '5000', buildSignature: 'fixture');
    await tester.pumpWidget(const MaterialApp(home: CreditsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('PiElJay'), findsOneWidget);
    expect(find.text('github.com/PiElJay'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
    expect(find.text('Da una base di ReFreezer di DJDoubleD'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image).first);
    expect((image.image as AssetImage).assetName, 'assets/vybe_music.png');
    expect(find.text('Andrea'), findsNothing);
    expect(find.text('Crowdin'), findsNothing);
    expect(find.textContaining('Huge thanks'), findsNothing);
    await tester.scrollUntilVisible(find.text('Lascia una stella su GitHub'), 250);
    expect(find.text('GitHub · contribuisci con le tue idee'), findsOneWidget);
    await tester.scrollUntilVisible(find.byIcon(FontAwesome5.paypal), 150);
    await tester.tap(find.byIcon(FontAwesome5.paypal));
    await tester.pumpAndSettle();
    expect(find.text('No really, go support your favorite artists instead ;)'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
