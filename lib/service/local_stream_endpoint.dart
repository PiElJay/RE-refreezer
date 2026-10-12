/// The native server binds an available IPv4 loopback port for this process.
class LocalStreamEndpoint {
  static final instance = LocalStreamEndpoint();
  int? _port;

  void configure(int port) {
    if (port <= 0 || port > 65535) throw ArgumentError.value(port, 'port');
    _port = port;
  }

  Uri _uri(String path, [Map<String, String>? parameters]) {
    final port = _port;
    if (port == null) throw StateError('Local audio server is not initialized');
    return Uri.http('127.0.0.1:$port', path, parameters);
  }

  Uri track(Map<String, String> parameters) => _uri('/', parameters);
  Uri get health => _uri('/health');
}
