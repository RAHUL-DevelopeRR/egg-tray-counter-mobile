/// Why a scan did not produce a saved result. The classes follow
/// docs/SCAN_JOBS_AND_DEVICES.md; each decides what the operator may do next.
enum ScanFailureKind {
  /// No full request reached the server, or the server was too busy to take
  /// it (408, 425, 429). Photos kept; upload again.
  uploadFailed,

  /// The photos were sent but no answer came back. Ask for the result
  /// (only a `scan_jobs_v1` server keeps one: see
  /// [ScanFailure.serverKeepsResult]).
  resultLost,

  /// The server received the photos and failed (5xx, 409 scan_failed), or
  /// gave an answer this app does not expect. Photos kept; retry.
  processingFailed,

  /// A 4xx that retrying cannot fix (400, 413, 415, 422, 409
  /// scan_id_conflict, 403 scan_forbidden).
  rejected,

  /// 401/403 device errors: wait for approval.
  notAuthorised,

  /// The result arrived but this phone could not read or save it. Never
  /// uploads again: the stored result is used.
  appError,

  /// The operator cancelled.
  cancelled,
}

class ScanFailure implements Exception {
  const ScanFailure(
    this.kind,
    this.message, {
    this.code,
    this.status,
    this.serverKeepsResult = true,
  });

  final ScanFailureKind kind;

  /// In the operator's words.
  final String message;

  /// The server's `detail.code`, when there was one.
  final String? code;
  final int? status;

  /// For [ScanFailureKind.resultLost]: the server stores results by scan id,
  /// so the app can ask for this one (KEEP WAITING) instead of sending the
  /// photos again. False on a server without `scan_jobs_v1`.
  final bool serverKeepsResult;

  String get title => switch (kind) {
    ScanFailureKind.uploadFailed => 'Upload failed',
    ScanFailureKind.resultLost when !serverKeepsResult => 'Result not received',
    ScanFailureKind.resultLost => 'Result not received yet',
    ScanFailureKind.processingFailed => 'Processing failed',
    ScanFailureKind.rejected => 'Scan rejected',
    ScanFailureKind.notAuthorised => 'Phone not authorised',
    ScanFailureKind.appError => 'App error',
    ScanFailureKind.cancelled => 'Cancelled',
  };

  /// Stored as `last_error_class` on the pending scan.
  String get errorClass => switch (kind) {
    ScanFailureKind.uploadFailed => 'upload_failed',
    ScanFailureKind.resultLost => 'result_lost',
    ScanFailureKind.processingFailed => 'processing_failed',
    ScanFailureKind.rejected => 'rejected',
    ScanFailureKind.notAuthorised => 'not_authorised',
    ScanFailureKind.appError => 'app_error',
    ScanFailureKind.cancelled => 'cancelled',
  };

  /// Whether trying the same scan again can succeed.
  bool get retryable => switch (kind) {
    ScanFailureKind.uploadFailed ||
    ScanFailureKind.resultLost ||
    ScanFailureKind.processingFailed ||
    ScanFailureKind.appError => true,
    _ => false,
  };

  @override
  String toString() => '$title: $message';
}

/// Progress of one scan as the processing screen shows it: [connecting]
/// before anything is sent or asked (a resume starts here), [checking] while
/// asking a `scan_jobs_v1` server for a stored result, [waiting] while that
/// server is still counting.
enum ScanStage { connecting, uploading, checking, waiting }
