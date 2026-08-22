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
      'Move approximately 25-35 degrees to the LEFT. Keep all stacks inside the guide.',
    CaptureView.right =>
      'Move approximately 25-35 degrees to the RIGHT. Keep all stacks inside the guide.',
    CaptureView.straight =>
      'Stand directly in front. Keep the entire scene, stack tops, and stack bottoms visible.',
  };
}
