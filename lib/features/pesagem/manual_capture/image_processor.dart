import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'capture_models.dart';
import 'dominant_weight_line.dart';
import 'image_normalizer.dart';

class ProcessedCapture {
  const ProcessedCapture(this.evidence, this.ocrInput, {this.original});
  final Uint8List evidence, ocrInput;
  final Uint8List? original;
}

abstract interface class CaptureImageProcessor {
  Future<ProcessedCapture> process(CapturedPhoto photo, DisplayRegion region);
}

class LocalCaptureImageProcessor implements CaptureImageProcessor {
  @override
  Future<ProcessedCapture> process(CapturedPhoto photo, DisplayRegion region) =>
      Isolate.run(() => processCapture(photo, region));
}

/// OCR uses the original crop, never the timestamp drawn on the evidence.
ProcessedCapture processCapture(CapturedPhoto photo, DisplayRegion region) {
  final image = normalizeCameraImage(photo);
  if (!region.valid) {
    throw const CaptureFailure('ROI_INVALIDA', 'Ajuste a região do visor.');
  }
  final crop = img.copyCrop(
    image,
    x: (image.width * region.left).round(),
    y: (image.height * region.top).round(),
    width: (image.width * region.width).round(),
    height: (image.height * region.height).round(),
  );
  final evidence = img.copyResize(
    image,
    width: image.width < 640 ? 640 : image.width,
  );
  img.fillRect(
    evidence,
    x1: 0,
    y1: evidence.height - 42,
    x2: evidence.width - 1,
    y2: evidence.height - 1,
    color: img.ColorRgb8(0, 0, 0),
  );
  img.drawString(
    evidence,
    localTimestamp(photo.capturedAt),
    font: img.arial24,
    x: 10,
    y: evidence.height - 34,
    color: img.ColorRgb8(255, 255, 255),
  );
  return ProcessedCapture(
    Uint8List.fromList(img.encodeJpg(evidence, quality: 95)),
    Uint8List.fromList(img.encodePng(crop)),
    original: Uint8List.fromList(img.encodePng(image)),
  );
}

/// Bounded variants, computed off the UI isolate. No changes to evidence.
Map<String, Uint8List> prepareOcrVariants(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Invalid OCR image');
  final line = isolateDominantWeightLine(decoded);
  // Excessive enlargement also harms LSTM recognition (e.g. a 160 px glyph).
  // A tightly framed display line targets ~60 px glyphs with room for margins.
  final targetHeight = identical(line, decoded) ? 160 : 100;
  final scale = min(4.0, min(1200 / line.width, targetHeight / line.height));
  final crop = img.copyResize(
    line,
    width: (line.width * scale).round(),
    height: (line.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );
  final gray = img.grayscale(crop);
  final contrast = img.normalize(img.Image.from(gray), min: 0, max: 255);
  // Bright green/cyan IND displays become dark glyphs on a light background.
  // Keep a separate normal-polarity strategy for printed photographs.
  final inverse = img.invert(img.Image.from(contrast));
  final threshold = img.Image.from(inverse);
  for (final pixel in threshold) {
    final value = pixel.r > 128 ? 255 : 0;
    pixel.setRgb(value, value, value);
  }
  Uint8List png(img.Image image) => Uint8List.fromList(img.encodePng(image));
  final prefix = identical(line, decoded) ? '' : 'dominant_line_';
  return {
    '${prefix}grayscale_contrast': png(contrast),
    '${prefix}inverted_contrast': png(inverse),
    '${prefix}inverted_threshold_128': png(threshold),
  };
}
