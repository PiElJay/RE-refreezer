import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../settings.dart';
import 'app_diagnostics.dart';

/// Connection state is transient: it must never overwrite a user's library.
class NetworkMonitor extends ValueNotifier<bool> {
  NetworkMonitor._() : super(false);
  static final instance = NetworkMonitor._();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _timer;
  int _generation = 0;
  bool get offline => !value;
  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = Connectivity().onConnectivityChanged.listen(
      (_) => refresh(),
    );
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
    await refresh();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    bool online = false;
    try {
      final connections = await Connectivity().checkConnectivity();
      if (connections.isNotEmpty &&
          !connections.contains(ConnectivityResult.none)) {
        final response = await http
            .get(Uri.https('api.deezer.com', '/infos'))
            .timeout(const Duration(seconds: 4));
        // A provider rejection is not evidence of airplane mode.
        online = response.statusCode >= 200 && response.statusCode < 600;
        AppDiagnostics.instance.record(
          'networkProbe',
          'REACHABLE',
          httpStatus: response.statusCode,
        );
      }
    } catch (_) {
      /* No Internet, including captive Wi-Fi. */
    }
    if (generation != _generation) return;
    settings.offlineMode = !online;
    value = online;
  }

  void recordProviderSuccess() {
    _generation++;
    settings.offlineMode = false;
    value = true;
  }

  void stopMonitoring() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
    _timer?.cancel();
  }
}
