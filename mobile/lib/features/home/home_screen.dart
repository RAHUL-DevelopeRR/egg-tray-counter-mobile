import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../models/scan_session.dart';
import '../../services/api_client.dart';
import '../../services/device_auth.dart';
import '../../services/history_database.dart';
import '../../services/pending_scans.dart';
import '../../services/settings_store.dart';
import '../scan_flow/result_look.dart';
import '../scan_flow/scan_flow_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.settings,
    required this.history,
    required this.pendingScans,
    this.clientFor,
    super.key,
  });

  final SettingsStore settings;
  final HistoryDatabase history;
  final PendingScanStore pendingScans;

  /// Makes the client for a server address (tests: a fake server); the
  /// app's shared connection when null.
  final ApiClient Function(String baseUrl)? clientFor;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ScanHistoryEntry> _recent = const [];
  bool? _backendOnline;
  DeviceState? _device;
  PendingScanRow? _pending;
  bool _startingScan = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// History, the unfinished scan and the server check run side by side: a
  /// slow database must not hold back the status card, nor the reverse.
  Future<void> _refresh() async {
    await Future.wait([_loadHistory(), _loadPending(), _checkServer()]);
  }

  Future<void> _loadHistory() async {
    try {
      final entries = await widget.history.recent();
      if (mounted) setState(() => _recent = entries);
    } on Object {
      // The list stays as it was; scanning does not depend on it.
    }
  }

  Future<void> _loadPending() async {
    try {
      final pending = await widget.pendingScans.latest();
      if (mounted) setState(() => _pending = pending);
      await widget.pendingScans.sweep();
    } on Object {
      // No pending store (tests, or storage unavailable): nothing to resume.
    }
  }

  ApiClient _api(String baseUrl) =>
      widget.clientFor?.call(baseUrl) ?? ApiClient(baseUrl);

  Future<void> _checkServer() async {
    var online = false;
    DeviceState? device;
    try {
      final baseUrl = await widget.settings.getBaseUrl();
      final client = _api(baseUrl);
      online = await client.health();
      // Registers the phone on a server that asks for device credentials.
      if (online) device = await client.checkDevice();
    } on Object {
      online = false;
    }
    if (!mounted) return;
    setState(() {
      _backendOnline = online;
      _device = device;
    });
  }

  /// The server and this phone's approval, checked again at every start:
  /// an approval given a minute ago counts at once. Only a definite answer
  /// (pending, revoked, a refused check) stops a scan; a check that got no
  /// answer does not.
  Future<bool> _readyToScan(ApiClient client) async {
    await client.requireModelScan();
    final device = await client.checkDevice();
    if (!mounted) return false;
    setState(() {
      _backendOnline = true;
      _device = device;
    });
    final reason = device.blockReason;
    if (reason == null) return true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(reason)));
    return false;
  }

  Future<void> _startScan({bool uploadPhotos = false}) async {
    if (_startingScan) return;
    setState(() => _startingScan = true);
    try {
      final url = await widget.settings.getBaseUrl();
      if (!await _readyToScan(_api(url))) return;
      // Keep native camera startup out of the offline pilot and app launch.
      final cameras = uploadPhotos
          ? <CameraDescription>[]
          : await availableCameras();
      if (!mounted) return;
      await _openFlow(cameras: cameras, uploadPhotos: uploadPhotos);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo scan unavailable: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingScan = false);
    }
  }

  /// RESUME: asks the server for the scan's result first and uploads only if
  /// it has none. A result already kept on the phone needs no server: it is
  /// finished offline, whatever the server or the phone's approval says now.
  Future<void> _resume() async {
    final pending = _pending;
    if (pending == null || _startingScan) return;
    setState(() => _startingScan = true);
    try {
      final url = await widget.settings.getBaseUrl();
      final kept = await _hasKeptResult(pending.scanId);
      if (!kept && !await _readyToScan(_api(url))) return;
      final ScanSession session;
      try {
        session = await widget.pendingScans.restore(pending.scanId);
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'The unfinished scan cannot be read ($error). Discard it '
                'and scan the block again.',
              ),
            ),
          );
        }
        return;
      }
      // A retake after a rejection needs the camera; without one the
      // gallery screen still works.
      var cameras = <CameraDescription>[];
      try {
        cameras = await availableCameras();
      } on Object {
        cameras = const [];
      }
      if (!mounted) return;
      await _openFlow(
        cameras: cameras,
        uploadPhotos: cameras.isEmpty,
        resume: session,
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot resume yet: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingScan = false);
    }
  }

  Future<bool> _hasKeptResult(String scanId) async {
    try {
      return await widget.pendingScans.storedResult(scanId) != null;
    } on Object {
      return false;
    }
  }

  Future<void> _discardPending() async {
    final pending = _pending;
    if (pending == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unfinished scan?'),
        content: const Text(
          'Its photos are deleted from this phone. If the server already '
          'counted it, that result is not shown here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('KEEP'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DISCARD'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.pendingScans.remove(pending.scanId);
    } on Object {
      // Shown again on the next refresh if it is still there.
    }
    await _loadPending();
  }

  Future<void> _openFlow({
    required List<CameraDescription> cameras,
    required bool uploadPhotos,
    ScanSession? resume,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ScanFlowScreen(
          cameras: cameras,
          settings: widget.settings,
          history: widget.history,
          pendingScans: widget.pendingScans,
          uploadPhotos: uploadPhotos,
          resume: resume,
          clientFor: widget.clientFor,
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
    final pending = _pending;
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
                          style: textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
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
              _BackendCard(
                online: _backendOnline,
                device: _device,
                onRetry: _refresh,
              ),
              if (pending != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  key: const ValueKey('resume-scan'),
                  onPressed: _startingScan ? null : _resume,
                  icon: const Icon(Icons.restore),
                  label: Text(
                    'RESUME UNFINISHED SCAN (${_clock(pending.createdAt)})',
                  ),
                ),
                TextButton(
                  onPressed: _startingScan ? null : _discardPending,
                  child: const Text('DISCARD UNFINISHED SCAN'),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _startingScan ? null : _startScan,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('SCAN A BLOCK — CAMERA'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _startingScan
                    ? null
                    : () => _startScan(uploadPhotos: true),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('SCAN A BLOCK — GALLERY'),
              ),
              const SizedBox(height: 12),
              const Text(
                'One block at a time: photograph its front face (STRAIGHT), then its LEFT and RIGHT side faces, square-on, phone level at mid-height. Then record your count.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Text(
                'Recent scans',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (_recent.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Text(
                      'No scans yet. Completed scan metadata will appear here.',
                    ),
                  ),
                )
              else
                ..._recent.map(HistoryTile.new),
            ],
          ),
        ),
      ),
    );
  }

  static String _clock(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.day}/${local.month} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _BackendCard extends StatelessWidget {
  const _BackendCard({
    required this.online,
    required this.device,
    required this.onRetry,
  });

  final bool? online;
  final DeviceState? device;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final color = switch (online) {
      true => const Color(0xFF63E6A5),
      false => const Color(0xFFFFB86B),
      null => Colors.blueGrey,
    };
    final label = switch (online) {
      true => 'SERVER REACHABLE',
      false => 'SERVER NOT REACHED — TAP TO RETRY',
      null => 'CHECKING BACKEND',
    };
    final device = online == true && this.device?.authRequired == true
        ? this.device
        : null;
    final deviceColor = switch (device?.status) {
      DeviceStatus.active => const Color(0xFF63E6A5),
      DeviceStatus.revoked => const Color(0xFFFF6B6B),
      _ => const Color(0xFFFFB86B),
    };
    return Card(
      child: InkWell(
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(Icons.shield_outlined, size: 20),
                ],
              ),
              if (device != null) ...[
                const SizedBox(height: 10),
                Text(
                  device.label,
                  key: const ValueKey('device-status'),
                  style: TextStyle(
                    color: deviceColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if ((device.blockReason ?? device.problem) != null) ...[
                  const SizedBox(height: 6),
                  Text(device.blockReason ?? device.problem!),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One history row. Rows saved by apps before 0.4.12 that say "rescan
/// required" with no count are shown as unknown: those apps stored a status
/// that did not describe the scan.
class HistoryTile extends StatelessWidget {
  const HistoryTile(this.entry, {super.key});

  final ScanHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final unknown = entry.recordedByOlderApp;
    final look = unknown ? unknownLook : resultLook(entry.status);
    final count = entry.trayCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(look.icon, color: look.color)),
          title: Text(
            unknown
                ? 'Unknown - recorded by an older app'
                : count != null
                ? '${entry.status == 'estimated' ? 'About ' : ''}$count trays'
                : 'Rescan required',
          ),
          subtitle: Text(
            '${entry.createdAt.toLocal()}  |  ${entry.latencyMs} ms',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(look.label),
        ),
      ),
    );
  }
}
