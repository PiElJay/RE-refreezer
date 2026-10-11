import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/api/browser_login.dart';
import 'package:refreezer/api/deezer_login.dart';

void main() {
  test('reads a host-only session issued by the account website', () async {
    final visited = <String>[];
    final session = await readDeezerBrowserSession((url) async {
      visited.add(url.host);
      return url.host == 'account.deezer.com' ? ' account-session ' : null;
    });
    expect(session?.arl, 'account-session');
    expect(session?.cookieUrl.host, 'account.deezer.com');
    expect(visited, ['www.deezer.com', 'account.deezer.com']);
  });

  test(
    'a failed scope and a blank cookie still allow the next scope',
    () async {
      final session = await readDeezerBrowserSession((url) async {
        if (url.host == 'www.deezer.com') {
          throw StateError('cookie read failed');
        }
        return url.host == 'account.deezer.com' ? '  ' : 'root-session';
      });
      expect(session?.arl, 'root-session');
      expect(session?.cookieUrl.host, 'deezer.com');
    },
  );

  test('unauthenticated pages do not complete login', () async {
    expect(await readDeezerBrowserSession((_) async => null), isNull);
  });

  test(
    'a website session ends lookup without reading unrelated scopes',
    () async {
      final visited = <String>[];
      final session = await readDeezerBrowserSession((url) async {
        visited.add(url.host);
        return 'website-session';
      });
      expect(session?.arl, 'website-session');
      expect(visited, ['www.deezer.com']);
    },
  );

  test('missing app configuration fails before any password request', () async {
    // This fixture uses the empty app credentials shipped in .env.example.
    if (DeezerLogin.emailLoginConfigured) return;
    await expectLater(
      DeezerLogin.getArlByEmailAndPassword('test@example.invalid', 'test-only'),
      throwsA(
        isA<DeezerLoginException>().having(
          (exception) => exception.type,
          'type',
          'AppConfiguration',
        ),
      ),
    );
  });
}
