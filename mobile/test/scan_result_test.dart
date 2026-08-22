import 'package:egg_tray_counter/models/scan_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejected API response keeps inventory totals absent', () {
    final result = ScanResult.fromJson({
      'scan_id': 'scan-3',
      'status': 'rescan_required',
      'accepted': false,
      'physical_stack_count': null,
      'total_trays': null,
      'eggs_per_tray': 30,
      'total_eggs': null,
      'processing': {
        'mode': 'mock',
        'latency_ms': 50,
        'model_version': 'mock/full-face-v1',
      },
      'views': {
        'left': {'quality': 0.2, 'accepted': false, 'reason': 'blurry'},
        'right': {'quality': 0.9, 'accepted': true, 'reason': null},
        'straight': {'quality': 0.9, 'accepted': true, 'reason': null},
      },
      'stacks': <Object>[],
      'rescan': {
        'recommended_view': 'left',
        'reason': 'LEFT photo is blurry',
      },
    });
    expect(result.accepted, isFalse);
    expect(result.totalTrays, isNull);
    expect(result.totalEggs, isNull);
    expect(result.recommendedView, 'left');
  });
}
