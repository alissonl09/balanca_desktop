import 'dart:typed_data';

import 'capture_models.dart';
import 'configured_digits_service.dart';
import 'seven_segment_recognition_engine.dart';
import 'seven_segment_ocr_service.dart';
import 'weight_ocr_service.dart';
import 'weight_recognition_validation.dart';

/// UI-facing cascade. Temporal acceptance stays with the multi-frame reader.
class WeightRecognitionService implements WeightOcrService {
  WeightRecognitionService({
    required this.configuration,
    this.primary,
    WeightOcrService? fallback,
  }) : fallback =
           fallback ??
           SevenSegmentWeightOcrService(
             whitelist: '0123456789.',
             budget: const Duration(seconds: 2),
             engine: TesseractWeightOcrService(
               processTimeout: const Duration(milliseconds: 900),
             ),
             generic: TesseractWeightOcrService(
               processTimeout: const Duration(milliseconds: 900),
             ),
           );
  final WebcamConfiguration Function() configuration;
  final WeightOcrService? primary;
  final WeightOcrService fallback;
  late final _digits = ConfiguredDigitsService(configuration);
  @override
  Future<WeightRecognitionResult> recognize(Uint8List image) async {
    final config = configuration();
    if (config.decimalPlaces != null) return _digits.recognize(image);
    final rules = WeightRecognitionRules(
      minimum: config.minimumWeight,
      maximum: config.maximumWeight,
      expectedDecimalPlaces: config.expectedDecimalPlaces,
    );
    WeightOcrResult geometric;
    try {
      geometric = !config.region.calibrated
          ? const WeightOcrResult(error: 'SEGMENT_ROI_NOT_CALIBRATED')
          : rules.validate(
              await (primary ??
                      SevenSegmentRecognitionEngine(
                        profile: config.displayProfile,
                        diagnostics: config.diagnostics,
                      ))
                  .recognize(image),
            );
    } catch (_) {
      geometric = const WeightOcrResult(error: 'SEGMENT_ENGINE_ERROR');
    }
    if (geometric.success) {
      return geometric.copyWith(weight: geometric.weight!.truncateToDouble());
    }
    if (geometric.error == 'SEGMENT_NEGATIVE') return geometric;
    WeightOcrResult secondary;
    try {
      secondary = rules.validate(await fallback.recognize(image));
    } catch (_) {
      secondary = const WeightOcrResult(error: 'OCR_ENGINE_ERRO');
    }
    return secondary.copyWith(
      weight: secondary.weight?.truncateToDouble(),
      strategy: 'Tesseract fallback: ${secondary.strategy}',
      attempts: [...geometric.attempts, ...secondary.attempts],
      diagnostics: {
        ...secondary.diagnostics,
        'profile': config.displayProfile,
        'primaryFailure': geometric.error ?? 'SEGMENT_LOW_CONFIDENCE',
        'primaryDiagnostics': geometric.diagnostics,
      },
    );
  }
}
