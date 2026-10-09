import 'block_result.dart';

/// The operator's on-site count for one stack of a scanned block.
class ManualCountCell {
  const ManualCountCell({
    required this.x,
    required this.y,
    required this.appLayers,
    required this.appStatus,
    required this.filled,
    required this.empty,
    this.unreachable = false,
  });

  final int x;
  final int y;
  final int? appLayers;
  final String appStatus;
  final int filled;
  final int empty;
  final bool unreachable;

  factory ManualCountCell.fromBlockCell(BlockCell cell) => ManualCountCell(
    x: cell.x,
    y: cell.y,
    appLayers: cell.layers,
    appStatus: cell.status,
    filled: cell.status == 'missing' ? 0 : (cell.layers ?? 0),
    empty: 0,
  );

  ManualCountCell copyWith({int? filled, int? empty, bool? unreachable}) =>
      ManualCountCell(
        x: x,
        y: y,
        appLayers: appLayers,
        appStatus: appStatus,
        filled: filled ?? this.filled,
        empty: empty ?? this.empty,
        unreachable: unreachable ?? this.unreachable,
      );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'app_layers': appLayers,
    'app_status': appStatus,
    'filled': filled,
    'empty': empty,
    'unreachable': unreachable,
  };

  factory ManualCountCell.fromJson(Map<String, dynamic> json) =>
      ManualCountCell(
        x: json['x'] as int,
        y: json['y'] as int,
        appLayers: json['app_layers'] as int?,
        appStatus: json['app_status'] as String? ?? '',
        filled: json['filled'] as int,
        empty: json['empty'] as int,
        unreachable: json['unreachable'] as bool? ?? false,
      );
}

class ManualCount {
  const ManualCount({
    required this.scanId,
    required this.blockId,
    required this.cells,
    required this.notes,
    required this.createdAt,
    this.appTotal,
    this.submitted = false,
  });

  final String scanId;
  final String blockId;
  final List<ManualCountCell> cells;
  final String notes;
  final DateTime createdAt;
  final int? appTotal;
  final bool submitted;

  int get filledTotal => cells.fold(0, (s, c) => s + c.filled);
  int get emptyTotal => cells.fold(0, (s, c) => s + c.empty);
  int get unreachableCount => cells.where((c) => c.unreachable).length;

  ManualCount copyWith({
    String? blockId,
    List<ManualCountCell>? cells,
    String? notes,
    bool? submitted,
  }) => ManualCount(
    scanId: scanId,
    blockId: blockId ?? this.blockId,
    cells: cells ?? this.cells,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    appTotal: appTotal,
    submitted: submitted ?? this.submitted,
  );

  Map<String, dynamic> toJson({String? appVersion}) => {
    'block_id': blockId,
    'cells': cells.map((c) => c.toJson()).toList(growable: false),
    'notes': notes,
    'app_total': appTotal,
    'app_version': ?appVersion,
  };

  static const csvHeader =
      'scan_id,block_id,x,y,app_layers,app_status,filled_trays,empty_trays,unreachable,recorded_at,submitted';

  List<String> csvRows() => [
    for (final c in cells)
      [
        scanId,
        _csv(blockId),
        c.x,
        c.y,
        c.appLayers ?? '',
        c.appStatus,
        c.filled,
        c.empty,
        c.unreachable ? 'yes' : 'no',
        createdAt.toUtc().toIso8601String(),
        submitted ? 'yes' : 'no',
      ].join(','),
  ];

  static String _csv(String value) =>
      value.contains(RegExp('[,"\n]')) ? '"${value.replaceAll('"', '""')}"' : value;
}
