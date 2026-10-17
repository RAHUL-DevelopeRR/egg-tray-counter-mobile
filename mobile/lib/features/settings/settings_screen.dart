import 'package:flutter/material.dart';

import '../../services/device_auth.dart';
import '../../services/settings_store.dart';
import '../grid_height/grid_height_screen.dart';
import '../reconstruction/reconstruction_screen.dart';
import 'network_test_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.store, this.deviceAuth, super.key});

  final SettingsStore store;

  /// The phone's credential; [DeviceAuth.shared] by default.
  final DeviceAuth? deviceAuth;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  String _deviceLine = 'This phone: reading device code...';

  DeviceAuth get _auth => widget.deviceAuth ?? DeviceAuth.shared;

  @override
  void initState() {
    super.initState();
    widget.store.getBaseUrl().then((value) {
      if (!mounted) return;
      _controller.text = value;
      setState(() => _loading = false);
      _loadDevice(value);
    });
  }

  /// The code the admin approves; never the secret. The launch creates the
  /// credential; this screen only shows it.
  Future<void> _loadDevice(String baseUrl) async {
    final identity = await _auth.loadedIdentity();
    var line = identity == null
        ? 'This phone: device code not available (secure storage not ready)'
        : 'This phone: device ${identity.displayCode}';
    final state = _auth.stateFor(Uri.parse(baseUrl));
    if (identity != null && state != null && state.authRequired) {
      line += '  |  ${state.label}';
    }
    if (mounted) setState(() => _deviceLine = line);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uri = Uri.tryParse(_controller.text.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a full URL such as http://10.0.2.2:8000')),
      );
      return;
    }
    await widget.store.setBaseUrl(_controller.text);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Backend', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Android emulator uses 10.0.2.2 for the Windows host. '
                  'A physical phone must use the computer LAN address.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Backend base URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _save, child: const Text('SAVE SETTINGS')),
                const SizedBox(height: 16),
                Text(
                  _deviceLine,
                  key: const ValueKey('device-code'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 28),
                Text(
                  'Diagnostics (not part of block counting)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => GridHeightScreen(store: widget.store),
                    ),
                  ),
                  icon: const Icon(Icons.grid_view),
                  label: const Text('GRID + HEIGHT PILOT'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ReconstructionScreen(settings: widget.store),
                    ),
                  ),
                  icon: const Icon(Icons.view_in_ar),
                  label: const Text('3D POINT CLOUD (EXPERIMENTAL)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => NetworkTestScreen(
                        settings: widget.store,
                        deviceAuth: _auth,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.network_check),
                  label: const Text('NETWORK TEST'),
                ),
                const SizedBox(height: 28),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Roboflow and Supabase service credentials belong only in the backend .env. '
                            'This app never stores them.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

