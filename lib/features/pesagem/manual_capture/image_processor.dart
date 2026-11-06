import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'capture_models.dart';
import 'dominant_weight_line.dart';
import 'image_normalizer.dart';

class ProcessedCapture {
  const ProcessedCapture(
    this.evidence,
    this.ocrInput, {
    this.original,
    this.frameWidth = 0,
    this.frameHeight = 0,
    this.roiWidth = 0,
    this.roiHeight = 0,
    this.ocrWidth = 0,
    this.ocrHeight = 0,
  });
  final Uint8List evidence, ocrInput;
  final Uint8List? original;
  final int frameWidth, frameHeight, roiWidth, roiHeight, ocrWidth, ocrHeight;
  Map<String, int> get dimensions => {
    'frameWidth': frameWidth,
    'frameHeight': frameHeight,
    'roiWidth': roiWidth,
    'roiHeight': roiHeight,
    'ocrWidth': ocrWidth,
    'ocrHeight': ocrHeight,
  };
}

abstract interface class CaptureImageProcessor {
  Future<ProcessedCapture> process(CapturedPhoto photo, DisplayRegion region);
}

abstract interface class EvidenceOnlyImageProcessor {
  Future<ProcessedCapture> processEvidence(CapturedPhoto photo);
}

abstract interface class OcrFrameImageProcessor {
  Future<ProcessedCapture> processOcrFrame(
    CapturedPhoto photo,
    DisplayRegion region,
  );
}

class LocalCaptureImageProcessor
    implements
        CaptureImageProcessor,
        EvidenceOnlyImageProcessor,
        OcrFrameImageProcessor {
  @override
  Future<ProcessedCapture> process(CapturedPhoto photo, DisplayRegion region) =>
      Isolate.run(() => processCapture(photo, region));
  @override
  Future<ProcessedCapture> processEvidence(CapturedPhoto photo) => Isolate.run(
    () => processCapture(photo, const DisplayRegion(), evidenceOnly: true),
  );
  @override
  Future<ProcessedCapture> processOcrFrame(
    CapturedPhoto photo,
    DisplayRegion region,
  ) => Isolate.run(() => processCapture(photo, region, ocrOnly: true));
}

/// OCR uses the original crop, never the timestamp drawn on the evidence.
ProcessedCapture processCapture(
  CapturedPhoto photo,
  DisplayRegion region, {
  bool evidenceOnly = false,
  bool ocrOnly = false,
}) {
  final image = normalizeCameraImage(photo);
  final evidence = ocrOnly
      ? Uint8List(0)
      : _stampEvidence(image, photo.capturedAt);
  if (evidenceOnly) {
    return ProcessedCapture(
      evidence,
      Uint8List(0),
      frameWidth: image.width,
      frameHeight: image.height,
    );
  }
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
  // Optional station calibration, applied only to the clean ROI. Expanded
  // bounds and cubic interpolation preserve corners and the decimal point.
  if (region.deskewDegrees != 0) {
    final corner = crop.getPixel(0, 0);
    crop.backgroundColor = img.ColorRgb8(
      corner.r.toInt(),
      corner.g.toInt(),
      corner.b.toInt(),
    );
  }
  final ocrCrop = region.deskewDegrees == 0
      ? crop
      : img.copyRotate(
          crop,
          angle: -region.deskewDegrees,
          interpolation: img.Interpolation.cubic,
        );
  return ProcessedCapture(
    evidence,
    Uint8List.fromList(img.encodePng(ocrCrop)),
    original: ocrOnly ? null : Uint8List.fromList(img.encodePng(image)),
    frameWidth: image.width,
    frameHeight: image.height,
    roiWidth: crop.width,
    roiHeight: crop.height,
    ocrWidth: ocrCrop.width,
    ocrHeight: ocrCrop.height,
  );
}

Uint8List _stampEvidence(img.Image image, DateTime capturedAt) {
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
    localTimestamp(capturedAt),
    font: img.arial24,
    x: 10,
    y: evidence.height - 34,
    color: img.ColorRgb8(255, 255, 255),
  );
  return Uint8List.fromList(img.encodeJpg(evidence, quality: 95));
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
