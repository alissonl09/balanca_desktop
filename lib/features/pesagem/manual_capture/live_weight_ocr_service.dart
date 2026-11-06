import 'dart:isolate';
import 'dart:typed_data';

import 'capture_models.dart';
import 'decimal_detector.dart';
import 'seven_segment_preprocessor.dart';
import 'weight_ocr_service.dart';

/// Operational loop: exactly two eng/PSM7 passes on one native ROI. The slower
/// model/scale cascade remains available for offline calibration and replay.
class LiveWeightOcrService implements WeightOcrService {
  LiveWeightOcrService({OcrVariantEngine? engine})
    : engine =
          engine ??
          TesseractWeightOcrService(
            processTimeout: const Duration(milliseconds: 900),
          );
  final OcrVariantEngine engine;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    final clock = Stopwatch()..start();
    final prepared = await Isolate.run(
      () => (
        prepareSevenSegmentVariants(image, quick: true),
        analyzeDisplayGeometry(image),
      ),
    );
    final attempts = <OcrAttempt>[];
    for (final variant in prepared.$1.entries) {
      final raw = await engine.recognizeVariant(
        variant.value,
        numericOnly: true,
      );
      final result = reconcileVisualDecimal(raw, prepared.$2).copyWith(
        diagnostics: {
          ...prepared.$2.toJson(),
          'requestedScale': 2,
          'effectiveScale': effectiveSevenSegmentScale(
            prepared.$2.width,
            prepared.$2.height,
            2,
          ),
          'mode': 'live',
          'thresholdMethod': variant.key.split('_').first,
        },
      );
      attempts.add(OcrAttempt(variant.key, variant.value, result));
      if ([
        'OCR_TIMEOUT',
        'OCR_ENGINE_INDISPONIVEL',
        'OCR_ENGINE_ERRO',
        'OCR_MODELO_INDISPONIVEL',
      ].contains(raw.error)) {
        break;
      }
    }
    return selectConsistentOcr(attempts)
        .copyWith(elapsedMs: clock.elapsedMilliseconds);
  }
}
