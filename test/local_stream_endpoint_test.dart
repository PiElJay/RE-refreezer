import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/service/local_stream_endpoint.dart';

void main() {
  test(
    'stream credentials stay in encoded query values on the assigned loopback port',
    () {
      final endpoint = LocalStreamEndpoint()..configure(60345);
      final uri = endpoint.track({
        'id': '1',
        'trackToken': 'test+/=&forceOnline=1',
      });
      expect(uri.host, '127.0.0.1');
      expect(uri.port, 60345);
      expect(uri.queryParameters['trackToken'], 'test+/=&forceOnline=1');
      expect(uri.queryParameters.containsKey('forceOnline'), isFalse);
      expect(endpoint.health.path, '/health');
      expect(endpoint.health.port, 60345);
    },
  );
  test(
    'using an endpoint before native startup fails instead of contacting a stale port',
    () {
      final endpoint = LocalStreamEndpoint();
      expect(() => endpoint.track({'id': '1'}), throwsStateError);
    },
  );
}
