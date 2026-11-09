import 'dart:math' as math;

import 'capture_models.dart';

/// No visual decimal inference. Separators may only be a single internal mark.
WeightOcrResult configuredDigits(
  String raw,
  double ocrConfidence,
  int places, {
  double minimum = 0,
  double maximum = 100000,
  String strategy = 'digits',
  int elapsedMs = 0,
  Map<String, Object?> diagnostics = const {},
}) {
  final text = raw.trim();
  final digits = text.replaceAll(RegExp(r'[.,]'), '');
  String? failure;
  if (places < 0 || places > 3) failure = 'OCR_DECIMAL_CONFIG_INVALID';
  if (!RegExp(r'^\d{1,10}([.,]\d{1,3})?$').hasMatch(text) ||
      digits.length > 10) {
    failure = 'OCR_FORMATO_INVALIDO';
  }
  final value = failure == null
      ? int.parse(digits) / math.pow(10, places)
      : null;
  if (!minimum.isFinite ||
      !maximum.isFinite ||
      minimum < 0 ||
      minimum > maximum) {
    failure = 'OCR_FAIXA_INVALIDA';
  } else if (value != null && (value < minimum || value > maximum)) {
    failure = 'OCR_FORA_DA_FAIXA';
  }
  if (!ocrConfidence.isFinite || ocrConfidence < .40 || ocrConfidence > 1) {
    failure ??= 'OCR_BAIXA_CONFIANCA';
  }
  return WeightOcrResult(
    rawText: raw,
    normalizedText: digits,
    confidence: ocrConfidence.isFinite ? ocrConfidence.clamp(0, 1) : 0,
    error: failure ?? 'OCR_DIGITS_PENDING_CONSENSUS',
    strategy: strategy,
    elapsedMs: elapsedMs,
    diagnostics: {
      ...diagnostics,
      'configuredDigits': true,
      'rawDigits': digits,
      'decimalPlaces': places,
      'interpretedValue': value,
      'finalWeight': null,
      'ocrConfidence': ocrConfidence.isFinite ? ocrConfidence : 0,
      'numericAndRangeValid': failure == null,
    },
  );
}

/// Five independent photos, at least four matching raw sequences. Confidence
/// is an acceptance score, not a calibrated probability of correctness.
class ConfiguredDigitsConsensus {
  final _window = <WeightOcrResult>[];
  int stableReadings = 0;
  WeightOcrResult observe(WeightOcrResult reading) {
    _window.add(reading);
    if (_window.length > 5) _window.removeAt(0);
    bool eligible(WeightOcrResult r) =>
        r.diagnostics['numericAndRangeValid'] == true &&
        (r.error == 'OCR_DIGITS_PENDING_CONSENSUS' || r.error == null) &&
        r.ocrConfidence.isFinite &&
        r.ocrConfidence >= .40 &&
        r.ocrConfidence <= 1;
    final valid = eligible(reading);
    final matching = _window
        .where(
          (r) =>
              eligible(r) &&
              r.recognitionKey == reading.recognitionKey &&
              r.diagnostics['decimalPlaces'] ==
                  reading.diagnostics['decimalPlaces'],
        )
        .toList();
    stableReadings = valid ? matching.length : 0;
    final mean = matching.isEmpty
        ? 0.0
        : matching.map((r) => r.ocrConfidence).reduce((a, b) => a + b) /
              matching.length;
    final weakest = matching.isEmpty
        ? 0.0
        : matching.map((r) => r.ocrConfidence).reduce(math.min);
    final agreement = stableReadings / 5;
    // Repetition cannot rescue very weak observations. Require all five photos
    // and a minimum mean confidence, numeric grammar and plausible range.
    final score = .35 * mean + .55 * agreement + (valid ? .10 : 0);
    final accepted =
        _window.length == 5 &&
        stableReadings >= 4 &&
        weakest >= .40 &&
        mean >= .45 &&
        score >= .69 &&
        valid;
    final interpreted = reading.diagnostics['interpretedValue'] as num?;
    return WeightOcrResult(
      rawText: reading.rawText,
      normalizedText: reading.recognitionKey,
      weight: accepted ? interpreted!.truncateToDouble() : null,
      // Preserve OCR confidence separately; this is the temporal decision score.
      confidence: accepted ? score.clamp(0, 1) : reading.confidence,
      error: accepted
          ? null
          : valid
          ? 'OCR_DIGITS_PENDING_CONSENSUS'
          : reading.error,
      strategy: reading.strategy,
      model: reading.model,
      psm: reading.psm,
      attempts: reading.attempts,
      elapsedMs: reading.elapsedMs,
      requiredReadings: 4,
      consensusReadings: accepted ? stableReadings : 0,
      diagnostics: {
        ...reading.diagnostics,
        'temporalFrames': _window.length,
        'temporalVotes': stableReadings,
        'temporalAgreement': agreement,
        'acceptanceScore': score,
        'meanOcrConfidence': mean,
        'finalWeight': accepted ? interpreted!.truncate() : null,
      },
    );
  }
}
