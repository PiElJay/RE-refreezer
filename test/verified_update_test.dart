import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:refreezer/service/verified_update.dart';

void main() {
  late Directory directory;
  final bytes = [80, 75, 3, 4, 1, 2, 3];
  final url = Uri.parse('https://github.com/PiElJay/VYBE-MUSIC/releases/download/1.0.2/app.apk');
  setUp(() async { directory = await Directory.systemTemp.createTemp('vybe-update-'); });
  tearDown(() async { await directory.delete(recursive: true); });
  test('validated update replaces destination only after matching size and hash', () async {
    final file = File('${directory.path}/update.apk');
    await file.writeAsString('previous verified file');
    final client = MockClient((_) async => http.Response.bytes(bytes, 200));
    try {
      await downloadVerifiedUpdate(client: client, url: url,
        expectedDigest: 'sha256:${sha256.convert(bytes)}', expectedSize: bytes.length,
        destination: file);
      expect(await file.readAsBytes(), bytes);
      expect(await File('${file.path}.part').exists(), isFalse);
    } finally { client.close(); }
  });
  for (final attack in ['tampered', 'truncated', 'oversized', 'http error', 'http redirect', 'missing hash', 'wrong repository']) {
    test('rejects $attack without replacing a previous validated APK', () async {
      final file = File('${directory.path}/update.apk');
      await file.writeAsString('previous verified file');
      final client = MockClient((_) async {
        if (attack == 'http error') return http.Response('error', 403);
        if (attack == 'http redirect') return http.Response('', 302, headers: {'location':'http://example.invalid/app.apk'});
        return http.Response.bytes(attack == 'tampered' ? [0,0,0,0,0,0,0] : bytes, 200);
      });
      try {
        await expectLater(downloadVerifiedUpdate(client: client,
          url: attack == 'wrong repository' ? Uri.parse('https://github.com/attacker/project/releases/download/1/app.apk') : url,
          expectedDigest: attack == 'missing hash' ? '' : 'sha256:${sha256.convert(bytes)}',
          expectedSize: attack == 'truncated' ? bytes.length + 1 : attack == 'oversized' ? bytes.length - 1 : bytes.length,
          destination: file), throwsFormatException);
        expect(await file.readAsString(), 'previous verified file');
        expect(await File('${file.path}.part').exists(), isFalse);
      } finally { client.close(); }
    });
  }
}
