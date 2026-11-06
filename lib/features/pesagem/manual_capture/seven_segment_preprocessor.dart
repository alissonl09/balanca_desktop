import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

double effectiveSevenSegmentScale(int width, int height, int scale) => math.max(
  1.0,
  math.min(scale.toDouble(), math.min(1600 / width, 600 / height)),
);

/// Operates ONLY on the clean configured ROI. Morphology is an alternative,
/// never a mandatory transform, and is never applied to the photograph.
Map<String, Uint8List> prepareSevenSegmentVariants(
  Uint8List bytes, {
  int scale = 2,
  bool experimental = false,
  bool quick = false,
}) {
  if (scale < 2 || scale > 4) throw ArgumentError.value(scale, 'scale');
  final source = img.decodeImage(bytes);
  if (source == null) throw const FormatException('Invalid ROI');
  final factor = effectiveSevenSegmentScale(source.width, source.height, scale);
  final resized = img.copyResize(
    source,
    width: math.max(1, (source.width * factor).round()),
    height: math.max(1, (source.height * factor).round()),
    interpolation: img.Interpolation.cubic,
  );
  final gray = img.grayscale(resized);
  final contrast = img.normalize(img.Image.from(gray), min: 0, max: 255);
  var border = 0.0, count = 0;
  for (var x = 0; x < contrast.width; x++) {
    border +=
        contrast.getPixel(x, 0).r + contrast.getPixel(x, contrast.height - 1).r;
    count += 2;
  }
  for (var y = 0; y < contrast.height; y++) {
    border +=
        contrast.getPixel(0, y).r + contrast.getPixel(contrast.width - 1, y).r;
    count += 2;
  }
  final normalized = border / count < 128
      ? img.invert(img.Image.from(contrast))
      : img.Image.from(contrast);
  final binary = _binarize(normalized, _otsu(normalized));
  final variants = <String, img.Image>{
    'gray_contrast_${scale}x': normalized,
    'otsu_${scale}x': binary,
    if (!quick) 'adaptive_${scale}x': _adaptive(normalized),
    if (!quick) 'global128_${scale}x': _binarize(normalized, 128),
    if (!quick) 'inverse_${scale}x': img.invert(img.Image.from(normalized)),
    if (!quick)
      'close1_${scale}x': _morph(_morph(binary, dilate: true), dilate: false),
    if (experimental) ...{
      'denoise_sharpen_${scale}x': img.convolution(
        img.gaussianBlur(img.Image.from(normalized), radius: 1),
        filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
      ),
      'dilate1_${scale}x': _morph(binary, dilate: true),
      'erode1_${scale}x': _morph(binary, dilate: false),
    },
  };
  // Small white border helps PSM 7/8/13 without enlarging the ROI itself.
  return variants.map((name, image) {
    final padded = img.Image(
      width: image.width + 20,
      height: image.height + 20,
    );
    img.fill(padded, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(padded, image, dstX: 10, dstY: 10);
    return MapEntry(name, Uint8List.fromList(img.encodePng(padded)));
  });
}

int _otsu(img.Image image) {
  final histogram = List<int>.filled(256, 0);
  for (final p in image) {
    histogram[p.r.toInt()]++;
  }
  final total = image.width * image.height;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * histogram[i];
  }
  var count = 0, threshold = 128;
  var subtotal = 0.0, best = -1.0;
  for (var i = 0; i < 255; i++) {
    count += histogram[i];
    subtotal += i * histogram[i];
    if (count == 0 || count == total) continue;
    final difference = subtotal / count - (sum - subtotal) / (total - count);
    final variance = count * (total - count) * difference * difference;
    if (variance > best) {
      best = variance;
      threshold = i;
    }
  }
  return threshold;
}

img.Image _binarize(img.Image input, int threshold) {
  final output = img.Image.from(input);
  for (final p in output) {
    final value = p.r > threshold ? 255 : 0;
    p.setRgb(value, value, value);
  }
  return output;
}

/// Local mean threshold using an integral image: linear work, bounded memory.
img.Image _adaptive(img.Image input) {
  final w = input.width, h = input.height, stride = w + 1;
  final sums = Float64List(stride * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0.0;
    for (var x = 0; x < w; x++) {
      row += input.getPixel(x, y).r;
      sums[(y + 1) * stride + x + 1] = sums[y * stride + x + 1] + row;
    }
  }
  final output = img.Image.from(input);
  for (final p in output) {
    final x1 = math.max(0, p.x - 15), x2 = math.min(w, p.x + 16);
    final y1 = math.max(0, p.y - 15), y2 = math.min(h, p.y + 16);
    final mean =
        (sums[y2 * stride + x2] -
            sums[y1 * stride + x2] -
            sums[y2 * stride + x1] +
            sums[y1 * stride + x1]) /
        ((x2 - x1) * (y2 - y1));
    final value = p.r < mean - 8 ? 0 : 255;
    p.setRgb(value, value, value);
  }
  return output;
}

/// Dark foreground, radius one pixel. Closing bridges small gaps only.
img.Image _morph(img.Image input, {required bool dilate}) {
  final output = img.Image.from(input);
  for (final p in output) {
    var value = dilate ? 255 : 0;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final x = (p.x + dx).clamp(0, input.width - 1);
        final y = (p.y + dy).clamp(0, input.height - 1);
        final v = input.getPixel(x, y).r.toInt();
        value = dilate ? math.min(value, v) : math.max(value, v);
      }
    }
    p.setRgb(value, value, value);
  }
  return output;
}
