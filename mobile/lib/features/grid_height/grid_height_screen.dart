import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/height_calibration.dart';
import '../../models/scan_session.dart';
import '../../services/settings_store.dart';

class GridHeightScreen extends StatefulWidget {
  const GridHeightScreen({required this.store, super.key});
  final SettingsStore store;

  @override
  State<GridHeightScreen> createState() => _GridHeightScreenState();
}

class _GridHeightScreenState extends State<GridHeightScreen> {
  final _fields = {
    for (final key in [
      'profile',
      'h1',
      'h5',
      'h10',
      'maxCount',
      'hMax',
      'error',
      'cell',
      'height',
      'physical',
    ])
      key: TextEditingController(),
  };
  HeightCalibration? _calibration;
  HeightEstimate? _estimate;
  List<Map<String, dynamic>> _records = [];
  String _session = DateTime.now().toUtc().toIso8601String();
  bool _loading = true, _busy = false, _dirty = false, _layoutChecked = false;
  String? _loadError;

  Map<String, Map<String, dynamic>> get _latest => {
    for (final row in _records.where((row) => row['session_id'] == _session))
      row['cell_id'] as String: row,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.store.getHeightPilot();
      if (!mounted) return;
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['schema'] != 1) {
          throw const FormatException('Unknown pilot log version.');
        }
        _session = data['session_id'] as String;
        DateTime.parse(_session);
        _records = (data['records'] as List).map((row) {
          final record = Map<String, dynamic>.from(row as Map);
          ScanSession.normalizeCellId(record['cell_id'] as String);
          DateTime.parse(record['session_id'] as String);
          DateTime.parse(record['recorded_at'] as String);
          final count = record['physical_count'];
          final height = record['height_cm'];
          if (count is! int ||
              count < 0 ||
              count > 1000 ||
              height is! num ||
              !height.isFinite ||
              height <= 0 ||
              record['source'] != 'operator_recount') {
            throw const FormatException('Invalid pilot measurement.');
          }
          HeightCalibration.fromJson(
            Map<String, dynamic>.from(record['calibration'] as Map),
          );
          return record;
        }).toList();
        if (data['calibration'] != null) {
          _calibration = HeightCalibration.fromJson(
            data['calibration'] as Map<String, dynamic>,
          );
          final c = _calibration!;
          _fields['profile']!.text = c.profile;
          for (final n in [1, 5, 10]) {
            _fields['h$n']!.text = '${c.heights[n]}';
          }
          _fields['maxCount']!.text = '${c.maxCount}';
          _fields['hMax']!.text = '${c.heights[c.maxCount]}';
          _fields['error']!.text = '${c.errorCm}';
        }
      }
      setState(() {
        _loading = false;
        _loadError = null;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError =
              'Cannot read the saved pilot log. It has NOT been overwritten. $e';
        });
      }
    }
  }

  Map<String, Object?> _data({
    HeightCalibration? calibration,
    List<Map<String, dynamic>>? records,
    String? session,
  }) => {
    'schema': 1,
    'mode': 'measurement_assisted_pilot_not_auto_verified',
    'target': 'egg_filled_trays_only',
    'session_id': session ?? _session,
    'calibration': (calibration ?? _calibration)?.toJson(),
    'records': records ?? _records,
  };

  Future<void> _persist({
    HeightCalibration? calibration,
    List<Map<String, dynamic>>? records,
    String? session,
  }) => widget.store.setHeightPilot(
    jsonEncode(
      _data(calibration: calibration, records: records, session: session),
    ),
  );

  void _message(Object text) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$text')));
  }

  double _number(String key) {
    final value = double.tryParse(_fields[key]!.text.trim());
    if (value == null || !value.isFinite || value <= 0) {
      throw const FormatException(
        'Complete every required measurement with a positive number in cm (use a decimal point).',
      );
    }
    return value;
  }

  Future<void> _saveCalibration() async {
    setState(() => _busy = true);
    try {
      final n = int.tryParse(_fields['maxCount']!.text.trim());
      if (n == null || n < 11 || n > 200) {
        throw const FormatException(
          'The larger reference must contain 11–200 manually counted trays.',
        );
      }
      final calibration = HeightCalibration(
        profile: _fields['profile']!.text.trim(),
        heights: {
          1: _number('h1'),
          5: _number('h5'),
          10: _number('h10'),
          n: _number('hMax'),
        },
        errorCm: _number('error'),
      );
      await _persist(calibration: calibration);
      if (!mounted) return;
      setState(() {
        _calibration = calibration;
        _dirty = false;
        _estimate = null;
      });
      _message('Calibration saved locally. It is not yet field-validated.');
    } on Object catch (e) {
      _message(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _calculate() {
    try {
      if (_calibration == null || _dirty || !_layoutChecked) {
        throw const FormatException(
          'Save your calibration and confirm the physical setup first.',
        );
      }
      ScanSession.normalizeCellId(_fields['cell']!.text);
      final result = _calibration!.estimate(_number('height'));
      setState(() {
        _estimate = result;
        _fields['physical']!.clear();
      });
    } on Object catch (e) {
      _message(e);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CONFIRM'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _saveRecount() async {
    if (_busy || _estimate == null || _dirty || !_layoutChecked) return;
    setState(() => _busy = true);
    try {
      final count = int.tryParse(_fields['physical']!.text.trim());
      if (count == null || count < 0 || count > 1000) {
        throw const FormatException(
          'Enter your physically recounted whole-number tray count (0–1000). Do not copy the estimate without counting.',
        );
      }
      final cell = ScanSession.normalizeCellId(_fields['cell']!.text);
      if (_latest.containsKey(cell) &&
          !await _confirm(
            'Update cell $cell?',
            'This replaces the cell’s current tally, not adds another view. The previous observation stays in the exported log.',
          )) {
        return;
      }
      if (!mounted) return;
      final records = [
        ..._records,
        <String, dynamic>{
          'session_id': _session,
          'cell_id': cell,
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
          'height_cm': _number('height'),
          'calibration': _calibration!.toJson(),
          'candidate_counts': _estimate!.candidates,
          'estimated_count': _estimate!.count,
          'physical_count': count,
          'source': 'operator_recount',
          'auto_verified': false,
        },
      ];
      await _persist(records: records);
      if (!mounted) return;
      setState(() {
        _records = records;
        _estimate = null;
        _layoutChecked = false;
        for (final key in ['cell', 'height', 'physical']) {
          _fields[key]!.clear();
        }
      });
      _message('Physical recount saved for $cell. No automatic acceptance.');
    } on Object catch (e) {
      _message('Not saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newTally() async {
    if (!await _confirm(
      'Start a new tally?',
      'The current cell list starts empty. All previous observations remain in the exported pilot log.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final session = DateTime.now().toUtc().toIso8601String();
      await _persist(session: session);
      if (mounted) {
        setState(() {
          _session = session;
          _estimate = null;
          _layoutChecked = false;
          for (final key in ['cell', 'height', 'physical']) {
            _fields[key]!.clear();
          }
        });
      }
    } on Object catch (e) {
      _message('New tally not saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyReport() async {
    try {
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(_data()),
        ),
      );
      _message(
        'Pilot JSON copied, including calibration, estimates and physical counts. Paste it into a file to back it up.',
      );
    } on Object catch (e) {
      _message('Could not copy report: $e');
    }
  }

  Widget _field(
    String key,
    String label, {
    bool calibration = false,
    bool text = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: ValueKey(key),
      controller: _fields[key],
      enabled: !_busy,
      maxLength: text ? (key == 'cell' ? 32 : 64) : 12,
      keyboardType: text
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      onChanged: (_) {
        if (key == 'physical') return;
        setState(() {
          _estimate = null;
          _fields['physical']!.clear();
          if (calibration) _dirty = true;
        });
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final latest = _latest;
    final total = latest.values.fold<int>(
      0,
      (sum, row) => sum + (row['physical_count'] as int),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Grid + height pilot')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(_loadError!),
                  TextButton(onPressed: _load, child: const Text('RETRY')),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'OFFLINE · MEASUREMENT-ASSISTED',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter ruler measurements, not photo pixels. This pilot does not read floor markers or height from a camera. Every result needs a physical recount; accuracy is not yet validated.',
                ),
                const SizedBox(height: 16),
                const ExpansionTile(
                  title: Text('1. Set up one floor cell'),
                  children: [
                    Image(
                      image: AssetImage('assets/floor-cells-wall-reference.png'),
                      semanticLabel:
                          'Concept: painted boxes only on the floor, egg-filled stacks, and tray-count reference levels on the wall. Not measured data.',
                    ),
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'One upright column per numbered cell (use A1-1, A1-2 for separate columns). Count only egg-filled trays of the same type. Measure from the support surface to the top TRAY RIM, excluding egg tips and pallet height.\n\n'
                        'Paint boxes on the FLOOR before placing stacks; hidden floor boundaries stay hidden. Height reference marks go on the WALL, calibrated with physically counted loaded stacks. Wall marks at a different depth cannot be compared directly to stack tops in a photo: perspective calibration is required. Floor scale alone cannot measure vertical height.\n\n'
                        'The image is a concept, not measurement or training data. Example cell C1 contains multiple columns: record C1-1 and C1-2 separately. The wall labels are illustrative, not calibrated heights. This APK still requires ruler input and physical recount; it does not detect these markings.',
                      ),
                    ),
                  ],
                ),
                ExpansionTile(
                  key: const ValueKey('calibrationSection'),
                  initiallyExpanded: _calibration == null,
                  title: const Text('2. Calibrate real loaded trays'),
                  subtitle: Text(
                    _dirty
                        ? 'Unsaved changes — counting paused'
                        : _calibration == null
                        ? 'Required — no invented defaults'
                        : '${_calibration!.profile} · up to ${_calibration!.maxCount} trays',
                  ),
                  children: [
                    const Text(
                      'Use manually counted 1-, 5-, 10-tray and full-height reference stacks. Recalibrate after a tray, support or loading change. Uncertainty is ± cm on EACH height, including repeat-measurement and load variation. Do not shrink it to force a unique answer.',
                    ),
                    _field(
                      'profile',
                      'Tray type / calibration profile',
                      calibration: true,
                      text: true,
                    ),
                    for (final n in [1, 5, 10])
                      _field(
                        'h$n',
                        '$n-tray reference height (cm)',
                        calibration: true,
                      ),
                    _field(
                      'maxCount',
                      'Full-height reference: known tray count (11–200)',
                      calibration: true,
                    ),
                    _field(
                      'hMax',
                      'Full-height reference height (cm)',
                      calibration: true,
                    ),
                    _field(
                      'error',
                      'Height uncertainty ± (cm)',
                      calibration: true,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _saveCalibration,
                      child: const Text('SAVE CALIBRATION'),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '3. Measure one cell',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                _field(
                  'cell',
                  'Painted cell / column ID (e.g. A1)',
                  text: true,
                ),
                _field('height', 'Measured stack height (cm)'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _layoutChecked,
                  title: const Text(
                    'One upright column; egg-filled trays only; same tray type and support as calibration.',
                  ),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _layoutChecked = value ?? false;
                          _estimate = null;
                        }),
                ),
                FilledButton.icon(
                  key: const ValueKey('checkHeight'),
                  onPressed:
                      _busy || _calibration == null || _dirty || !_layoutChecked
                      ? null
                      : _calculate,
                  icon: const Icon(Icons.straighten),
                  label: const Text('CHECK HEIGHT'),
                ),
                if (_estimate != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _estimate!.count == null
                        ? 'MANUAL RECOUNT REQUIRED'
                        : 'Candidate: ${_estimate!.count} trays',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(_estimate!.reason),
                  if (_estimate!.candidates.length > 1)
                    Text(
                      'Possible counts: ${_estimate!.candidates.join(', ')}',
                    ),
                  _field(
                    'physical',
                    'Actual count after physically recounting',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _saveRecount,
                    child: const Text('SAVE PHYSICAL RECOUNT'),
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  '4. Recorded cells: $total trays',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Operator-counted total for ${latest.length} cells in this tally only. Not an AI-verified warehouse total. No egg total is inferred from tray capacity.',
                ),
                Text('Tally started: ${DateTime.parse(_session).toLocal()}'),
                for (final row in latest.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.grid_view),
                    title: Text(
                      '${row['cell_id']}: ${row['physical_count']} trays',
                    ),
                    subtitle: Text(
                      'Operator recount · height ${row['height_cm']} cm\nHeight candidate: ${row['estimated_count'] ?? 'recount required'}',
                    ),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _copyReport,
                  icon: const Icon(Icons.copy),
                  label: const Text('COPY PILOT REPORT'),
                ),
                TextButton(
                  onPressed: _busy ? null : _newTally,
                  child: const Text('START NEW TALLY'),
                ),
                const Text(
                  'Stored only on this phone. Copy the report before uninstalling or clearing app data. Previous tallies remain in the report; revisiting a cell never adds a second view to its total.',
                ),
              ],
            ),
    );
  }
}
