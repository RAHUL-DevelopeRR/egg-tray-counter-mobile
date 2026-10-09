import 'package:flutter/material.dart';

import '../../services/settings_store.dart';
import '../grid_height/grid_height_screen.dart';
import '../reconstruction/reconstruction_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.store, super.key});

  final SettingsStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.store.getBaseUrl().then((value) {
      if (!mounted) return;
      _controller.text = value;
      setState(() => _loading = false);
    });
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

