import 'package:egg_tray_counter/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
