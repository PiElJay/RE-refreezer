import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Only structured codes and statuses: no provider bodies, URLs or credentials.
class AppDiagnostics extends ChangeNotifier {
  static final instance = AppDiagnostics();
  final List<String> _events = [];
  final Map<String, String> _state = {};
  void record(String stage, String code, {int? httpStatus}) {
    final safe = RegExp(r'^[A-Za-z0-9_. -]{1,96}$');
    if (!safe.hasMatch(stage) || !safe.hasMatch(code)) return;
    final value = '$code${httpStatus == null ? '' : ' HTTP $httpStatus'}';
    _state[stage] = value;
    final time = DateTime.now().toIso8601String().substring(11, 19);
    _events.add('$time $stage: $value');
    if (_events.length > 50) _events.removeAt(0);
    Logger.root.info('Diagnostic $stage: $value');
    notifyListeners();
  }

  String report() => [
    'PiElJay - diagnostica 0.8.2',
    ..._state.entries.map((entry) => '${entry.key}: ${entry.value}'),
    '',
    ..._events,
  ].join('\n');
}
