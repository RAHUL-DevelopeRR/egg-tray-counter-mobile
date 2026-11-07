import 'package:egg_tray_counter/models/block_declaration.dart';
import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/models/extra_capture.dart';
import 'package:egg_tray_counter/models/scan_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replacement and clearing never reuse previous capture evidence', () {
    final session = ScanSession(scanId: 'evidence')
      ..setPath(CaptureView.left, 'first.jpg', evidence: '{"capture":1}');
    expect(session.constraintEvidence['left'], '{"capture":1}');
    session.setPath(CaptureView.left, 'second.jpg');
    expect(session.constraintEvidence, isEmpty);
    session.setPath(CaptureView.left, 'third.jpg', evidence: '{"capture":3}');
    session.clear(CaptureView.left);
    expect(session.constraintEvidence, isEmpty);
  });
  test('capture state advances STRAIGHT, LEFT, RIGHT', () {
    final session = ScanSession(scanId: 'scan-1');
    expect(session.nextMissing, CaptureView.straight);
    session.setPath(CaptureView.straight, 'straight.jpg', cellId: 'A1');
    expect(session.nextMissing, CaptureView.left);
    session.setPath(CaptureView.left, 'left.jpg', cellId: 'A1');
    expect(session.nextMissing, CaptureView.right);
    session.setPath(CaptureView.right, 'right.jpg', cellId: 'A1');
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
    'optional cell ID is validated when provided; no identity is invented',
    () {
      final session = ScanSession(scanId: 'scan-3');
      session.setPath(CaptureView.left, 'x.jpg');
      expect(session.pathFor(CaptureView.left), 'x.jpg');
      expect(session.cellIds, isEmpty);
      session.setPath(CaptureView.left, 'x.jpg', cellId: ' w1-a2 ');
      expect(session.cellIds, {'left': 'W1-A2'});
      expect(() => ScanSession.normalizeCellId('A/B'), throwsFormatException);
      expect(
        () => ScanSession.normalizeCellId('A' * 33),
        throwsFormatException,
      );
    },
  );

  test('three photos are complete without painted floor IDs', () {
    final session = ScanSession(scanId: 'no-markers')
      ..setPath(CaptureView.left, 'left.jpg')
      ..setPath(CaptureView.right, 'right.jpg')
      ..setPath(CaptureView.straight, 'straight.jpg');
    expect(session.isComplete, isTrue);
    expect(session.cellIds, isEmpty);
  });

  test('a retake is a new scan id that keeps the other two photos', () {
    final first = ScanSession(scanId: 'scan-a')
      ..setPath(CaptureView.left, 'left.jpg', cellId: 'A1', evidence: '{"l":1}')
      ..setPath(CaptureView.right, 'right.jpg', evidence: '{"r":1}')
      ..setPath(CaptureView.straight, 'straight.jpg', evidence: '{"s":1}');
    final retake = first.retake(CaptureView.right, scanId: 'scan-b');
    expect(retake.scanId, 'scan-b');
    expect(retake.scanId, isNot(first.scanId));
    expect(retake.pathFor(CaptureView.right), isNull);
    expect(retake.nextMissing, CaptureView.right);
    expect(retake.pathFor(CaptureView.left), 'left.jpg');
    expect(retake.pathFor(CaptureView.straight), 'straight.jpg');
    expect(retake.cellIds, {'left': 'A1'});
    expect(retake.constraintEvidence, {'left': '{"l":1}', 'straight': '{"s":1}'});
    // The original triplet is untouched.
    expect(first.isComplete, isTrue);
    expect(first.constraintEvidence['right'], '{"r":1}');
  });

  test('extras never decide completeness; the declaration is asked once and '
      'a retake keeps it and the extras', () {
    final declaration = BlockDeclaration(
      x: 5,
      y: 3,
      declaredAt: DateTime.utc(2026, 11, 1, 10),
    );
    final first = ScanSession(scanId: 'scan-a')
      ..setExtra(
        ExtraView.corner,
        'corner.jpg',
        evidence: '{"c":1}',
        side: kCornerFrontRight,
      );
    expect(first.isComplete, isFalse);
    expect(first.nextMissing, CaptureView.straight);
    for (final view in CaptureView.values) {
      first.setPath(view, '${view.name}.jpg');
    }
    expect(first.isComplete, isTrue);
    expect(first.constraintEvidence, isEmpty, reason: 'extras keep their own');
    expect(first.declarationAsked, isFalse);
    first.declare(declaration);
    expect(first.declarationAsked, isTrue);

    first.setExtra(ExtraView.elevated, 'top.jpg', evidence: '{"e":1}');
    first.setElevatedTaps(const ElevatedTaps(x: 5, y: 3).tap(0, 0));
    expect(first.extraFor(ExtraView.elevated)!.taps!.cells, {
      (0, 0): kTapPresent,
    });
    expect(first.allPaths, containsAll(['corner.jpg', 'top.jpg', 'left.jpg']));

    final retake = first.retake(CaptureView.left, scanId: 'scan-b');
    expect(retake.declarationAsked, isTrue);
    expect(retake.declaration, same(declaration));
    expect(retake.extraFor(ExtraView.corner)!.side, kCornerFrontRight);
    expect(retake.extraFor(ExtraView.elevated)!.taps, isNotNull);

    // A new elevated photo drops the reading of the old one.
    retake.setExtra(ExtraView.elevated, 'top2.jpg');
    expect(retake.extraFor(ExtraView.elevated)!.taps, isNull);
    retake.clearExtra(ExtraView.corner);
    expect(retake.extraFor(ExtraView.corner), isNull);
    expect(first.extraFor(ExtraView.corner), isNotNull);

    // Skipped: asked, nothing declared.
    final skipped = ScanSession(scanId: 'scan-c')..declare(null);
    expect(skipped.declarationAsked, isTrue);
    expect(skipped.declaration, isNull);
  });
}
