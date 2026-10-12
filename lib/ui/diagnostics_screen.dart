import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../api/deezer.dart';
import '../api/download.dart';
import '../service/app_diagnostics.dart';
import '../service/network_monitor.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _checking = false;
  final _diagnostics = AppDiagnostics.instance;
  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await NetworkMonitor.instance.refresh();
      _diagnostics.record(
        'network',
        NetworkMonitor.instance.offline ? 'OFFLINE' : 'ONLINE',
      );
      if (!NetworkMonitor.instance.offline) await deezerAPI.authorize();
      try {
        final response = await http
            .get(Uri.http('127.0.0.1:36958', '/health'))
            .timeout(const Duration(seconds: 2));
        final body = jsonDecode(response.body);
        _diagnostics.record(
          'localServer',
          response.statusCode == 200 && body is Map && body['status'] == 'ready'
              ? 'READY'
              : 'BAD_RESPONSE',
        );
      } catch (_) {
        _diagnostics.record('localServer', 'UNREACHABLE');
      }
      try {
        final native = await DownloadManager.platform
            .invokeMapMethod<String, dynamic>('getPlaybackDiagnostics');
        final code = native?['errorCode'];
        if (code is String) _diagnostics.record('nativeStream', code);
        _diagnostics.record(
          'nativeSession',
          native?['authorized'] == true ? 'AUTHENTICATED' : 'NOT_AUTHENTICATED',
        );
      } catch (_) {
        _diagnostics.record('nativeBridge', 'UNAVAILABLE');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Diagnostica')),
    body: AnimatedBuilder(
      animation: _diagnostics,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Stato di sessione, API e player. Il report contiene soltanto codici tecnici: non include password, cookie o token.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _checking ? null : _check,
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
            label: const Text('Verifica sistema'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: _diagnostics.report()),
              );
              if (context.mounted)
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Report copiato')));
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copia report'),
          ),
          const SizedBox(height: 20),
          SelectableText(
            _diagnostics.report(),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    ),
  );
}
