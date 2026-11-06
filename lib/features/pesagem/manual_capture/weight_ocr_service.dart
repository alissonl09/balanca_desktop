import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'capture_models.dart';
import 'decimal_detector.dart';
import 'image_processor.dart';
import 'seven_segment_preprocessor.dart';
import 'tesseract_runtime.dart';

abstract interface class WeightOcrService {
  Future<WeightOcrResult> recognize(Uint8List image);
}

abstract interface class OcrVariantEngine {
  Future<WeightOcrResult> recognizeVariant(
    Uint8List image, {
    String model = 'eng',
    String? tessdataDirectory,
    int psm = 7,
    bool restrict = false,
    bool numericOnly = false,
    String whitelist = '0123456789.-',
  });
}

/// Real offline adapter. Requires Tesseract 5 + eng.traineddata on the station.
class TesseractWeightOcrService implements WeightOcrService, OcrVariantEngine {
  TesseractWeightOcrService({
    String? executable,
    TesseractRuntime? runtime,
    this.processTimeout = const Duration(seconds: 15),
  }) : runtime = runtime ?? TesseractRuntime.resolve(executable: executable);
  final TesseractRuntime runtime;
  final Duration processTimeout;
  String get executable => runtime.executable;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    final attempts = <OcrAttempt>[];
    Map<String, Uint8List> variants;
    try {
      variants = await Isolate.run(() => prepareOcrVariants(image));
    } catch (_) {
      // Still report a missing engine explicitly, including for invalid input.
      return recognizeVariant(image);
    }
    final geometry = await Isolate.run(() => analyzeDisplayGeometry(image));
    for (final variant in variants.entries) {
      final result = await recognizeVariant(
        variant.value,
        // Tesseract can assign confidence 0 to mixed number/unit words when
        // constrained by a whitelist, even if it reads them correctly.
        restrict:
            attempts.isNotEmpty &&
            !attempts.first.result.rawText.trim().toLowerCase().endsWith('kg'),
      );
      attempts.add(
        OcrAttempt(
          variant.key,
          variant.value,
          reconcileVisualDecimal(result, geometry),
        ),
      );
      if (result.error == 'OCR_ENGINE_INDISPONIVEL' ||
          result.error == 'OCR_ENGINE_ERRO' ||
          result.error == 'OCR_MODELO_INDISPONIVEL' ||
          result.error == 'OCR_TIMEOUT') {
        break;
      }
    }
    final legacy = selectConsistentOcr(attempts);
    if (legacy.success ||
        attempts.any(
          (a) => [
            'OCR_ENGINE_INDISPONIVEL',
            'OCR_ENGINE_ERRO',
            'OCR_MODELO_INDISPONIVEL',
            'OCR_TIMEOUT',
          ].contains(a.result.error),
        )) {
      return legacy;
    }
    // Preserve the previous eng fallback, then compare eng on the untrimmed
    // high-resolution display variants too. Its old line crop can cut a dot.
    final displayVariants = await Isolate.run(
      () => prepareSevenSegmentVariants(image),
    );
    final displayAttempts = <OcrAttempt>[];
    for (final entry in displayVariants.entries) {
      final raw = await recognizeVariant(entry.value, numericOnly: true);
      final result = reconcileVisualDecimal(raw, geometry).copyWith(
        diagnostics: {
          ...geometry.toJson(),
          'requestedScale': 2,
          'effectiveScale': effectiveSevenSegmentScale(
            geometry.width,
            geometry.height,
            2,
          ),
          'thresholdMethod': entry.key.split('_').first,
          'paddingPixels': 10,
          'morphology': entry.key.startsWith('close1')
              ? 'close radius 1 (alternative)'
              : 'none',
        },
      );
      final attempt = OcrAttempt('display_${entry.key}', entry.value, result);
      displayAttempts.add(attempt);
      attempts.add(attempt);
      final selected = selectConsistentOcr(displayAttempts);
      if (selected.success) {
        return selected.copyWith(attempts: List.unmodifiable(attempts));
      }
    }
    return selectConsistentOcr(displayAttempts)
        .copyWith(attempts: List.unmodifiable(attempts));
  }

  @override
  Future<WeightOcrResult> recognizeVariant(
    Uint8List image, {
    String model = 'eng',
    String? tessdataDirectory,
    int psm = 7,
    bool restrict = false,
    bool numericOnly = false,
    String whitelist = '0123456789.-',
  }) async {
    final clock = Stopwatch()..start();
    final result = await _runVariant(
      image,
      model: model,
      tessdataDirectory: tessdataDirectory,
      psm: psm,
      restrict: restrict,
      numericOnly: numericOnly,
      whitelist: whitelist,
    );
    return result.copyWith(
      model: model,
      psm: psm,
      elapsedMs: clock.elapsedMilliseconds,
    );
  }

  Future<WeightOcrResult> _runVariant(
    Uint8List image, {
    bool restrict = false,
    String model = 'eng',
    String? tessdataDirectory,
    int psm = 7,
    bool numericOnly = false,
    String whitelist = '0123456789.-',
  }) async {
    Directory? temporary;
    Process? process;
    try {
      final tessdata = tessdataDirectory ?? runtime.tessdataDirectory;
      if (tessdata != null &&
          !await File('$tessdata/$model.traineddata').exists()) {
        return WeightOcrResult(
          error: 'OCR_MODELO_INDISPONIVEL',
          engineMessage: '$tessdata/$model.traineddata',
        );
      }
      temporary = await Directory.systemTemp.createTemp('balanca_ocr_');
      final input = File('${temporary.path}/display.png');
      await input.writeAsBytes(image, flush: true);
      process = await Process.start(executable, [
        input.path,
        'stdout',
        '-l',
        model,
        if (tessdata != null) ...['--tessdata-dir', tessdata],
        '--psm',
        '$psm',
        '--oem',
        '1',
        if (numericOnly || restrict) ...[
          '-c',
          'tessedit_char_whitelist=${numericOnly ? whitelist : '0123456789.,-kgKG'}',
        ],
        '-c',
        'load_system_dawg=0',
        '-c',
        'load_freq_dawg=0',
        '-c',
        'tessedit_create_tsv=1',
      ]);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode.timeout(processTimeout);
      final text = await output;
      final stderr = await errors;
      if (code != 0) {
        return WeightOcrResult(
          error: 'OCR_ENGINE_ERRO',
          engineMessage: stderr.length > 1000
              ? stderr.substring(0, 1000)
              : stderr,
        );
      }
      return interpretTesseractTsv(text, numericOnly: numericOnly);
    } on ProcessException catch (error) {
      return WeightOcrResult(
        error: 'OCR_ENGINE_INDISPONIVEL',
        engineMessage:
            'Executável: $executable; erro Windows: ${error.errorCode}',
      );
    } on TimeoutException {
      process?.kill();
      await process?.exitCode;
      return const WeightOcrResult(error: 'OCR_TIMEOUT');
    } catch (_) {
      return const WeightOcrResult(error: 'OCR_ERRO');
    } finally {
      if (temporary != null) {
        try {
          await temporary.delete(recursive: true);
        } catch (_) {
          /* Temporary files only. */
        }
      }
    }
  }
}

/// Strict display grammar. A dot/comma is ALWAYS decimal, never thousands.
/// No letter substitutions: missing or uncertain digits must remain a failure.
WeightOcrResult interpretTesseractTsv(String tsv, {bool numericOnly = false}) {
  final words = <String>[];
  final confidences = <double>[];
  final lines = <String>{};
  for (final line in const LineSplitter().convert(tsv).skip(1)) {
    final cells = line.split('\t');
    if (cells.length < 12 || cells[0] != '5' || cells[11].trim().isEmpty) {
      continue;
    }
    words.add(cells[11].trim());
    lines.add('${cells[2]}:${cells[3]}:${cells[4]}');
    confidences.add((double.tryParse(cells[10]) ?? 0) / 100);
  }
  final raw = words.join(' ');
  if (numericOnly &&
      (lines.length != 1 ||
          !RegExp(r'^-?[0-9]{1,7}(?:[.,][0-9]{1,3})?$').hasMatch(raw))) {
    return WeightOcrResult(rawText: raw, error: 'OCR_FORMATO_INVALIDO');
  }
  return parseWeightText(
    raw,
    confidences.isEmpty ? 0 : confidences.reduce((a, b) => a < b ? a : b),
  );
}

WeightOcrResult parseWeightText(String raw, double confidence) {
  final match = RegExp(
    r'^(-?(?:[0-9]{1,7}|[0-9]{1,3}(?: [0-9]{3}){1,2})(?:[.,][0-9]{1,3})?)\s*(?:kg)?$',
    caseSensitive: false,
  ).firstMatch(raw.trim());
  if (match == null) {
    return WeightOcrResult(
      rawText: raw,
      confidence: confidence,
      error: 'OCR_SEM_LEITURA',
    );
  }
  return WeightOcrResult(
    rawText: raw,
    normalizedText: match[1]!.replaceAll(' ', '').replaceAll(',', '.'),
    weight: double.tryParse(match[1]!.replaceAll(' ', '').replaceAll(',', '.')),
    confidence: confidence,
    error: confidence < WeightOcrResult.threshold
        ? 'OCR_BAIXA_CONFIANCA'
        : null,
  );
}

/// Independent preprocessing must agree. A conflicting parse is unsafe even
/// if its confidence is lower; repeated wrong confident output is still possible.
WeightOcrResult selectConsistentOcr(List<OcrAttempt> attempts) {
  if (attempts.isEmpty) return const WeightOcrResult(error: 'OCR_SEM_LEITURA');
  final parsed = attempts.where((a) => a.result.weight != null).toList();
  final valid = parsed.where((a) => a.result.success).toList();
  final values = parsed.map((a) => a.result.recognitionKey).toSet();
  final best = valid.isNotEmpty ? valid.first : attempts.last;
  final error = values.length > 1
      ? 'OCR_VARIANTES_DIVERGENTES'
      : valid.length < 2 || !attempts.first.result.success
      ? best.result.error ?? 'OCR_SEM_CONSENSO'
      : null;
  return best.result.copyWith(
    failure: error,
    confidence: valid.isEmpty
        ? best.result.confidence
        : valid.map((a) => a.result.confidence).reduce((a, b) => a < b ? a : b),
    strategy: best.strategy,
    attempts: attempts,
    model: best.result.model,
    psm: best.result.psm,
    elapsedMs: attempts.fold<int>(0, (sum, a) => sum + a.result.elapsedMs),
  );
}
