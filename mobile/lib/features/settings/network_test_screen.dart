import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/device_auth.dart';
import '../../services/network_probe.dart';
import '../../services/settings_store.dart';

/// Settings > Diagnostics > NETWORK TEST: the same connector the app uses,
/// forced over IPv4 and over IPv6, so a lossy family shows up as numbers.
/// Each request is logged as one `EGGNET {json}` line for `adb logcat`.
class NetworkTestScreen extends StatefulWidget {
  const NetworkTestScreen({
    required this.settings,
    required this.deviceAuth,
    super.key,
  });

  final SettingsStore settings;
  final DeviceAuth deviceAuth;

  @override
  State<NetworkTestScreen> createState() => _NetworkTestScreenState();
}

class _NetworkTestScreenState extends State<NetworkTestScreen> {
  final List<ProbeResult> _results = [];
  NetworkProbe? _probe;
  bool _running = false;
  int _planned = 0;
  String? _note;

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _running = true;
      _results.clear();
      _note = 'Checking whether this phone may run the upload test...';
    });
    try {
      final baseUrl = await widget.settings.getBaseUrl();
      // Uploads only for an approved phone on a server that offers them.
      final device = await ApiClient(baseUrl).checkDevice();
      final withUploads = device.authRequired && device.mayScan;
      final probe = NetworkProbe(
        baseUrl: baseUrl,
        deviceAuth: widget.deviceAuth,
      );
      _probe = probe;
      if (!mounted) return;
      setState(() {
        _planned = probe.plannedCount(withUploads: withUploads);
        _note = withUploads
            ? null
            : 'Upload test skipped: ${device.authRequired ? device.label : 'this server does not offer it'}.';
      });
      await for (final result in probe.run(withUploads: withUploads)) {
        debugPrint('EGGNET ${jsonEncode(result.toJson())}');
        if (!mounted) {
          probe.stop();
          break;
        }
        setState(() => _results.add(result));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _note = 'Network test stopped: $error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _probe?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ProbeSummary.of(_results);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Network test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '20 server health checks over IPv4 and 20 over IPv6, 10 Cloudflare '
            'control requests per family, and 3 uploads of 500 KB when this '
            'phone is approved. Each request uses a new connection. Takes a '
            'few minutes on a weak link.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? null : _start,
            icon: const Icon(Icons.network_check),
            label: Text(_running ? 'RUNNING...' : 'START NETWORK TEST'),
          ),
          if (_running) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _planned == 0 ? null : _results.length / _planned,
            ),
            const SizedBox(height: 6),
            Text('${_results.length} of $_planned requests'),
          ],
          if (_note != null) ...[
            const SizedBox(height: 12),
            Text(_note!),
          ],
          if (summaries.isNotEmpty) ...[
            const SizedBox(height: 16),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2.2),
                1: FlexColumnWidth(1.1),
                2: FlexColumnWidth(1.1),
                3: FlexColumnWidth(1.1),
                4: FlexColumnWidth(1.3),
              },
              children: [
                TableRow(
                  children: [
                    for (final head in const ['Test', 'OK', 'TCP', 'TLS', 'Total'])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          head,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
                for (final s in summaries)
                  TableRow(
                    children: [
                      _cell('${s.target} ${s.family}'),
                      _cell('${s.okCount}/${s.results.length}'),
                      _cell(_ms(s.meanTcpMs)),
                      _cell(_ms(s.meanTlsMs)),
                      _cell(_ms(s.meanTotalMs)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Times are means over successful requests.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final s in summaries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${s.target} ${s.family}: '
                  '${s.outcomes.entries.map((e) => '${e.key} ${e.value}').join(', ')}'
                  '${s.remotes.isEmpty ? '' : '; via ${s.remotes.join(', ')}'}'
                  '${s.colos.isEmpty ? '' : '; colo ${s.colos.join(', ')}'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _ms(int? value) => value == null ? '-' : '$value ms';

  static Widget _cell(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(text),
  );
}
