import 'package:sqflite/sqflite.dart';

import '../models/manual_count.dart';

/// Where manual counts are kept on the phone. Abstract so screens can be
/// tested without SQLite.
abstract class ManualCountRepository {
  Future<void> save(ManualCount count);
  Future<List<ManualCount>> all();

  Future<String> csv() async {
    final counts = await all();
    return [
      ManualCount.csvHeader,
      for (final c in counts) ...c.csvRows(),
    ].join('\n');
  }
}

class InMemoryManualCountRepository extends ManualCountRepository {
  final Map<String, ManualCount> _counts = {};

  @override
  Future<void> save(ManualCount count) async => _counts[count.scanId] = count;

  @override
  Future<List<ManualCount>> all() async => _counts.values.toList(growable: false)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

class SqliteManualCountRepository extends ManualCountRepository {
  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      '$root/manual_counts.db',
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE manual_count_cells (
            scan_id TEXT NOT NULL,
            block_id TEXT NOT NULL,
            x INTEGER NOT NULL,
            y INTEGER NOT NULL,
            app_layers INTEGER,
            app_status TEXT NOT NULL,
            filled INTEGER NOT NULL,
            empty INTEGER NOT NULL,
            unreachable INTEGER NOT NULL,
            notes TEXT NOT NULL,
            app_total INTEGER,
            created_at TEXT NOT NULL,
            submitted INTEGER NOT NULL,
            PRIMARY KEY (scan_id, x, y)
          )
        ''');
      },
    );
    return _database!;
  }

  @override
  Future<void> save(ManualCount count) async {
    final database = await _db;
    await database.transaction((txn) async {
      await txn.delete(
        'manual_count_cells',
        where: 'scan_id = ?',
        whereArgs: [count.scanId],
      );
      for (final c in count.cells) {
        await txn.insert('manual_count_cells', {
          'scan_id': count.scanId,
          'block_id': count.blockId,
          'x': c.x,
          'y': c.y,
          'app_layers': c.appLayers,
          'app_status': c.appStatus,
          'filled': c.filled,
          'empty': c.empty,
          'unreachable': c.unreachable ? 1 : 0,
          'notes': count.notes,
          'app_total': count.appTotal,
          'created_at': count.createdAt.toUtc().toIso8601String(),
          'submitted': count.submitted ? 1 : 0,
        });
      }
    });
  }

  @override
  Future<List<ManualCount>> all() async {
    final database = await _db;
    final rows = await database.query(
      'manual_count_cells',
      orderBy: 'created_at DESC, y ASC, x ASC',
    );
    final byScan = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      byScan.putIfAbsent(row['scan_id']! as String, () => []).add(row);
    }
    return [
      for (final entry in byScan.entries)
        ManualCount(
          scanId: entry.key,
          blockId: entry.value.first['block_id']! as String,
          notes: entry.value.first['notes']! as String,
          appTotal: entry.value.first['app_total'] as int?,
          createdAt: DateTime.parse(entry.value.first['created_at']! as String),
          submitted: (entry.value.first['submitted']! as int) == 1,
          cells: [
            for (final r in entry.value)
              ManualCountCell(
                x: r['x']! as int,
                y: r['y']! as int,
                appLayers: r['app_layers'] as int?,
                appStatus: r['app_status']! as String,
                filled: r['filled']! as int,
                empty: r['empty']! as int,
                unreachable: (r['unreachable']! as int) == 1,
              ),
          ],
        ),
    ];
  }
}
