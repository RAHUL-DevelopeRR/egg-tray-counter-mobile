import 'package:egg_tray_counter/features/capture/capture_frame_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capture remains locked until every framing confirmation passes', () {
    const initial = CaptureFrameGate();
    expect(initial.ready, isFalse);

    final ready = initial.copyWith(
      stackContained: true,
      topAndBaseVisible: true,
      viewAngleConfirmed: true,
    );
    expect(ready.ready, isTrue);
  });
}
