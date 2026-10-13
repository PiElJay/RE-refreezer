import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class _DigestSink implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest value) { digest = value; }
  @override
  void close() {}
}

/// Download only the official release asset; publish it locally after validation.
Future<File> downloadVerifiedUpdate({
  required http.Client client,
  required Uri url,
  required String expectedDigest,
  required int expectedSize,
  required File destination,
  void Function(double)? onProgress,
}) async {
  if (url.scheme != 'https' || url.host != 'github.com' || url.userInfo.isNotEmpty ||
      url.hasQuery || url.hasFragment ||
      !url.path.startsWith('/PiElJay/VYBE-MUSIC/releases/download/') ||
      !url.path.endsWith('.apk')) throw const FormatException('Invalid update source');
  if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(expectedDigest) ||
      expectedSize <= 0 || expectedSize > 200 * 1024 * 1024)
    throw const FormatException('Invalid update integrity metadata');
  final temporary = File('${destination.path}.part');
  IOSink? output;
  try {
    var current = url;
    http.StreamedResponse? response;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = http.Request('GET', current)..followRedirects = false;
      response = await client.send(request).timeout(const Duration(seconds: 20));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.timeout(const Duration(seconds: 30)).drain<void>();
        if (location == null) throw const FormatException('Invalid redirect');
        current = current.resolve(location);
        if (current.scheme != 'https' || current.userInfo.isNotEmpty)
          throw const FormatException('Insecure update redirect');
        response = null;
        continue;
      }
      break;
    }
    if (response == null || response.statusCode != 200)
      throw const FormatException('Update download rejected');
    if (response.contentLength != null && response.contentLength != expectedSize)
      throw const FormatException('Unexpected update size');
    output = temporary.openWrite();
    final result = _DigestSink();
    final hash = sha256.startChunkedConversion(result);
    var received = 0;
    await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
      received += chunk.length;
      if (received > expectedSize) throw const FormatException('Oversized update');
      hash.add(chunk);
      output.add(chunk);
      onProgress?.call(received / expectedSize);
    }
    hash.close();
    await output.flush();
    await output.close();
    output = null;
    if (received != expectedSize || 'sha256:${result.digest}' != expectedDigest)
      throw const FormatException('Update integrity check failed');
    return await temporary.rename(destination.path);
  } catch (_) {
    if (output != null) await output.close();
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}
