import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/models/scan_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capture state advances LEFT, RIGHT, STRAIGHT', () {
    final session = ScanSession(scanId: 'scan-1');
    expect(session.nextMissing, CaptureView.left);
    session.setPath(CaptureView.left, 'left.jpg', cellId: 'A1');
    expect(session.nextMissing, CaptureView.right);
    session.setPath(CaptureView.right, 'right.jpg', cellId: 'A1');
    expect(session.nextMissing, CaptureView.straight);
    session.setPath(CaptureView.straight, 'straight.jpg', cellId: 'A1');
    expect(session.isComplete, isTrue);
    expect(session.nextMissing, isNull);
  });

  test('retaking RIGHT preserves LEFT and STRAIGHT', () {
    final session = ScanSession(scanId: 'scan-2')
      ..setPath(CaptureView.left, 'left.jpg', cellId: 'A1')
      ..setPath(CaptureView.right, 'right.jpg', cellId: 'B1')
      ..setPath(CaptureView.straight, 'straight.jpg', cellId: 'C1');
    session.clear(CaptureView.right);
    expect(session.pathFor(CaptureView.left), 'left.jpg');
    expect(session.pathFor(CaptureView.straight), 'straight.jpg');
    expect(session.nextMissing, CaptureView.right);
    expect(session.isComplete, isFalse);
    expect(session.cellIdFor(CaptureView.right), isNull);
    expect(session.cellIdFor(CaptureView.left), 'A1');
  });

  test(
    'cell ID is validated before binding a photo; no identity is inferred',
    () {
      final session = ScanSession(scanId: 'scan-3');
      expect(
        () => session.setPath(CaptureView.left, 'x.jpg', cellId: ''),
        throwsFormatException,
      );
      expect(session.pathFor(CaptureView.left), isNull);
      session.setPath(CaptureView.left, 'x.jpg', cellId: ' w1-a2 ');
      expect(session.cellIds, {'left': 'W1-A2'});
      expect(() => ScanSession.normalizeCellId('A/B'), throwsFormatException);
      expect(
        () => ScanSession.normalizeCellId('A' * 33),
        throwsFormatException,
      );
    },
  );
}
