import 'dart:io';

import 'package:image/image.dart' as img;

class LocalQualityResult {
  const LocalQualityResult({
    required this.accepted,
    required this.blurScore,
    required this.exposureMean,
    this.reason,
  });

  final bool accepted;
  final double blurScore;
  final double exposureMean;
  final String? reason;
}

class ImageQualityService {
  const ImageQualityService({
    this.minimumWidth = 480,
    this.minimumHeight = 480,
    this.minimumBlurVariance = 28,
  });

  final int minimumWidth;
  final int minimumHeight;
  final double minimumBlurVariance;

  Future<LocalQualityResult> inspect(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const LocalQualityResult(
        accepted: false,
        blurScore: 0,
        exposureMean: 0,
        reason: 'The camera image could not be decoded.',
      );
    }
    final oriented = img.bakeOrientation(decoded);
    if (oriented.width < minimumWidth || oriented.height < minimumHeight) {
      return LocalQualityResult(
        accepted: false,
        blurScore: 0,
        exposureMean: 0,
        reason: 'Resolution is too low (${oriented.width}x${oriented.height}).',
      );
    }
    final sample = img.copyResize(
      oriented,
      width: oriented.width > 480 ? 480 : oriented.width,
    );
    final luminance = List<double>.filled(sample.width * sample.height, 0);
    var total = 0.0;
    var dark = 0;
    var bright = 0;
    for (final pixel in sample) {
      final value = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      luminance[pixel.y * sample.width + pixel.x] = value;
      total += value;
      if (value <= 15) dark += 1;
      if (value >= 245) bright += 1;
    }
    final exposure = total / luminance.length;
    final clipping = (dark > bright ? dark : bright) / luminance.length;
    var laplacianTotal = 0.0;
    var laplacianSquared = 0.0;
    var count = 0;
    for (var y = 1; y < sample.height - 1; y += 1) {
      for (var x = 1; x < sample.width - 1; x += 1) {
        final center = luminance[y * sample.width + x];
        final value =
            luminance[(y - 1) * sample.width + x] +
            luminance[(y + 1) * sample.width + x] +
            luminance[y * sample.width + x - 1] +
            luminance[y * sample.width + x + 1] -
            4 * center;
        laplacianTotal += value;
        laplacianSquared += value * value;
        count += 1;
      }
    }
    final mean = laplacianTotal / count;
    final blurVariance = laplacianSquared / count - mean * mean;
    String? reason;
    if (blurVariance < minimumBlurVariance) {
      reason = 'Image is blurry. Hold steady and retake it.';
    } else if (clipping > 0.88 || exposure < 25) {
      reason = 'Lighting is too dark. Move to a brighter position.';
    } else if (exposure > 235) {
      reason = 'Image is overexposed. Avoid direct glare.';
    }
    return LocalQualityResult(
      accepted: reason == null,
      blurScore: blurVariance,
      exposureMean: exposure,
      reason: reason,
    );
  }
}

