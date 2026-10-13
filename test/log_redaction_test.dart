import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/utils/log_redaction.dart';

void main() {
  test('diagnostics retain track ID but redact streaming credentials', () {
    final safe = redactLog(
      'http://localhost/?id=42&trackToken=secret&arl=credential',
    );
    expect(safe, contains('id=42'));
    expect(safe, isNot(contains('secret')));
    expect(safe, isNot(contains('credential')));
  });
  test('authorization and cookie values are redacted', () {
    expect(
      redactLog('Cookie=private-cookie\nAuthorization=Bearer private-auth'),
      'Cookie=[REDACTED]\nAuthorization=[REDACTED]',
    );
  });
  test('local server access nonce is redacted', () {
    expect(redactLog('http://127.0.0.1:123/?_auth=secret&id=1'), isNot(contains('secret')));
  });

}
