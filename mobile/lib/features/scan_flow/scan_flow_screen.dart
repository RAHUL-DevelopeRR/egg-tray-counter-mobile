import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/capture_view.dart';
import '../../models/scan_result.dart';
import '../../models/scan_session.dart';
import '../../services/api_client.dart';
import '../../services/device_auth.dart';
import '../../services/history_database.dart';
import '../../services/pending_scans.dart';
import '../../services/scan_failure.dart';
import '../../services/scan_job_runner.dart';
import '../../services/settings_store.dart';
import '../capture/guided_capture_pane.dart';
import '../capture/photo_upload_pane.dart';
import '../../services/manual_count_store.dart';
import 'block_view.dart';
import 'result_look.dart';
import 'manual_count_screen.dart';

enum _FlowPhase { capture, processing, result }

class ScanFlowScreen extends StatefulWidget {
  const ScanFlowScreen({
    required this.cameras,
    required this.settings,
    required this.history,
    required this.pendingScans,
    this.uploadPhotos = false,
    this.resume,
    this.clientFor,
    super.key,
  });

  final List<CameraDescription> cameras;
  final SettingsStore settings;
  final HistoryDatabase history;
  final PendingScanStore pendingScans;
  final bool uploadPhotos;

  /// An unfinished scan from an earlier launch: asked for its result first,
  /// uploaded again only if the server has none.
  final ScanSession? resume;

  /// Makes the client for a server address (tests: a fake server); the
  /// app's shared connection when null.
  final ApiClient Function(String baseUrl)? clientFor;

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
  ScanStage _stage = ScanStage.uploading;
  ScanFailure? _failure;
  DeviceState? _device;
  bool _running = false;
  final ManualCountRepository _manualCounts = SqliteManualCountRepository();

  @override
  void initState() {
    super.initState();
    final resumed = widget.resume;
    _session = resumed ?? ScanSession(scanId: const Uuid().v4());
    if (resumed != null) {
      _phase = _FlowPhase.processing;
      _stage = ScanStage.connecting;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _process(resumed, resume: true);
      });
    }
  }

  Future<void> _process(
    ScanSession session, {
    bool resume = false,
    bool forceUpload = false,
  }) async {
    // One upload at a time: a double tap used to start two.
    if (_running) return;
    _running = true;
    setState(() {
      _phase = _FlowPhase.processing;
      _failure = null;
      _uploadProgress = 0;
      _stage = resume ? ScanStage.connecting : ScanStage.uploading;
    });
    try {
      final baseUrl = await widget.settings.getBaseUrl();
      if (!mounted) return;
      final client = _api(baseUrl);
      _client = client;
      final result = await ScanJobRunner(
        api: client,
        pending: widget.pendingScans,
        history: widget.history,
      ).run(
        session,
        resume: resume,
        forceUpload: forceUpload,
        onProgress: (sent, total) {
          if (!mounted) return;
          setState(() => _uploadProgress = total > 0 ? sent / total : null);
        },
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (result.accepted) {
        await _deleteSessionPhotos();
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _FlowPhase.result;
      });
    } on ScanFailure catch (failure) {
      if (!mounted || failure.kind == ScanFailureKind.cancelled) return;
      setState(() => _failure = failure);
      if (failure.kind == ScanFailureKind.notAuthorised) {
        unawaited(_checkDevice());
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _failure = ScanFailure(ScanFailureKind.appError, '$error'),
      );
    } finally {
      _running = false;
    }
  }

  ApiClient _api(String baseUrl) =>
      widget.clientFor?.call(baseUrl) ?? ApiClient(baseUrl);

  /// Reads this phone's approval for the NOT AUTHORISED pane.
  Future<DeviceState> _checkDevice() async {
    final baseUrl = await widget.settings.getBaseUrl();
    final state = await _api(baseUrl).checkDevice();
    if (mounted) setState(() => _device = state);
    return state;
  }

  /// CHECK APPROVAL: continues the same scan once the phone is approved.
  Future<void> _checkApproval() async {
    final state = await _checkDevice();
    if (!mounted) return;
    if (state.mayScan) {
      await _process(_session, resume: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.blockReason ?? state.problem ?? state.label),
        ),
      );
    }
  }

  void _retake(CaptureView view) {
    final previous = _session;
    final oldPath = previous.pathFor(view);
    if (oldPath != null) unawaited(_deleteFile(oldPath));
    setState(() {
      // A retake is a new triplet, so a new scan id; the other two photos
      // carry over.
      _session = previous.retake(view, scanId: const Uuid().v4());
      _captureView = view;
      _result = null;
      _failure = null;
      _phase = _FlowPhase.capture;
    });
    unawaited(_forget(previous.scanId));
  }

  void _newScan() {
    final previous = _session.scanId;
    unawaited(_deleteSessionPhotos());
    setState(() {
      _session = ScanSession(scanId: const Uuid().v4());
      _captureView = null;
      _result = null;
      _failure = null;
      _phase = _FlowPhase.capture;
    });
    unawaited(_forget(previous));
  }

  /// The operator moved on from a scan id: nothing more is sent under it.
  /// A scan whose result was saved is already gone from the pending list.
  Future<void> _forget(String scanId) async {
    try {
      await widget.pendingScans.remove(scanId);
    } on Object {
      // Best effort; the home screen offers to discard what is left.
    }
  }

  @override
  void dispose() {
    // Leaving mid-upload keeps the pending copy; the home screen offers
    // RESUME. Only this screen's own photo files are removed.
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

  CaptureView _viewNamed(String? name) => CaptureView.values.firstWhere(
    (value) => value.name == name,
    orElse: () => CaptureView.left,
  );

  @override
  Widget build(BuildContext context) {
    final cameraUp = _phase == _FlowPhase.capture && !widget.uploadPhotos;
    return Scaffold(
      backgroundColor: cameraUp ? Colors.black : null,
      appBar: cameraUp
          ? null
          : AppBar(
              title: Text(switch (_phase) {
                _FlowPhase.capture =>
                  widget.uploadPhotos ? 'Upload photos' : 'Guided capture',
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
        _FlowPhase.capture =>
          widget.uploadPhotos
              ? PhotoUploadPane(
                  key: ValueKey(_session.scanId),
                  session: _session,
                  onComplete: _process,
                )
              : GuidedCapturePane(
                  key: ValueKey(
                    '${_session.scanId}-${_captureView?.name ?? 'next'}',
                  ),
                  cameras: widget.cameras,
                  session: _session,
                  initialView: _captureView,
                  settings: widget.settings,
                  onComplete: _process,
                  onClose: () {
                    _client?.cancel();
                    Navigator.pop(context);
                  },
                ),
        _FlowPhase.processing =>
          _failure != null
              ? ScanFailurePane(
                  failure: _failure!,
                  device: _device,
                  displayCode: DeviceAuth.shared.cachedIdentity?.displayCode,
                  onRetry: () => _process(_session),
                  onKeepWaiting: () => _process(_session, resume: true),
                  onSendAgain: () => _process(_session, forceUpload: true),
                  onCheckApproval: _checkApproval,
                  onRetake: _retake,
                  onNewScan: _newScan,
                  onClose: () => Navigator.pop(context),
                )
              : _ProcessingPane(
                  progress: _uploadProgress,
                  stage: _stage,
                  onCancel: () {
                    _client?.cancel();
                    Navigator.pop(context);
                  },
                ),
        _FlowPhase.result => _ResultPane(
          result: _result!,
          onRetake: () => _retake(_viewNamed(_result!.recommendedView)),
          onNewScan: _newScan,
          onDone: () => Navigator.pop(context),
          onManualCount: () async {
            final result = _result!;
            // A manual count is ground truth: it must belong to this scan.
            if (result.scanId != _session.scanId) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'This result belongs to another scan; take a new scan '
                    'to record a manual count.',
                  ),
                ),
              );
              return;
            }
            final baseUrl = await widget.settings.getBaseUrl();
            if (!context.mounted) return;
            final done = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => ManualCountScreen(
                  result: result,
                  repository: _manualCounts,
                  baseUrl: baseUrl,
                  client: widget.clientFor?.call(baseUrl),
                ),
              ),
            );
            // The operator finished this block: go straight to the next one.
            if (done == true && mounted) _newScan();
          },
        ),
      },
    );
  }
}

class _ProcessingPane extends StatelessWidget {
  const _ProcessingPane({
    required this.progress,
    required this.stage,
    required this.onCancel,
  });

  final double? progress;
  final ScanStage stage;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final uploaded = progress != null && progress! >= 1;
    final (headline, detail) = switch (stage) {
      ScanStage.connecting => (
        'Contacting the server...',
        'Checking the server before anything is sent.',
      ),
      // Said only to a server that stores results; the photos may or may not
      // have arrived, so nothing here claims they did.
      ScanStage.checking => (
        'Asking for the result...',
        "Asking the server whether it already has this scan's result.",
      ),
      ScanStage.waiting => (
        'The server is still counting...',
        'Waiting for the result of this scan.',
      ),
      ScanStage.uploading when uploaded => (
        'Analyzing three views...',
        'Analyzing tray evidence from the three photographs.',
      ),
      ScanStage.uploading => (
        'Uploading original photos...',
        '${((progress ?? 0) * 100).round()}% uploaded',
      ),
    };
    final determinate = stage == ScanStage.uploading && !uploaded;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 96,
              child: CircularProgressIndicator(
                value: determinate ? progress : null,
                strokeWidth: 8,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(detail, textAlign: TextAlign.center),
            const SizedBox(height: 30),
            TextButton(onPressed: onCancel, child: const Text('CANCEL')),
          ],
        ),
      ),
    );
  }
}

/// One failure class, in the operator's words, with only the actions that
/// can work for it: RETRY where retrying can succeed, RETAKE or NEW SCAN for
/// a rejected scan, CHECK APPROVAL for an unapproved phone, and KEEP WAITING
/// only where the server keeps the result.
class ScanFailurePane extends StatelessWidget {
  const ScanFailurePane({
    super.key,
    required this.failure,
    required this.device,
    required this.displayCode,
    required this.onRetry,
    required this.onKeepWaiting,
    required this.onSendAgain,
    required this.onCheckApproval,
    required this.onRetake,
    required this.onNewScan,
    required this.onClose,
  });

  final ScanFailure failure;
  final DeviceState? device;
  final String? displayCode;
  final VoidCallback onRetry;
  final VoidCallback onKeepWaiting;
  final VoidCallback onSendAgain;
  final VoidCallback onCheckApproval;
  final ValueChanged<CaptureView> onRetake;
  final VoidCallback onNewScan;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final icon = switch (failure.kind) {
      ScanFailureKind.uploadFailed => Icons.cloud_off_outlined,
      ScanFailureKind.resultLost => Icons.hourglass_bottom,
      ScanFailureKind.processingFailed => Icons.error_outline,
      ScanFailureKind.rejected => Icons.block,
      ScanFailureKind.notAuthorised => Icons.lock_outline,
      _ => Icons.report_problem_outlined,
    };
    final code = device?.displayCode ?? displayCode;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 24),
        Icon(icon, size: 64),
        const SizedBox(height: 18),
        Text(
          failure.title.toUpperCase(),
          key: const ValueKey('failure-title'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(failure.message, textAlign: TextAlign.center),
        if (failure.kind == ScanFailureKind.notAuthorised) ...[
          const SizedBox(height: 14),
          Text(
            [
              'Device ${code ?? '(code unknown)'}',
              if (device != null && device!.authRequired) device!.label,
            ].join('  |  '),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
        const SizedBox(height: 24),
        ...switch (failure.kind) {
          ScanFailureKind.uploadFailed => [
            FilledButton(onPressed: onRetry, child: const Text('RETRY UPLOAD')),
          ],
          ScanFailureKind.resultLost when !failure.serverKeepsResult => [
            // Nothing to ask for: the only way on is another upload, which
            // this server counts again (the message says so).
            FilledButton(
              onPressed: onSendAgain,
              child: const Text('SEND PHOTOS AGAIN'),
            ),
          ],
          ScanFailureKind.resultLost => [
            FilledButton(
              onPressed: onKeepWaiting,
              child: const Text('KEEP WAITING'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onSendAgain,
              child: const Text('SEND PHOTOS AGAIN'),
            ),
          ],
          ScanFailureKind.processingFailed => [
            FilledButton(onPressed: onRetry, child: const Text('RETRY')),
          ],
          ScanFailureKind.appError => [
            FilledButton(onPressed: onRetry, child: const Text('TRY AGAIN')),
          ],
          ScanFailureKind.notAuthorised => [
            FilledButton(
              onPressed: onCheckApproval,
              child: const Text('CHECK APPROVAL'),
            ),
          ],
          ScanFailureKind.rejected => [
            FilledButton(onPressed: onNewScan, child: const Text('NEW SCAN')),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final view in CaptureView.values)
                  OutlinedButton(
                    onPressed: () => onRetake(view),
                    child: Text('RETAKE ${view.name.toUpperCase()}'),
                  ),
              ],
            ),
          ],
          ScanFailureKind.cancelled => const <Widget>[],
        },
        const SizedBox(height: 8),
        TextButton(
          onPressed: onClose,
          child: Text(
            failure.kind == ScanFailureKind.rejected
                ? 'CLOSE'
                : 'CLOSE - RESUME LATER FROM HOME',
          ),
        ),
      ],
    );
  }
}

class _ResultPane extends StatelessWidget {
  const _ResultPane({
    required this.result,
    required this.onRetake,
    required this.onNewScan,
    required this.onDone,
    required this.onManualCount,
  });

  final ScanResult result;
  final VoidCallback onRetake;
  final VoidCallback onNewScan;
  final VoidCallback onDone;
  final VoidCallback onManualCount;

  @override
  Widget build(BuildContext context) {
    // One result state drives the icon, the headline and the saved history.
    final look = resultLook(result.resultStatus);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      children: [
        Icon(look.icon, size: 76, color: look.color),
        const SizedBox(height: 12),
        Text(
          look.headline,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 22),
        if (result.block != null) ...[
          BlockPanel(block: result.block!),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('manual-count-button'),
            onPressed: onManualCount,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('RECORD MANUAL COUNT'),
          ),
          const SizedBox(height: 18),
        ],
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
          // With a computed block total the block panel is the result; the
          // legacy per-photo evidence rows would contradict it on screen.
          if (result.block?.totalTrays == null) ...[
            Text(
              result.rescanReason ??
                  'The photographs did not resolve the physical tray count.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            ...result.views.entries.map(
              (entry) => _MetricRow(
                label: entry.key.toUpperCase(),
                value: entry.value.accepted ? 'VERIFIED' : 'REVIEW EVIDENCE',
              ),
            ),
          ],
          if (result.block?.totalTrays == null && result.stacks.isNotEmpty) ...[
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
          if (result.block?.totalTrays == null)
            FilledButton.tonal(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Manual recount'),
                  content: const Text(
                    'Count each physical stack once and record its tray count in your inventory log. Do not sum overlapping photographs. To retry, capture the same complete group of stacks from left, right and straight. Floor IDs are optional.',
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
          TextButton(onPressed: onNewScan, child: const Text('NEW SCAN')),
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
