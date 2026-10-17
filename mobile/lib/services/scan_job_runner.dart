import 'dart:async';

import '../app/app_version.dart';
import '../models/scan_result.dart';
import '../models/scan_session.dart';
import 'api_client.dart';
import 'history_database.dart';
import 'pending_scans.dart';
import 'scan_failure.dart';

/// One scan from submitted photos to a history row: keeps the scan on disk
/// until its result is saved, sends it, keeps the answer before reading it,
/// and records why it failed. Throws [ScanFailure].
class ScanJobRunner {
  ScanJobRunner({
    required this.api,
    required this.pending,
    required this.history,
    this.appVersion = kAppVersion,
  });

  final ApiClient api;
  final PendingScanStore pending;
  final HistoryDatabase history;
  final String appVersion;

  /// [resume] (an unfinished scan from an earlier launch, or KEEP WAITING)
  /// asks the server for the result before uploading: a scan whose photos
  /// were sent in full is waited for, one whose photos never finished
  /// sending is asked once and then uploaded. [forceUpload] sends the photos
  /// again even after they were sent once (a `scan_jobs_v1` server returns
  /// its stored result rather than counting twice).
  Future<ScanResult> run(
    ScanSession session, {
    required void Function(int sent, int total) onProgress,
    void Function(ScanStage stage)? onStage,
    bool resume = false,
    bool forceUpload = false,
  }) async {
    final scanId = session.scanId;
    final PendingScanRow record;
    try {
      record = await pending.find(scanId) ?? await pending.create(session);
    } on Object catch (error) {
      throw ScanFailure(
        ScanFailureKind.appError,
        'The phone could not keep a copy of this scan ($error). Nothing was '
        'sent. Free some storage and tap TRY AGAIN.',
      );
    }
    // A result that arrived earlier but was not saved: finish it here,
    // without uploading again. One that does not fit this scan is dropped
    // and the server is asked again.
    final stored = await _quietly(() => pending.storedResult(scanId));
    if (stored != null) {
      if (_fits(stored, session)) return _finish(session, stored);
      await _quietly(() => pending.clearResult(scanId));
    }

    await _quietly(() => pending.recordAttempt(scanId));
    final Map<String, dynamic> body;
    try {
      body = await api.submitScan(
        session,
        onProgress: onProgress,
        onStage: onStage,
        askResultFirst: !forceUpload && (resume || record.bodySent),
        bodySentBefore: record.bodySent,
        onBodySent: () => unawaited(
          _quietly(() => pending.markBodySent(scanId)),
        ),
      );
      // Checked before it is kept: a kept answer is replayed by every later
      // try, so a wrong one would never let the server be asked again.
      checkScanResponse(body, session);
    } on ScanFailure catch (failure) {
      if (failure.kind == ScanFailureKind.rejected) {
        // Retrying can never succeed, so there is nothing to resume. The
        // screen keeps its own photos for a retake under a new scan id.
        await _quietly(() => pending.remove(scanId));
      } else {
        await _quietly(() => pending.markFailed(scanId, failure.errorClass));
      }
      rethrow;
    }
    await _quietly(() => pending.storeResult(scanId, body));
    return _finish(session, body);
  }

  static bool _fits(Map<String, dynamic> body, ScanSession session) {
    try {
      checkScanResponse(body, session);
      return true;
    } on ScanFailure {
      return false;
    }
  }

  /// Reads and saves an answer already checked against [session].
  Future<ScanResult> _finish(
    ScanSession session,
    Map<String, dynamic> body,
  ) async {
    final scanId = session.scanId;
    final ScanResult result;
    try {
      result = ScanResult.fromJson(body);
    } on Object catch (error) {
      await _quietly(() => pending.markFailed(scanId, 'app_error'));
      throw ScanFailure(
        ScanFailureKind.appError,
        'The result arrived but this app could not read it ($error). The '
        'photos are not sent again; tap TRY AGAIN or update the app.',
      );
    }
    try {
      await history.save(result, appVersion: appVersion);
    } on Object catch (error) {
      await _quietly(() => pending.markFailed(scanId, 'app_error'));
      throw ScanFailure(
        ScanFailureKind.appError,
        'The result arrived but could not be saved on this phone ($error). '
        'The photos are not sent again; tap TRY AGAIN.',
      );
    }
    // Only now is the scan safe to forget.
    await _quietly(() => pending.remove(scanId));
    return result;
  }

  /// A result is used only for the scan that asked for it, and only from a
  /// server that ran the requested analysis.
  static void checkScanResponse(
    Map<String, dynamic> data,
    ScanSession session,
  ) {
    if (data['scan_id'] != session.scanId) {
      throw ScanFailure(
        ScanFailureKind.appError,
        'The server answered for a different scan (${data['scan_id']}), not '
        'this one (${session.scanId}). Nothing was saved; tap TRY AGAIN to '
        'ask the server again.',
      );
    }
    if (data['processing'] is! Map ||
        data['processing']['mode'] != 'model_spatial_v1' ||
        data['cell_ids'] is! Map ||
        session.cellIds.entries.any(
          (entry) => data['cell_ids'][entry.key] != entry.value,
        )) {
      throw const ScanFailure(
        ScanFailureKind.appError,
        'The server returned an incompatible scan result. Nothing was saved; '
        'tap TRY AGAIN to ask the server again. If it repeats, the backend '
        'needs an update.',
      );
    }
  }

  /// Bookkeeping on the phone must not turn a good scan into a failed one.
  static Future<T?> _quietly<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object {
      return null;
    }
  }
}
