import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'capture_models.dart';

class ProcessedCapture {
  const ProcessedCapture(this.evidence, this.ocrInput);
  final Uint8List evidence, ocrInput;
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
  final decoded = img.decodeImage(photo.bytes);
  if (decoded == null || decoded.width < 64 || decoded.height < 64) {
    throw const CaptureFailure(
      'IMAGEM_INVALIDA',
      'Imagem inválida. Capture novamente.',
    );
  }
  final image = img.bakeOrientation(decoded);
  final crop = img.copyCrop(
    image,
    x: (image.width * region.left).round(),
    y: (image.height * region.top).round(),
    width: (image.width * region.width).round(),
    height: (image.height * region.height).round(),
  );
  final processed = img.grayscale(crop);
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
    Uint8List.fromList(img.encodePng(processed)),
  );
}
