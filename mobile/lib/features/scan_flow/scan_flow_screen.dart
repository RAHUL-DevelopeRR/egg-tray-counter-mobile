import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/capture_view.dart';
import '../../models/scan_result.dart';
import '../../models/scan_session.dart';
import '../../services/api_client.dart';
import '../../services/history_database.dart';
import '../../services/settings_store.dart';
import '../capture/guided_capture_pane.dart';

enum _FlowPhase { capture, processing, result }

class ScanFlowScreen extends StatefulWidget {
  const ScanFlowScreen({
    required this.cameras,
    required this.settings,
    required this.history,
    super.key,
  });

  final List<CameraDescription> cameras;
  final SettingsStore settings;
  final HistoryDatabase history;

  @override
  State<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends State<ScanFlowScreen> {
  _FlowPhase _phase = _FlowPhase.capture;
  late ScanSession _session;
  CaptureView? _captureView;
  ScanResult? _result;
  ApiClient? _client;
  double? _uploadProgress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = ScanSession(scanId: const Uuid().v4());
  }

  Future<void> _process(ScanSession session) async {
    setState(() {
      _phase = _FlowPhase.processing;
      _error = null;
      _uploadProgress = 0;
    });
    final baseUrl = await widget.settings.getBaseUrl();
    final client = ApiClient(baseUrl);
    _client = client;
    try {
      final result = await client.countScan(
        session,
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(() => _uploadProgress = total > 0 ? sent / total : null);
        },
      );
      await widget.history.save(result);
      if (result.accepted) {
        await _deleteSessionPhotos();
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _FlowPhase.result;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      final detail = error.response?.data;
      setState(() {
        _error = detail is Map && detail['detail'] is Map
            ? (detail['detail'] as Map)['message']?.toString()
            : error.message ?? 'Network request failed.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  void _retake(String? viewName) {
    final view = CaptureView.values.firstWhere(
      (value) => value.name == viewName,
      orElse: () => CaptureView.left,
    );
    final oldPath = _session.pathFor(view);
    if (oldPath != null) unawaited(_deleteFile(oldPath));
    _session.clear(view);
    setState(() {
      _captureView = view;
      _result = null;
      _phase = _FlowPhase.capture;
    });
  }

  void _newScan() {
    unawaited(_deleteSessionPhotos());
    setState(() {
      _session = ScanSession(scanId: const Uuid().v4());
      _captureView = null;
      _result = null;
      _phase = _FlowPhase.capture;
    });
  }

  @override
  void dispose() {
    _client?.cancel();
    unawaited(_deleteSessionPhotos());
    super.dispose();
  }

  Future<void> _deleteSessionPhotos() async {
    final paths = _session.paths.values.toList(growable: false);
    await Future.wait(paths.map(_deleteFile));
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cache cleanup is best-effort; scan metadata remains valid.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_phase) {
          _FlowPhase.capture => 'Guided capture',
          _FlowPhase.processing => 'Verifying count',
          _FlowPhase.result => 'Scan result',
        }),
        leading: IconButton(
          onPressed: () {
            _client?.cancel();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.close),
        ),
      ),
      body: switch (_phase) {
        _FlowPhase.capture => GuidedCapturePane(
          key: ValueKey('${_session.scanId}-${_captureView?.name ?? 'next'}'),
          cameras: widget.cameras,
          session: _session,
          initialView: _captureView,
          onComplete: _process,
        ),
        _FlowPhase.processing => _ProcessingPane(
          progress: _uploadProgress,
          error: _error,
          onRetry: () => _process(_session),
          onCancel: () {
            _client?.cancel();
            Navigator.pop(context);
          },
        ),
        _FlowPhase.result => _ResultPane(
          result: _result!,
          onRetake: () => _retake(_result!.recommendedView),
          onNewScan: _newScan,
          onDone: () => Navigator.pop(context),
        ),
      },
    );
  }
}

class _ProcessingPane extends StatelessWidget {
  const _ProcessingPane({
    required this.progress,
    required this.error,
    required this.onRetry,
    required this.onCancel,
  });

  final double? progress;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 64),
              const SizedBox(height: 18),
              Text(
                'Scan could not be processed',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onRetry,
                child: const Text('RETRY SAME SCAN'),
              ),
              TextButton(onPressed: onCancel, child: const Text('CANCEL')),
            ],
          ),
        ),
      );
    }
    final uploaded = progress != null && progress! >= 1;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 96,
              child: CircularProgressIndicator(
                value: uploaded ? null : progress,
                strokeWidth: 8,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              uploaded
                  ? 'Analyzing three views...'
                  : 'Uploading original photos...',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              uploaded
                  ? 'Detecting individual trays and comparing matching cell IDs.'
                  : '${((progress ?? 0) * 100).round()}% uploaded',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            TextButton(onPressed: onCancel, child: const Text('CANCEL')),
          ],
        ),
      ),
    );
  }
}

class _ResultPane extends StatelessWidget {
  const _ResultPane({
    required this.result,
    required this.onRetake,
    required this.onNewScan,
    required this.onDone,
  });

  final ScanResult result;
  final VoidCallback onRetake;
  final VoidCallback onNewScan;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      children: [
        Icon(
          result.accepted
              ? Icons.verified_outlined
              : Icons.warning_amber_rounded,
          size: 76,
          color: result.accepted
              ? const Color(0xFF63E6A5)
              : const Color(0xFFFFB86B),
        ),
        const SizedBox(height: 12),
        Text(
          result.accepted ? 'VERIFIED' : 'COUNT NOT VERIFIED',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 22),
        if (result.accepted) ...[
          _MetricRow(label: 'Verified cells', value: '${result.stacks.length}'),
          _MetricRow(
            label: 'Cell IDs',
            value: result.stacks.map((cell) => cell.id).join(', '),
          ),
          _MetricRow(label: 'Total trays', value: '${result.totalTrays}'),
          _MetricRow(label: 'Eggs / tray', value: '${result.eggsPerTray}'),
          const Divider(height: 30),
          Text(
            'TOTAL EGGS',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(
            '${result.totalEggs}',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ] else ...[
          Text(
            result.rescanReason ??
                'The views did not provide enough agreement.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          ...result.views.entries.map(
            (entry) => _MetricRow(
              label: entry.key.toUpperCase(),
              value: entry.value.accepted ? 'CELL AGREES' : 'RECOUNT CELL',
            ),
          ),
          if (result.stacks.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...result.stacks.map(
              (stack) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stack.id,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Left ${stack.counts['left'] ?? '-'}  |  "
                        "Right ${stack.counts['right'] ?? '-'}  |  "
                        "Straight ${stack.counts['straight'] ?? '-'}",
                      ),
                      const SizedBox(height: 6),
                      Text(stack.reason),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _MetricRow(label: 'Model', value: result.modelVersion),
                _MetricRow(
                  label: 'Processing',
                  value: '${result.latencyMs} ms',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (result.accepted)
          FilledButton(onPressed: onNewScan, child: const Text('NEW SCAN'))
        else ...[
          FilledButton.tonal(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Manual recount'),
                content: const Text(
                  'Count the physical trays in each listed cell separately and record the cell ID and count in your inventory log. Do not sum overlapping views or treat these predictions as verified. To retry automation, start a new scan of one entire cell from all three angles.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('UNDERSTOOD'),
                  ),
                ],
              ),
            ),
            child: const Text('MANUAL RECOUNT'),
          ),
          TextButton(
            onPressed: onNewScan,
            child: const Text('NEW SAME-CELL SCAN'),
          ),
          FilledButton(
            onPressed: onRetake,
            child: Text(
              'RETAKE ${(result.recommendedView ?? 'photo').toUpperCase()}',
            ),
          ),
        ],
        TextButton(onPressed: onDone, child: const Text('DONE')),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
