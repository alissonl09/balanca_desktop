import 'capture_models.dart';
import 'configured_digits.dart';

class WeightRecognitionRules {
  const WeightRecognitionRules({
    required this.minimum,
    required this.maximum,
    this.expectedDecimalPlaces,
  });
  final double minimum, maximum;
  final int? expectedDecimalPlaces;
  WeightOcrResult validate(WeightOcrResult reading) {
    if (!minimum.isFinite ||
        !maximum.isFinite ||
        minimum < 0 ||
        minimum > maximum) {
      return reading.copyWith(failure: 'OCR_FAIXA_INVALIDA');
    }
    if (reading.diagnostics['configuredDigits'] == true) {
      final value = reading.diagnostics['interpretedValue'];
      if (value is num &&
          (!value.isFinite || value < minimum || value > maximum)) {
        return reading.copyWith(
          failure: 'OCR_FORA_DA_FAIXA',
          diagnostics: {...reading.diagnostics, 'numericAndRangeValid': false},
        );
      }
      return reading;
    }
    if (!reading.success) return reading;
    if (!reading.weight!.isFinite ||
        reading.weight! < minimum ||
        reading.weight! > maximum ||
        reading.weight! < 0) {
      return reading.copyWith(failure: 'OCR_FORA_DA_FAIXA');
    }
    final text = reading.recognitionKey;
    final places = text.contains('.') ? text.length - text.indexOf('.') - 1 : 0;
    if (expectedDecimalPlaces != null && places != expectedDecimalPlaces) {
      return reading.copyWith(failure: 'OCR_CASAS_DECIMAIS_DIVERGENTES');
    }
    return reading;
  }
}

/// Bounded window of independent photographs. A vote includes its separator
/// and precision. Weak/invalid frames never vote and never gain confidence.
class WeightTemporalConsensus {
  WeightTemporalConsensus({
    this.requiredReadings = 3,
    this.digitsMode = false,
  }) {
    if (requiredReadings < 2 || requiredReadings > 5) {
      throw ArgumentError.value(requiredReadings);
    }
  }
  final int requiredReadings;
  final bool digitsMode;
  int stableReadings = 0;
  final _window = <WeightOcrResult>[];
  final _digits = ConfiguredDigitsConsensus();
  int get maximumFrames => digitsMode ? 5 : requiredReadings + 2;
  WeightOcrResult observe(WeightOcrResult result) {
    if (digitsMode || result.diagnostics['configuredDigits'] == true) {
      final observation = _digits.observe(result);
      stableReadings = _digits.stableReadings;
      return observation;
    }
    _window.add(result);
    if (_window.length > maximumFrames) _window.removeAt(0);
    final matching = _window
        .where((r) => r.success && r.recognitionKey == result.recognitionKey)
        .toList();
    stableReadings = result.success ? matching.length : 0;
    final consecutiveTail =
        _window.length >= 2 &&
        _window[_window.length - 2].success &&
        _window[_window.length - 2].recognitionKey == result.recognitionKey;
    final strong =
        stableReadings >= requiredReadings &&
        stableReadings / _window.length >= .8 &&
        consecutiveTail;
    final minimum = matching.isEmpty
        ? result.confidence
        : matching
              .map((r) => r.candidateConfidence)
              .reduce((a, b) => a < b ? a : b);
    return result.copyWith(
      consensusReadings: strong ? stableReadings : 0,
      requiredReadings: requiredReadings,
      temporalConfidence: strong
          ? minimum.clamp(0, 1 - .02 * (_window.length - stableReadings))
          : 1,
      diagnostics: {
        ...result.diagnostics,
        'temporalVotes': stableReadings,
        'temporalFrames': _window.length,
        'temporalAgreement': stableReadings / _window.length,
      },
      failure:
          result.success &&
              !strong &&
              _window.length > 1 &&
              _window.any(
                (r) => r.success && r.recognitionKey != result.recognitionKey,
              )
          ? 'OCR_LEITURA_INSTAVEL'
          : null,
    );
  }
}
