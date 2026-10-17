import 'package:sqflite/sqflite.dart';

import '../app/app_version.dart';
import '../models/scan_result.dart';

class ScanHistoryEntry {
  const ScanHistoryEntry({
    required this.scanId,
    required this.createdAt,
    required this.status,
    required this.trayCount,
    required this.eggCount,
    required this.modelVersion,
    required this.latencyMs,
    this.appVersion,
  });

  final String scanId;
  final DateTime createdAt;
  final String status;
  final int? trayCount;
  final int? eggCount;
  final String modelVersion;
  final int latencyMs;

  /// The app that saved the row; null for rows from apps before 0.4.12.
  final String? appVersion;

  /// Apps up to 0.4.10 stored the legacy top-level status, which block scans
  /// always set to rescan_required with no count whatever the block showed
  /// (0.4.11 still did when a server sent no block), so such a row from an
  /// app before 0.4.12 says nothing about the scan. It is shown as unknown
  /// and kept exactly as stored.
  bool get recordedByOlderApp =>
      appVersion == null && status == 'rescan_required' && trayCount == null;

  factory ScanHistoryEntry.fromMap(Map<String, Object?> map) =>
      ScanHistoryEntry(
        scanId: map['scan_id']! as String,
        createdAt: DateTime.parse(map['created_at']! as String),
        status: map['status']! as String,
        trayCount: map['tray_count'] as int?,
        eggCount: map['egg_count'] as int?,
        modelVersion: map['model_version']! as String,
        latencyMs: map['latency_ms']! as int,
        appVersion: map['app_version'] as String?,
      );
}

/// One unfinished scan; its photos are copied under `pending/<scan_id>/`.
class PendingScanRow {
  const PendingScanRow({
    required this.scanId,
    required this.createdAt,
    required this.state,
    this.attempts = 0,
    this.lastErrorClass,
    this.bodySent = false,
  });

  final String scanId;
  final DateTime createdAt;

  /// captured, uploading, failed or result_received.
  final String state;
  final int attempts;
  final String? lastErrorClass;

  /// Whether a complete request body was ever sent for this scan.
  final bool bodySent;

  factory PendingScanRow.fromMap(Map<String, Object?> map) => PendingScanRow(
    scanId: map['scan_id']! as String,
    createdAt: DateTime.parse(map['created_at']! as String),
    state: map['state']! as String,
    attempts: map['attempts']! as int,
    lastErrorClass: map['last_error_class'] as String?,
    bodySent: (map['body_sent']! as int) == 1,
  );

  Map<String, Object?> toMap() => {
    'scan_id': scanId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'state': state,
    'attempts': attempts,
    'last_error_class': lastErrorClass,
    'body_sent': bodySent ? 1 : 0,
  };
}

/// Scan history and unfinished scans, one SQLite file. [factory] and [path]
/// let tests open it with sqflite_common_ffi.
class HistoryDatabase {
  HistoryDatabase({DatabaseFactory? factory, String? path})
    : _factory = factory,
      _path = path;

  static const schemaVersion = 2;

  final DatabaseFactory? _factory;
  final String? _path;
  Future<Database>? _opening;

  static const _scansTable = '''
    CREATE TABLE scans (
      scan_id TEXT PRIMARY KEY,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL,
      tray_count INTEGER,
      egg_count INTEGER,
      model_version TEXT NOT NULL,
      latency_ms INTEGER NOT NULL,
      app_version TEXT
    )
  ''';

  static const _pendingTable = '''
    CREATE TABLE pending_scans (
      scan_id TEXT PRIMARY KEY,
      created_at TEXT NOT NULL,
      state TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error_class TEXT,
      body_sent INTEGER NOT NULL DEFAULT 0
    )
  ''';

  Future<Database> get _db async {
    final opening = _opening ??= _open();
    try {
      return await opening;
    } on Object {
      // Let the next call try again rather than keep a failed open.
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final path =
        _path ?? '${await factory.getDatabasesPath()}/egg_tray_counter.db';
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (database, _) async {
          await database.execute(_scansTable);
          await database.execute(_pendingTable);
        },
        onUpgrade: (database, from, _) async {
          if (from < 2) {
            // Existing rows keep every stored value; app_version stays NULL,
            // which is what marks them as written by an app before 0.4.12.
            await database.execute(
              'ALTER TABLE scans ADD COLUMN app_version TEXT',
            );
            await database.execute(_pendingTable);
          }
        },
      ),
    );
  }

  Future<void> save(ScanResult result, {String appVersion = kAppVersion}) async {
    final database = await _db;
    await database.transaction((txn) async {
      final existing = await txn.query(
        'scans',
        columns: ['app_version'],
        where: 'scan_id = ?',
        whereArgs: [result.scanId],
      );
      // A row from an older app is never rewritten.
      if (existing.isNotEmpty && existing.first['app_version'] == null) return;
      await txn.insert(
        'scans',
        {
          'scan_id': result.scanId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          // Same state and total the result screen showed (block scans used
          // to be stored as rescan_required with no count).
          'status': result.resultStatus,
          'tray_count': result.shownTrays,
          'egg_count': result.shownEggs,
          'model_version': result.modelVersion,
          'latency_ms': result.latencyMs,
          'app_version': appVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<ScanHistoryEntry>> recent({int limit = 20}) async {
    final database = await _db;
    final rows = await database.query(
      'scans',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ScanHistoryEntry.fromMap).toList(growable: false);
  }

  Future<void> insertPending(PendingScanRow row) async {
    final database = await _db;
    await database.insert(
      'pending_scans',
      row.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<PendingScanRow?> pending(String scanId) async {
    final database = await _db;
    final rows = await database.query(
      'pending_scans',
      where: 'scan_id = ?',
      whereArgs: [scanId],
    );
    return rows.isEmpty ? null : PendingScanRow.fromMap(rows.first);
  }

  /// The most recent unfinished scan, if any.
  Future<PendingScanRow?> latestPending() async {
    final database = await _db;
    final rows = await database.query(
      'pending_scans',
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : PendingScanRow.fromMap(rows.first);
  }

  Future<List<String>> pendingIds() async {
    final database = await _db;
    final rows = await database.query('pending_scans', columns: ['scan_id']);
    return [for (final row in rows) row['scan_id']! as String];
  }

  Future<void> updatePending(
    String scanId, {
    String? state,
    String? lastErrorClass,
    bool? bodySent,
    bool addAttempt = false,
  }) async {
    final database = await _db;
    final sets = <String>[
      if (state != null) 'state = ?',
      if (lastErrorClass != null) 'last_error_class = ?',
      if (bodySent != null) 'body_sent = ?',
      if (addAttempt) 'attempts = attempts + 1',
    ];
    if (sets.isEmpty) return;
    await database.rawUpdate(
      'UPDATE pending_scans SET ${sets.join(', ')} WHERE scan_id = ?',
      [
        ?state,
        ?lastErrorClass,
        if (bodySent != null) bodySent ? 1 : 0,
        scanId,
      ],
    );
  }

  Future<void> deletePending(String scanId) async {
    final database = await _db;
    await database.delete(
      'pending_scans',
      where: 'scan_id = ?',
      whereArgs: [scanId],
    );
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}
