import 'dart:typed_data';

import 'capture_models.dart';
import 'weight_ocr_service.dart';
import 'weight_recognition_validation.dart';

/// Runtime-neutral inference boundary. Input is the clean, rectified ROI.
abstract interface class WeightRecognitionEngine implements WeightOcrService {}

class DigitDetection {
  const DigitDetection(
    this.classId,
    this.x,
    this.y,
    this.width,
    this.height,
    this.confidence,
  );
  final int classId; // 0..9, 10 = decimal_point
  final double x, y, width, height, confidence; // normalized ROI coordinates
  Map<String, num> toJson() => {
    'classId': classId,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'confidence': confidence,
  };
  bool get valid =>
      classId >= 0 &&
      classId <= 10 &&
      [x, y, width, height, confidence].every((v) => v.isFinite) &&
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1.000001 &&
      y + height <= 1.000001 &&
      confidence >= 0 &&
      confidence <= 1;
}

abstract interface class LocalDigitModel {
  Future<bool> get available;

  /// Adapter must undo letterboxing, apply NMS and report completeness.
  Future<DigitModelOutput> detect(Uint8List rectifiedRoi);
}

class DigitModelOutput {
  const DigitModelOutput(this.detections, {required this.complete});
  final List<DigitDetection> detections;

  /// False for clipped displays, unresolved boxes or incomplete detections.
  final bool complete;
}

class CustomModelEngine implements WeightRecognitionEngine {
  const CustomModelEngine({
    this.model,
    this.minimum = 0,
    this.maximum = 150000,
  });
  final LocalDigitModel? model;
  final double minimum, maximum;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    final clock = Stopwatch()..start();
    try {
      if (model == null || !await model!.available) {
        return const WeightOcrResult(error: 'CUSTOM_MODEL_UNAVAILABLE');
      }
      final output = await model!.detect(image);
      return reconstructDetections(
        output,
        minimum: minimum,
        maximum: maximum,
      ).copyWith(elapsedMs: clock.elapsedMilliseconds);
    } catch (_) {
      return const WeightOcrResult(error: 'CUSTOM_MODEL_ERROR');
    }
  }
}

WeightOcrResult reconstructDetections(
  DigitModelOutput output, {
  double minimum = 0,
  double maximum = 150000,
}) {
  final boxes = [...output.detections]..sort((a, b) => a.x.compareTo(b.x));
  WeightOcrResult fail(String code) => WeightOcrResult(
    error: code,
    strategy: 'custom_model',
    characterPositions: boxes.map((b) => b.toJson()).toList(),
  );
  if (!output.complete || boxes.isEmpty) return fail('CUSTOM_INCOMPLETE');
  if (boxes.any((b) => !b.valid)) return fail('CUSTOM_INVALID_BOX');
  if (boxes.any((b) => b.confidence < WeightOcrResult.threshold)) {
    return fail('CUSTOM_LOW_CONFIDENCE');
  }
  for (var i = 1; i < boxes.length; i++) {
    // Ambiguous overlapping detections must be resolved by the adapter.
    if (boxes[i].x < boxes[i - 1].x + boxes[i - 1].width) {
      return fail('CUSTOM_OVERLAPPING_BOXES');
    }
  }
  final sequence = boxes
      .map((b) => b.classId == 10 ? '.' : '${b.classId}')
      .join();
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(sequence)) {
    return fail('CUSTOM_INVALID_SEQUENCE');
  }
  final integer = double.tryParse(sequence.split('.').first);
  if (integer == null || !integer.isFinite) {
    return fail('CUSTOM_INVALID_WEIGHT');
  }
  return WeightRecognitionRules(minimum: minimum, maximum: maximum).validate(
    WeightOcrResult(
      rawText: sequence,
      normalizedText: sequence,
      weight: integer,
      confidence: boxes
          .map((b) => b.confidence)
          .reduce((a, b) => a < b ? a : b),
      decimalDetected: sequence.contains('.'),
      decimalPosition: sequence.contains('.') ? sequence.indexOf('.') : null,
      strategy: 'custom_model',
      characterPositions: boxes.map((b) => b.toJson()).toList(),
    ),
  );
}

/// Opt-in cascade; not installed in the operational flow until qualification.
class WeightEngineCascade implements WeightRecognitionEngine {
  const WeightEngineCascade(
    this.engines, {
    this.minimum = 0,
    this.maximum = 150000,
  });
  final List<WeightOcrService> engines;
  final double minimum, maximum;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    final failures = <String>[];
    for (final engine in engines) {
      try {
        final result = WeightRecognitionRules(
          minimum: minimum,
          maximum: maximum,
        ).validate(await engine.recognize(image));
        if (result.success) {
          return result.copyWith(
            diagnostics: {...result.diagnostics, 'fallbackFailures': failures},
          );
        }
        failures.add(result.error ?? 'LOW_CONFIDENCE');
      } catch (_) {
        failures.add('ENGINE_ERROR');
      }
    }
    return WeightOcrResult(
      error: 'ALL_ENGINES_FAILED',
      diagnostics: {'fallbackFailures': failures},
    );
  }
}
