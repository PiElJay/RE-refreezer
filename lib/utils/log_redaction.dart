/// Redact whole credential-bearing values, including Authorization bearer strings.
String redactLog(String text) {
  var safe = text.replaceAllMapped(
    RegExp(
      r'(\b(?:cookie|authorization)\s*[=:]\s*)[^\r\n]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[REDACTED]',
  );
  safe = safe.replaceAllMapped(
    RegExp(
      r'''((?:_auth|arl|trackToken|licenseToken|access_token|apiKey|apiSecret|clientSecret)\s*[=:]\s*)[^\s&\n,}]+''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[REDACTED]',
  );
  return safe;
}
