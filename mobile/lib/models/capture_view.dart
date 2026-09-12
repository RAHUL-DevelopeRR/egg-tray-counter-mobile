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
      'Move approximately 25-35 degrees LEFT of the same painted cell. Exclude neighboring cells.',
    CaptureView.right =>
      'Move approximately 25-35 degrees RIGHT of the same painted cell. Exclude neighboring cells.',
    CaptureView.straight =>
      'Stand in front of the same painted cell. Keep all its tray tops and bottoms visible.',
  };
}
