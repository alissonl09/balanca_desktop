import 'dart:typed_data';

import 'capture_models.dart';
import 'image_processor.dart';
import 'weight_ocr_service.dart';
import 'weight_recognition_validation.dart';

class CapturedImageAnalysis {
  const CapturedImageAnalysis(this.capture, this.result);
  final ProcessedCapture capture;
  final WeightOcrResult result;
}

/// Shared by camera, explicit camera test and file CLI. Persistence is performed
/// by the caller BEFORE invoking this function. Only detached bytes are passed
/// to processors and recognizers; the stored original is never an OCR target.
Future<CapturedImageAnalysis> analyzeCapturedImage(
  CapturedPhoto original, {
  required WebcamConfiguration configuration,
  required CaptureImageProcessor processor,
  required WeightOcrService recognition,
}) async {
  final copy = CapturedPhoto(
    Uint8List.fromList(original.bytes),
    original.capturedAt,
    mirrorHorizontally: original.mirrorHorizontally,
  );
  final capture = await processor.process(copy, configuration.region);
  final reading = await recognition.recognize(
    Uint8List.fromList(capture.ocrInput),
  );
  final result = WeightRecognitionRules(
    minimum: configuration.minimumWeight,
    maximum: configuration.maximumWeight,
  ).validate(reading);
  return CapturedImageAnalysis(
    capture,
    result.copyWith(
      diagnostics: {
        ...result.diagnostics,
        ...capture.dimensions,
        'analysisKind': 'snapshot',
        'consensusScope': 'pipelines',
        'temporalFrames': 1,
      },
    ),
  );
}
