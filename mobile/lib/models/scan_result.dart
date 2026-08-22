class ViewResult {
  const ViewResult({
    required this.quality,
    required this.accepted,
    this.reason,
  });

  final double quality;
  final bool accepted;
  final String? reason;

  factory ViewResult.fromJson(Map<String, dynamic> json) => ViewResult(
    quality: (json['quality'] as num).toDouble(),
    accepted: json['accepted'] as bool,
    reason: json['reason'] as String?,
  );
}

class StackResult {
  const StackResult({
    required this.id,
    required this.counts,
    required this.finalCount,
    required this.confidence,
    required this.accepted,
    required this.reason,
  });

  final String id;
  final Map<String, int?> counts;
  final int? finalCount;
  final double confidence;
  final bool accepted;
  final String reason;

  factory StackResult.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['counts'] as Map<String, dynamic>;
    return StackResult(
      id: json['physical_stack_id'] as String,
      counts: rawCounts.map(
        (key, value) => MapEntry(key, value as int?),
      ),
      finalCount: json['final_count'] as int?,
      confidence: (json['confidence'] as num).toDouble(),
      accepted: json['accepted'] as bool,
      reason: json['reason'] as String,
    );
  }
}

class ScanResult {
  const ScanResult({
    required this.scanId,
    required this.accepted,
    required this.status,
    required this.physicalStackCount,
    required this.totalTrays,
    required this.eggsPerTray,
    required this.totalEggs,
    required this.modelVersion,
    required this.latencyMs,
    required this.views,
    required this.stacks,
    this.recommendedView,
    this.rescanReason,
  });

  final String scanId;
  final bool accepted;
  final String status;
  final int? physicalStackCount;
  final int? totalTrays;
  final int eggsPerTray;
  final int? totalEggs;
  final String modelVersion;
  final int latencyMs;
  final Map<String, ViewResult> views;
  final List<StackResult> stacks;
  final String? recommendedView;
  final String? rescanReason;

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    final processing = json['processing'] as Map<String, dynamic>;
    final viewsJson = json['views'] as Map<String, dynamic>;
    final rescan = json['rescan'] as Map<String, dynamic>?;
    return ScanResult(
      scanId: json['scan_id'] as String,
      accepted: json['accepted'] as bool,
      status: json['status'] as String,
      physicalStackCount: json['physical_stack_count'] as int?,
      totalTrays: json['total_trays'] as int?,
      eggsPerTray: json['eggs_per_tray'] as int,
      totalEggs: json['total_eggs'] as int?,
      modelVersion: processing['model_version'] as String,
      latencyMs: processing['latency_ms'] as int,
      views: viewsJson.map(
        (key, value) => MapEntry(
          key,
          ViewResult.fromJson(value as Map<String, dynamic>),
        ),
      ),
      stacks: (json['stacks'] as List<dynamic>)
          .map(
            (value) => StackResult.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false),
      recommendedView: rescan?['recommended_view'] as String?,
      rescanReason: rescan?['reason'] as String?,
    );
  }
}

