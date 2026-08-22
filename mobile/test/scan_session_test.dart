import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/models/scan_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capture state advances LEFT, RIGHT, STRAIGHT', () {
    final session = ScanSession(scanId: 'scan-1');
    expect(session.nextMissing, CaptureView.left);
    session.setPath(CaptureView.left, 'left.jpg');
    expect(session.nextMissing, CaptureView.right);
    session.setPath(CaptureView.right, 'right.jpg');
    expect(session.nextMissing, CaptureView.straight);
    session.setPath(CaptureView.straight, 'straight.jpg');
    expect(session.isComplete, isTrue);
    expect(session.nextMissing, isNull);
  });

  test('retaking RIGHT preserves LEFT and STRAIGHT', () {
    final session = ScanSession(scanId: 'scan-2')
      ..setPath(CaptureView.left, 'left.jpg')
      ..setPath(CaptureView.right, 'right.jpg')
      ..setPath(CaptureView.straight, 'straight.jpg');
    session.clear(CaptureView.right);
    expect(session.pathFor(CaptureView.left), 'left.jpg');
    expect(session.pathFor(CaptureView.straight), 'straight.jpg');
    expect(session.nextMissing, CaptureView.right);
    expect(session.isComplete, isFalse);
  });
}
