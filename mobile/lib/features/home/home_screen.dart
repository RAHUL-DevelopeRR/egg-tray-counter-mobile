import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/history_database.dart';
import '../../services/settings_store.dart';
import '../scan_flow/scan_flow_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.cameras,
    required this.settings,
    required this.history,
    super.key,
  });

  final List<CameraDescription> cameras;
  final SettingsStore settings;
  final HistoryDatabase history;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ScanHistoryEntry> _recent = const [];
  bool? _backendOnline;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final entries = await widget.history.recent();
    final baseUrl = await widget.settings.getBaseUrl();
    final online = await ApiClient(baseUrl).health();
    if (!mounted) return;
    setState(() {
      _recent = entries;
      _backendOnline = online;
    });
  }

  Future<void> _startScan() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ScanFlowScreen(
          cameras: widget.cameras,
          settings: widget.settings,
          history: widget.history,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SettingsScreen(store: widget.settings)),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.inventory_2_outlined),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('EGG TRAY', style: textTheme.labelLarge),
                        Text(
                          'Counter',
                          style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.tune),
                    tooltip: 'Settings',
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _BackendCard(online: _backendOnline),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _startScan,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('START NEW SCAN'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Three guided photos. A result is shown only when at least two usable views agree.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Text('Recent scans', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (_recent.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Text('No scans yet. Completed scan metadata will appear here.'),
                  ),
                )
              else
                ..._recent.map(_HistoryTile.new),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackendCard extends StatelessWidget {
  const _BackendCard({required this.online});

  final bool? online;

  @override
  Widget build(BuildContext context) {
    final color = switch (online) {
      true => const Color(0xFF63E6A5),
      false => const Color(0xFFFFB86B),
      null => Colors.blueGrey,
    };
    final label = switch (online) {
      true => 'BACKEND READY',
      false => 'BACKEND OFFLINE',
      null => 'CHECKING BACKEND',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            const Spacer(),
            const Icon(Icons.shield_outlined, size: 20),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.entry);

  final ScanHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final verified = entry.status == 'verified';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            child: Icon(verified ? Icons.check : Icons.refresh),
          ),
          title: Text(verified ? '${entry.trayCount} trays - ${entry.eggCount} eggs' : 'Rescan required'),
          subtitle: Text(
            '${entry.createdAt.toLocal()}  |  ${entry.latencyMs} ms',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(verified ? 'VERIFIED' : 'RETAKE'),
        ),
      ),
    );
  }
}

