import 'dart:convert';

import 'package:egg_tray_counter/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the capture field carries only what decides trust: source, blocked, heading', () {
    final camera = ApiClient.captureField(jsonEncode({
      'source': 'captured_still',
      'blocked': false,
      'yaw_deg': -91.5,
      'yaw_session': 'k3x9',
      'checks': [for (var i = 0; i < 400; i++) {'id': 'x$i'}],
    }))!;
    expect(jsonDecode(camera), {'source': 'captured_still', 'blocked': false, 'yaw_deg': -91.5, 'yaw_session': 'k3x9'});
    expect(camera.length, lessThan(200));
    expect(
      jsonDecode(ApiClient.captureField(jsonEncode({'source': 'uploaded_photo', 'pose_verified': false}))!),
      {'source': 'uploaded_photo'},
    );
    expect(ApiClient.captureField('{not json'), isNull);
    expect(ApiClient.captureField(jsonEncode({'sharpness': 3})), isNull);
    expect(ApiClient.captureField('[1, 2]'), isNull);
  });

  test('model scans require explicit optional-marker support', () {
    expect(
      ApiClient.supportsModelScan({
        'status': 'ok',
        'scan_contract': 'cell_identity_v1',
      }),
      isFalse,
    );
    expect(
      ApiClient.supportsModelScan({
        'status': 'ok',
        'scan_contracts': ['model_spatial_v1'],
      }),
      isTrue,
    );
    expect(
      ApiClient.supportsModelScan({
        'status': 'error',
        'scan_contracts': ['model_spatial_v1'],
      }),
      isFalse,
    );
  });
  test(
    'photo preflight rejects legacy, missing, wrong or unhealthy contracts',
    () {
      for (final data in <Map<String, dynamic>?>[
        null,
        {},
        {'status': 'ok'},
        {'status': 'ok', 'scan_contract': 'single_stack_baseline'},
        {'status': 'error', 'scan_contract': 'cell_identity_v1'},
      ]) {
        expect(ApiClient.supportsCellIdentity(data), isFalse);
      }
      expect(
        ApiClient.supportsCellIdentity({
          'status': 'ok',
          'scan_contract': 'cell_identity_v1',
        }),
        isTrue,
      );
    },
  );
}
