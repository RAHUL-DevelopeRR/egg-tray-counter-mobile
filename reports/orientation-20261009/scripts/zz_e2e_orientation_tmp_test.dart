// Temporary: copied into mobile/test/ to run the app's real photo preparation on synthetic phone
// stills, then removed. Not part of the suite.
import 'dart:convert';
import 'dart:io';

import 'package:egg_tray_counter/services/captured_still.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prepare synthetic phone stills', () {
    final dir = Platform.environment['E2E_DIR']!;
    final manifest = jsonDecode(File('$dir/manifest.json').readAsStringSync()) as List;
    final out = <Map<String, Object?>>[];
    for (final item in manifest.cast<Map<String, dynamic>>()) {
      final prepared = prepareCapturedStillSync(
        StillRequest(
          sourcePath: item['raw'] as String,
          targetPath: item['upload'] as String,
          captureRotation: item['rotation'] as int,
          visibleAspect: (item['visible_aspect'] as num?)?.toDouble() ?? 1080 / 2400,
          sensorOrientation: 90,
        ),
      );
      expect(prepared, isNotNull);
      out.add({
        ...item,
        'width': prepared!.width,
        'height': prepared.height,
        'visible_fraction': prepared.visibleFraction,
        'quality_ok': prepared.quality.accepted,
        'quality_reason': prepared.quality.reason,
      });
    }
    File('$dir/prepared.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(out),
    );
  });
}
