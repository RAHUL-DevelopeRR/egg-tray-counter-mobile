import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../app/app_version.dart';
import '../models/capture_view.dart';
import '../models/scan_session.dart';
import 'history_database.dart';

/// Unfinished scans kept on the phone until their result is in history:
/// a `pending_scans` row plus `pending/<scan_id>/` in the app documents
/// directory with the three upload files, session.json (cell IDs and each
/// view's evidence JSON) and, once a 200 arrives, result.json. Android may
/// kill the app mid-upload; with this the scan can be resumed.
abstract class PendingScanStore {
  Future<PendingScanRow?> find(String scanId);

  /// The most recent unfinished scan, offered as RESUME on the home screen.
  Future<PendingScanRow?> latest();

  /// Copies the session's photos and evidence; the row is written last, so
  /// a row always has its files.
  Future<PendingScanRow> create(ScanSession session);

  Future<void> recordAttempt(String scanId);
  Future<void> markBodySent(String scanId);
  Future<void> markFailed(String scanId, String errorClass);

  /// Keeps a 200 body before it is read, so a parse or save failure on the
  /// phone never costs another upload.
  Future<void> storeResult(String scanId, Map<String, dynamic> body);
  Future<Map<String, dynamic>?> storedResult(String scanId);

  /// Forgets a kept answer that turned out not to fit the scan, so the next
  /// try asks the server again instead of replaying it.
  Future<void> clearResult(String scanId);

  /// A session for [scanId] with its own copies of the photos (the pending
  /// copies stay until the result is saved).
  Future<ScanSession> restore(String scanId);

  /// Forgets the scan: after its result is in history, or when the operator
  /// abandons it.
  Future<void> remove(String scanId);

  /// Deletes pending folders that have no row (a removal cut short).
  Future<void> sweep();
}

class DiskPendingScanStore implements PendingScanStore {
  DiskPendingScanStore({
    required this.database,
    Future<Directory> Function()? root,
    Future<Directory> Function()? scratch,
  }) : _root = root ?? _defaultRoot,
       _scratch = scratch ?? (() async => Directory.systemTemp);

  final HistoryDatabase database;
  final Future<Directory> Function() _root;
  final Future<Directory> Function() _scratch;

  static Future<Directory> _defaultRoot() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}/pending');

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  Future<Directory> _dir(String scanId) async {
    if (!_safeId.hasMatch(scanId)) {
      throw FormatException('Unexpected scan id: $scanId');
    }
    return Directory('${(await _root()).path}/$scanId');
  }

  @override
  Future<PendingScanRow?> find(String scanId) => database.pending(scanId);

  @override
  Future<PendingScanRow?> latest() => database.latestPending();

  @override
  Future<PendingScanRow> create(ScanSession session) async {
    final dir = await _dir(session.scanId);
    try {
      await dir.create(recursive: true);
      final views = <String, Object?>{};
      for (final view in CaptureView.values) {
        final path = session.pathFor(view);
        if (path == null) throw StateError('${view.name} photo missing');
        await File(path).copy('${dir.path}/${view.name}.jpg');
        views[view.name] = {
          'file': '${view.name}.jpg',
          'cell_id': session.cellIdFor(view),
          'evidence': session.constraintEvidence[view.name],
        };
      }
      final row = PendingScanRow(
        scanId: session.scanId,
        createdAt: DateTime.now().toUtc(),
        state: 'captured',
      );
      await _writeJson(File('${dir.path}/session.json'), {
        'scan_id': session.scanId,
        'created_at': row.createdAt.toIso8601String(),
        'app_version': kAppVersion,
        'views': views,
      });
      await database.insertPending(row);
      return row;
    } on Object {
      await _deleteDir(dir);
      rethrow;
    }
  }

  @override
  Future<void> recordAttempt(String scanId) =>
      database.updatePending(scanId, state: 'uploading', addAttempt: true);

  @override
  Future<void> markBodySent(String scanId) =>
      database.updatePending(scanId, bodySent: true);

  @override
  Future<void> markFailed(String scanId, String errorClass) =>
      database.updatePending(
        scanId,
        state: 'failed',
        lastErrorClass: errorClass,
      );

  @override
  Future<void> storeResult(String scanId, Map<String, dynamic> body) async {
    final dir = await _dir(scanId);
    await _writeJson(File('${dir.path}/result.json'), body);
    await database.updatePending(scanId, state: 'result_received');
  }

  @override
  Future<Map<String, dynamic>?> storedResult(String scanId) async {
    final file = File('${(await _dir(scanId)).path}/result.json');
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  @override
  Future<void> clearResult(String scanId) async {
    final file = File('${(await _dir(scanId)).path}/result.json');
    if (await file.exists()) await file.delete();
    await database.updatePending(scanId, state: 'failed');
  }

  @override
  Future<ScanSession> restore(String scanId) async {
    final dir = await _dir(scanId);
    final manifest = jsonDecode(
      await File('${dir.path}/session.json').readAsString(),
    ) as Map<String, dynamic>;
    final views = manifest['views'] as Map<String, dynamic>;
    final scratch = await _scratch();
    final session = ScanSession(scanId: scanId);
    for (final view in CaptureView.values) {
      final entry = views[view.name] as Map<String, dynamic>;
      final copy = await File(
        '${dir.path}/${entry['file']}',
      ).copy('${scratch.path}/${const Uuid().v4()}.jpg');
      session.setPath(
        view,
        copy.path,
        cellId: entry['cell_id'] as String? ?? '',
        evidence: entry['evidence'] as String?,
      );
    }
    return session;
  }

  @override
  Future<void> remove(String scanId) async {
    await database.deletePending(scanId);
    await _deleteDir(await _dir(scanId));
  }

  @override
  Future<void> sweep() async {
    final root = await _root();
    if (!await root.exists()) return;
    final keep = (await database.pendingIds()).toSet();
    // A folder younger than an hour may belong to a scan whose row is
    // still being written (create() writes the row last).
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (keep.contains(name)) continue;
      if ((await entry.stat()).modified.isAfter(cutoff)) continue;
      await _deleteDir(entry);
    }
  }

  /// Written to a temporary name first, so a killed app leaves the old file
  /// or the new one, never half of one.
  static Future<void> _writeJson(File file, Object value) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }

  static Future<void> _deleteDir(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Best effort; sweep() retries orphans on a later launch.
    }
  }
}
