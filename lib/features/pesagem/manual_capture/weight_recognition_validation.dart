import 'capture_models.dart';

class WeightRecognitionRules {
  const WeightRecognitionRules({required this.minimum, required this.maximum});
  final double minimum, maximum;
  WeightOcrResult validate(WeightOcrResult reading) {
    if (!minimum.isFinite ||
        !maximum.isFinite ||
        minimum < 0 ||
        minimum > maximum) {
      return reading.copyWith(failure: 'OCR_FAIXA_INVALIDA');
    }
    // An untrusted candidate is not a validated weight. Preserve the OCR
    // failure (e.g. a hallucinated minus with confidence zero) before range.
    if (!reading.success) {
      return reading;
    }
    if (reading.weight != null &&
        (!reading.weight!.isFinite ||
            reading.weight! < minimum ||
            reading.weight! > maximum ||
            reading.weight! < 0)) {
      return reading.copyWith(failure: 'OCR_FORA_DA_FAIXA');
    }
    return reading;
  }
}

/// Independent photographs, not votes from multiple transforms of one photo.
/// Fail fast on disagreement; never take a majority over changing segments.
class WeightTemporalConsensus {
  WeightTemporalConsensus({this.requiredReadings = 3}) {
    if (requiredReadings < 2 || requiredReadings > 5) {
      throw ArgumentError.value(requiredReadings);
    }
  }
  final int requiredReadings;
  int stableReadings = 0;
  double? _previous;
  double _minimumConfidence = 1;
  WeightOcrResult observe(WeightOcrResult result) {
    if (!result.success) {
      stableReadings = 0;
      _previous = null;
      _minimumConfidence = 1;
      return result.copyWith(
        consensusReadings: 0,
        requiredReadings: requiredReadings,
      );
    }
    if (_previous != null && _previous != result.weight) {
      stableReadings = 0;
      _previous = null;
      _minimumConfidence = 1;
      return result.copyWith(
        failure: 'OCR_LEITURA_INSTAVEL',
        consensusReadings: 0,
        requiredReadings: requiredReadings,
      );
    }
    _previous = result.weight;
    stableReadings++;
    if (result.confidence < _minimumConfidence) {
      _minimumConfidence = result.confidence;
    }
    return WeightOcrResult(
      rawText: result.rawText,
      weight: result.weight,
      confidence: _minimumConfidence,
      error: result.error,
      attempts: result.attempts,
      strategy: result.strategy,
      engineMessage: result.engineMessage,
      model: result.model,
      psm: result.psm,
      elapsedMs: result.elapsedMs,
      consensusReadings: stableReadings,
      requiredReadings: requiredReadings,
    );
  }
}
