enum CaptureView { left, right, straight }

extension CaptureViewLabel on CaptureView {
  String get wireName => name;

  String get title => switch (this) {
    CaptureView.left => 'LEFT PHOTO',
    CaptureView.right => 'RIGHT PHOTO',
    CaptureView.straight => 'STRAIGHT PHOTO',
  };

  String get instruction => switch (this) {
    CaptureView.left =>
      'Move approximately 25-35 degrees LEFT of the same group of stacks.',
    CaptureView.right =>
      'Move approximately 25-35 degrees RIGHT of the same group of stacks.',
    CaptureView.straight =>
      'Stand in front of the same stacks. Keep tray tops and bottoms visible.',
  };
}
