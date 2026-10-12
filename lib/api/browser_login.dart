/// The account website replaced the legacy www.deezer.com/login entry point.
final deezerBrowserLoginUrl = Uri.https('account.deezer.com', '/it/login/');

class BrowserLoginSession {
  final String arl;
  final Uri cookieUrl;

  const BrowserLoginSession(this.arl, this.cookieUrl);
}

/// Read only Deezer cookie scopes. The account website can issue host-only
/// cookies, which a lookup against www.deezer.com cannot see.
Future<BrowserLoginSession?> readDeezerBrowserSession(
  Future<String?> Function(Uri url) readArl,
) async {
  for (final url in [
    Uri.https('www.deezer.com', '/'),
    Uri.https('account.deezer.com', '/'),
    Uri.https('deezer.com', '/'),
  ]) {
    try {
      final value = (await readArl(url))?.trim();
      if (value != null && value.isNotEmpty) {
        return BrowserLoginSession(value, url);
      }
    } catch (_) {
      // A failed cookie scope must not prevent checking the next scope.
      // Exceptions can contain session data: do not print them.
    }
  }
  return null;
}
