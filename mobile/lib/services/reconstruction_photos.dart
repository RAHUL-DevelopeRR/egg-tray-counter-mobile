import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

class PreparedPair {
  PreparedPair(this.paths, this.metadata, this.ownedDirectory);
  final List<String> paths;
  final Map<String, dynamic> metadata;
  final String? ownedDirectory;
  Future<void> dispose() async {
    if (ownedDirectory != null) {
      await Directory(ownedDirectory!).delete(recursive: true);
    }
  }
}

Future<PreparedPair> prepareReconstructionPair(List<String> paths) async {
  if (paths.length != 2) throw const FormatException('Choose two photos');
  final bytes = <Uint8List>[];
  final images = <img.Image>[];
  final missingExif = <bool>[];
  for (final path in paths) {
    final file = File(path);
    if (await file.length() > 32 * 1024 * 1024) {
      throw const FormatException('Choose originals smaller than 32 MB');
    }
    final raw = await file.readAsBytes();
    final decoder = img.findDecoderForData(raw);
    if (decoder is! img.JpegDecoder && decoder is! img.PngDecoder) {
      throw const FormatException('Use JPEG or PNG photos');
    }
    final info = decoder!.startDecode(raw);
    if (info == null || info.width * info.height > 40000000) {
      throw const FormatException('Choose photos of at most 40 megapixels');
    }
    final image = decoder.decodeFrame(0);
    if (image == null) throw const FormatException('Cannot read this photo');
    missingExif.add(image.exif.isEmpty);
    bytes.add(raw);
    images.add(img.bakeOrientation(image));
  }
  if (listEquals(bytes[0], bytes[1])) {
    throw const FormatException('Choose two different overlapping photos');
  }
  final width = images[0].width, height = images[0].height;
  if (images[1].width != width || images[1].height != height) {
    throw const FormatException(
      'Both photos must have the same pixel dimensions',
    );
  }
  final metadata = <String, dynamic>{
    'original_width': width,
    'original_height': height,
    'exif_missing': missingExif,
    'resized': false,
    'source': 'selected_or_captured_photos',
  };
  if (width * height <= 12000000 && bytes.every((b) => b.length <= 2000000)) {
    return PreparedPair(paths, metadata, null);
  }
  var factor = math.min(1.0, math.sqrt(12000000 / (width * height)));
  final output = <Uint8List>[];
  int targetWidth, targetHeight;
  do {
    targetWidth = math.max(1, (width * factor).floor());
    targetHeight = math.max(1, (height * factor).floor());
    output.clear();
    for (final image in images) {
      final resized = img.copyResize(
        image,
        width: targetWidth,
        height: targetHeight,
      );
      output.add(img.encodeJpg(resized, quality: 92));
    }
    factor *= .85;
  } while (output.any((b) => b.length > 2000000));
  final directory = await Directory(
    '${Directory.systemTemp.path}/reconstruct-${const Uuid().v4()}',
  ).create();
  try {
    final copies = <String>[];
    for (var i = 0; i < 2; i++) {
      final file = File('${directory.path}/$i.jpg');
      await file.writeAsBytes(output[i]);
      copies.add(file.path);
    }
    metadata.addAll({
      'resized': true,
      'width': targetWidth,
      'height': targetHeight,
      'jpeg_quality': 92,
      'scale_x': targetWidth / width,
      'scale_y': targetHeight / height,
    });
    return PreparedPair(copies, metadata, directory.path);
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  }
}
