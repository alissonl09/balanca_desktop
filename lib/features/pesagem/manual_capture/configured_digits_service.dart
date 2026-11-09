import 'dart:typed_data';

import 'capture_models.dart';
import 'configured_digits.dart';
import 'persistent_digits_ocr.dart';
import 'seven_segment_recognition_engine.dart';
import 'weight_ocr_service.dart';

class ConfiguredDigitsService implements WeightOcrService {
  ConfiguredDigitsService(this.configuration);
  final WebcamConfiguration Function() configuration;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    final config = configuration();
    var reading = await PersistentDigitsOcr.shared.recognize(image);
    if (reading.error != null && config.region.calibrated) {
      final fallback = await SevenSegmentRecognitionEngine(
        profile: config.displayProfile,
        diagnostics: config.diagnostics,
      ).recognize(image);
      // A rejected geometric result never becomes a numeric candidate.
      if (fallback.success) {
        reading = fallback;
      } else {
        return reading.copyWith(
          diagnostics: {
            ...reading.diagnostics,
            'geometricFailure': fallback.error,
          },
        );
      }
    }
    if (reading.error != null) return reading;
    return configuredDigits(
      reading.rawText,
      reading.confidence,
      config.decimalPlaces!,
      minimum: config.minimumWeight,
      maximum: config.maximumWeight,
      strategy: reading.strategy,
      elapsedMs: reading.elapsedMs,
      diagnostics: reading.diagnostics,
    ).copyWith(
      model: reading.model,
      psm: reading.psm,
      attempts: reading.attempts,
    );
  }
}
