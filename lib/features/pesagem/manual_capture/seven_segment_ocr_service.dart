import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'capture_models.dart';
import 'seven_segment_preprocessor.dart';
import 'tesseract_runtime.dart';
import 'weight_ocr_service.dart';

/// Priority cascade: 7seg -> alternate preprocessing/PSM -> legacy eng.
/// ssd/ssd_int are shipped for comparison; enabling them requires calibration.
class SevenSegmentWeightOcrService implements WeightOcrService {
  SevenSegmentWeightOcrService({
    OcrVariantEngine? engine,
    WeightOcrService? generic,
    String? modelDirectory,
    this.models = const ['7seg'],
    this.psms = const [7, 13],
    this.whitelist = '0123456789.-',
    this.budget = const Duration(seconds: 10),
  }) : engine = engine ?? TesseractWeightOcrService(),
       generic = generic ?? TesseractWeightOcrService(),
       modelDirectory =
           modelDirectory ?? TesseractRuntime.resolveModelDirectory();
  final OcrVariantEngine engine;
  final WeightOcrService generic;
  final String modelDirectory, whitelist;
  final List<String> models;
  final List<int> psms;
  final Duration budget;

  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    final clock = Stopwatch()..start();
    final attempts = <OcrAttempt>[];
    Map<String, Uint8List> variants;
    try {
      variants = await Isolate.run(() => prepareSevenSegmentVariants(image));
    } catch (_) {
      return generic.recognize(image);
    }
    for (final model in models) {
      if (!await File('$modelDirectory/$model.traineddata').exists()) {
        attempts.add(
          OcrAttempt(
            'model_check',
            Uint8List(0),
            WeightOcrResult(
              model: model,
              error: 'OCR_MODELO_ESPECIALIZADO_INDISPONIVEL',
            ),
          ),
        );
        continue;
      }
      final current = <OcrAttempt>[];
      for (final psm in psms) {
        for (final variant in variants.entries) {
          if (clock.elapsed >= budget) break;
          final result = await engine.recognizeVariant(
            variant.value,
            model: model,
            tessdataDirectory: modelDirectory,
            psm: psm,
            numericOnly: true,
            whitelist: whitelist,
          );
          final attempt = OcrAttempt(variant.key, variant.value, result);
          current.add(attempt);
          attempts.add(attempt);
          if (result.error == 'OCR_ENGINE_INDISPONIVEL' ||
              result.error == 'OCR_TIMEOUT') {
            return result.copyWith(
              attempts: attempts,
              elapsedMs: clock.elapsedMilliseconds,
            );
          }
          // Two different image pipelines must agree; changing only PSM does
          // not constitute a second independent preprocessing result.
          final selected = selectSpecializedOcr(current);
          if (selected.success) {
            final conflictingModels = attempts.where(
              (a) =>
                  a.result.model != model &&
                  a.result.weight != null &&
                  a.result.confidence >= .5 &&
                  a.result.weight != selected.weight,
            );
            return selected.copyWith(
              failure: conflictingModels.isNotEmpty
                  ? 'OCR_MODELOS_DIVERGENTES'
                  : null,
              attempts: List.unmodifiable(attempts),
              elapsedMs: clock.elapsedMilliseconds,
            );
          }
        }
      }
      if (clock.elapsed >= budget) break;
    }
    final fallback = await generic.recognize(image);
    attempts.addAll(fallback.attempts);
    // A trustworthy conflicting specialized reading cannot be erased by eng.
    final conflicts = attempts.where(
      (a) => a.result.success && a.result.weight != fallback.weight,
    );
    if (fallback.success && conflicts.isNotEmpty) {
      return fallback.copyWith(
        failure: 'OCR_MODELOS_DIVERGENTES',
        attempts: attempts,
        elapsedMs: clock.elapsedMilliseconds,
      );
    }
    return fallback.copyWith(
      attempts: List.unmodifiable(attempts),
      elapsedMs: clock.elapsedMilliseconds,
    );
  }
}

WeightOcrResult selectSpecializedOcr(List<OcrAttempt> attempts) {
  if (attempts.isEmpty) {
    return const WeightOcrResult(error: 'OCR_SEM_LEITURA');
  }
  final parsed = attempts.where((a) => a.result.weight != null).toList();
  final valid = parsed.where((a) => a.result.success).toList();
  final distinct = valid.map((a) => a.strategy).toSet();
  final values = parsed.map((a) => a.result.weight).toSet();
  if (values.length > 1) {
    return attempts.last.result.copyWith(failure: 'OCR_VARIANTES_DIVERGENTES');
  }
  if (distinct.length < 2) {
    return attempts.last.result.copyWith(failure: 'OCR_SEM_CONSENSO');
  }
  final best = valid.reduce(
    (a, b) => a.result.confidence < b.result.confidence ? a : b,
  );
  return best.result.copyWith(strategy: best.strategy);
}
