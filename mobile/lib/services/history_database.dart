import 'package:sqflite/sqflite.dart';

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
  });

  final String scanId;
  final DateTime createdAt;
  final String status;
  final int? trayCount;
  final int? eggCount;
  final String modelVersion;
  final int latencyMs;

  factory ScanHistoryEntry.fromMap(Map<String, Object?> map) =>
      ScanHistoryEntry(
        scanId: map['scan_id']! as String,
        createdAt: DateTime.parse(map['created_at']! as String),
        status: map['status']! as String,
        trayCount: map['tray_count'] as int?,
        eggCount: map['egg_count'] as int?,
        modelVersion: map['model_version']! as String,
        latencyMs: map['latency_ms']! as int,
      );
}

class HistoryDatabase {
  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      '$root/egg_tray_counter.db',
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE scans (
            scan_id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            status TEXT NOT NULL,
            tray_count INTEGER,
            egg_count INTEGER,
            model_version TEXT NOT NULL,
            latency_ms INTEGER NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<void> save(ScanResult result) async {
    final database = await _db;
    await database.insert(
      'scans',
      {
        'scan_id': result.scanId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'status': result.status,
        'tray_count': result.totalTrays,
        'egg_count': result.totalEggs,
        'model_version': result.modelVersion,
        'latency_ms': result.latencyMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
}

