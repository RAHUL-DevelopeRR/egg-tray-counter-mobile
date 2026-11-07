import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../../models/capture_view.dart';
import '../../models/scan_session.dart';
import '../../services/captured_still.dart';
import '../../services/image_quality_service.dart';

/// Largest photo decoded in Dart. A 50 MP phone photo would hold several
/// hundred MB there; [prepareGalleryPhoto] has the platform decoder shrink it.
const int kMaxDartDecodePixels = 40000000;

/// A photo over [kMaxDartDecodePixels]; [prepareGalleryPhoto] shrinks it.
class OversizedPhotoException implements Exception {
  const OversizedPhotoException(this.width, this.height);

  final int width;
  final int height;

  @override
  String toString() => 'Photo of $width × $height px is over 40 megapixels.';
}

/// Pixel size from the JPEG frame header or the PNG IHDR, without decoding:
/// the image package's startDecode allocates every DCT block (about 300 MB for
/// a 50 MP JPEG) before it reports the size.
({int width, int height})? encodedPixelSize(Uint8List b) {
  if (b.length >= 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) {
    final data = ByteData.sublistView(b);
    return (width: data.getUint32(16), height: data.getUint32(20));
  }
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // Fill byte.
      continue;
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2; // Standalone marker: no length field.
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) return null; // No frame header.
    final length = (b[i + 2] << 8) | b[i + 3];
    // SOF0–SOF15 carry the frame size; C4 (DHT), C8 and CC (DAC) do not.
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      if (i + 9 > b.length) return null;
      return (
        width: (b[i + 7] << 8) | b[i + 8],
        height: (b[i + 5] << 8) | b[i + 6],
      );
    }
    i += 2 + length;
  }
  return null;
}

/// Makes an owned JPEG copy: scan cleanup must never delete the user's original.
/// Throws [OversizedPhotoException] for a photo over [kMaxDartDecodePixels].
Future<String> prepareUploadedPhoto(String source) async {
  final original = File(source);
  if (await original.length() > 20 * 1024 * 1024) {
    throw const FormatException('Choose a photo smaller than 20 MB.');
  }
  final bytes = await original.readAsBytes();
  final decoder = img.findDecoderForData(bytes);
  if (decoder is! img.JpegDecoder && decoder is! img.PngDecoder) {
    throw const FormatException('Choose a JPEG or PNG photo.');
  }
  final size = encodedPixelSize(bytes);
  if (size != null && size.width * size.height > kMaxDartDecodePixels) {
    throw OversizedPhotoException(size.width, size.height);
  }
  final info = decoder?.startDecode(bytes);
  if (info == null) {
    throw const FormatException('Choose a valid JPEG or PNG photo.');
  }
  if (info.width * info.height > kMaxDartDecodePixels) {
    throw OversizedPhotoException(info.width, info.height);
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('Cannot decode this photo.');
  final copy = File('${Directory.systemTemp.path}/${const Uuid().v4()}.jpg');
  try {
    var oriented = img.bakeOrientation(decoded);
    // Same long side and quality as camera stills (see captured_still.dart).
    final longest = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;
    if (longest > kUploadLongSide) {
      final scale = kUploadLongSide / longest;
      oriented = img.copyResize(
        oriented,
        width: (oriented.width * scale).round(),
        height: (oriented.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }
    await copy.writeAsBytes(
      img.encodeJpg(oriented, quality: kUploadJpegQuality),
    );
    final quality = await const ImageQualityService().inspect(copy.path);
    if (!quality.accepted) {
      throw FormatException(quality.reason ?? 'Photo quality is insufficient.');
    }
    return copy.path;
  } catch (_) {
    if (await copy.exists()) await copy.delete();
    rethrow;
  }
}

/// Shrinks [source] so its long side is [longSide] px and returns a PNG copy.
typedef PhotoShrinker = Future<String> Function(String source, int longSide);

/// The platform decoder samples the JPEG at the smaller size, so the full-size
/// pixels are never held, and it applies the EXIF orientation.
Future<String> shrinkWithPlatformDecoder(String source, int longSide) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    await File(source).readAsBytes(),
  );
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final landscape = descriptor.width >= descriptor.height;
  final codec = await descriptor.instantiateCodec(
    targetWidth: landscape ? longSide : null,
    targetHeight: landscape ? null : longSide,
  );
  final frame = await codec.getNextFrame();
  final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  if (png == null) throw const FormatException('Cannot decode this photo.');
  final copy = File('${Directory.systemTemp.path}/${const Uuid().v4()}.png');
  await copy.writeAsBytes(
    png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
  );
  return copy.path;
}

/// [prepareUploadedPhoto] off the UI isolate. A photo over
/// [kMaxDartDecodePixels] is first shrunk to the upload size by [shrink], so it
/// takes the same checks as any other photo instead of being refused.
Future<String> prepareGalleryPhoto(
  String source, {
  PhotoShrinker shrink = shrinkWithPlatformDecoder,
}) async {
  try {
    return await compute(prepareUploadedPhoto, source);
  } on OversizedPhotoException {
    final smaller = await shrink(source, kUploadLongSide);
    try {
      return await compute(prepareUploadedPhoto, smaller);
    } finally {
      try {
        await File(smaller).delete();
      } on FileSystemException {
        /* Cache cleanup. */
      }
    }
  }
}

class PhotoUploadPane extends StatefulWidget {
  const PhotoUploadPane({
    required this.session,
    required this.onComplete,
    super.key,
  });

  final ScanSession session;
  final ValueChanged<ScanSession> onComplete;

  @override
  State<PhotoUploadPane> createState() => _PhotoUploadPaneState();
}

class _PhotoUploadPaneState extends State<PhotoUploadPane> {
  bool _busy = false;
  bool _sameScene = false;
  String? _error;

  Future<void> _pick(CaptureView view) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? owned;
    try {
      // The gallery picker is what a warehouse operator will use; the generic
      // document picker never lists files on some MIUI phones.
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (selected == null || !mounted) return;
      owned = await prepareGalleryPhoto(selected.path);
      if (!mounted) return;
      final old = widget.session.pathFor(view);
      widget.session.setPath(
        view,
        owned,
        evidence: jsonEncode({
          'source': 'uploaded_photo',
          'pose_verified': false,
          'live_checks_performed': false,
        }),
      );
      owned = null; // Session now owns this copy.
      setState(() => _sameScene = false);
      if (old != null) {
        try {
          await File(old).delete();
        } on FileSystemException {
          /* Cache cleanup. */
        }
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Photo not selected: $error');
    } finally {
      if (owned != null) {
        try {
          await File(owned).delete();
        } on FileSystemException {
          /* Cache cleanup. */
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Choose three views of the same unchanged stacks. Originals are preserved. Lighting and blur are checked; camera angles and hidden trays cannot be verified from file selection.',
      ),
      for (final view in CaptureView.values)
        Card(
          child: ListTile(
            leading: widget.session.pathFor(view) == null
                ? const Icon(Icons.add_photo_alternate_outlined)
                : Image.file(
                    File(widget.session.pathFor(view)!),
                    width: 56,
                    height: 56,
                    cacheWidth: 112,
                    fit: BoxFit.cover,
                  ),
            title: Text(view.title),
            subtitle: Text(
              widget.session.pathFor(view) == null
                  ? 'Choose photo'
                  : 'Selected — tap to replace',
            ),
            onTap: _busy ? null : () => _pick(view),
          ),
        ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!, semanticsLabel: _error),
        ),
      CheckboxListTile(
        value: _sameScene,
        onChanged: _busy
            ? null
            : (value) => setState(() => _sameScene = value ?? false),
        title: const Text(
          'These photos show the same stacks, without moving or rearranging trays.',
        ),
      ),
      FilledButton.icon(
        onPressed: !_busy && _sameScene && widget.session.isComplete
            ? () => widget.onComplete(widget.session)
            : null,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text('UPLOAD AND COUNT'),
      ),
      const Text(
        'The backend may return an unverified result or request another view. Uploading does not establish an exact warehouse total.',
      ),
    ],
  );
}
