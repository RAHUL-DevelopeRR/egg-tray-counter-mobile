class CaptureFrameGate {
  const CaptureFrameGate({
    this.stackContained = false,
    this.topAndBaseVisible = false,
    this.viewAngleConfirmed = false,
  });

  final bool stackContained;
  final bool topAndBaseVisible;
  final bool viewAngleConfirmed;

  bool get ready => stackContained && topAndBaseVisible && viewAngleConfirmed;

  CaptureFrameGate copyWith({
    bool? stackContained,
    bool? topAndBaseVisible,
    bool? viewAngleConfirmed,
  }) {
    return CaptureFrameGate(
      stackContained: stackContained ?? this.stackContained,
      topAndBaseVisible: topAndBaseVisible ?? this.topAndBaseVisible,
      viewAngleConfirmed: viewAngleConfirmed ?? this.viewAngleConfirmed,
    );
  }
}
