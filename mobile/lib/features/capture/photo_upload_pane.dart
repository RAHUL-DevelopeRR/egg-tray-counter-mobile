import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../../models/capture_view.dart';
import '../../models/scan_session.dart';
import '../../services/image_quality_service.dart';

/// Makes an owned JPEG copy: scan cleanup must never delete the user's original.
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
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 40000000) {
    throw const FormatException(
      'Choose a valid JPEG or PNG of at most 40 megapixels.',
    );
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('Cannot decode this photo.');
  final copy = File('${Directory.systemTemp.path}/${const Uuid().v4()}.jpg');
  try {
    await copy.writeAsBytes(
      img.encodeJpg(img.bakeOrientation(decoded), quality: 95),
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
      owned = await compute(prepareUploadedPhoto, selected.path);
      if (!mounted) return;
      final old = widget.session.pathFor(view);
      widget.session.setPath(
        view,
        owned!,
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
