enum CaptureView { straight, left, right }

extension CaptureViewLabel on CaptureView {
  String get wireName => name;

  String get title => switch (this) {
    CaptureView.straight => 'STRAIGHT PHOTO',
    CaptureView.left => 'LEFT PHOTO',
    CaptureView.right => 'RIGHT PHOTO',
  };

  /// One block at a time: the front face, then each side face, all square-on.
  String get instruction => switch (this) {
    CaptureView.straight =>
      'Stand square in front of the block. The whole front face fills the '
          'frame, top row and floor visible. Hold the phone level at mid-height.',
    CaptureView.left =>
      "Walk to the block's LEFT side. Photograph that side face square-on, "
          'filling the frame, phone level at mid-height.',
    CaptureView.right =>
      "Walk to the block's RIGHT side. Photograph that side face square-on, "
          'filling the frame, phone level at mid-height.',
  };
}
