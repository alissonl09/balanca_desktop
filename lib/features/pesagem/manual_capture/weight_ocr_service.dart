import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'capture_models.dart';
import 'image_processor.dart';
import 'tesseract_runtime.dart';

abstract interface class WeightOcrService {
  Future<WeightOcrResult> recognize(Uint8List image);
}

/// Real offline adapter. Requires Tesseract 5 + eng.traineddata on the station.
class TesseractWeightOcrService implements WeightOcrService {
  TesseractWeightOcrService({String? executable, TesseractRuntime? runtime})
    : runtime = runtime ?? TesseractRuntime.resolve(executable: executable);
  final TesseractRuntime runtime;
  String get executable => runtime.executable;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    final attempts = <OcrAttempt>[];
    Map<String, Uint8List> variants;
    try {
      variants = await Isolate.run(() => prepareOcrVariants(image));
    } catch (_) {
      // Still report a missing engine explicitly, including for invalid input.
      return _recognizeVariant(image);
    }
    for (final variant in variants.entries) {
      final result = await _recognizeVariant(
        variant.value,
        // Tesseract can assign confidence 0 to mixed number/unit words when
        // constrained by a whitelist, even if it reads them correctly.
        restrict:
            attempts.isNotEmpty &&
            !attempts.first.result.rawText.trim().toLowerCase().endsWith('kg'),
      );
      attempts.add(OcrAttempt(variant.key, variant.value, result));
      if (result.error == 'OCR_ENGINE_INDISPONIVEL' ||
          result.error == 'OCR_ENGINE_ERRO' ||
          result.error == 'OCR_MODELO_INDISPONIVEL' ||
          result.error == 'OCR_TIMEOUT') {
        break;
      }
    }
    return selectConsistentOcr(attempts);
  }

  Future<WeightOcrResult> _recognizeVariant(
    Uint8List image, {
    bool restrict = false,
  }) async {
    Directory? temporary;
    Process? process;
    try {
      final tessdata = runtime.tessdataDirectory;
      if (tessdata != null &&
          !await File('$tessdata/eng.traineddata').exists()) {
        return WeightOcrResult(
          error: 'OCR_MODELO_INDISPONIVEL',
          engineMessage: '$tessdata/eng.traineddata',
        );
      }
      temporary = await Directory.systemTemp.createTemp('balanca_ocr_');
      final input = File('${temporary.path}/display.png');
      await input.writeAsBytes(image, flush: true);
      process = await Process.start(executable, [
        input.path,
        'stdout',
        '-l',
        'eng',
        if (tessdata != null) ...['--tessdata-dir', tessdata],
        '--psm',
        '7',
        if (restrict) ...['-c', 'tessedit_char_whitelist=0123456789.,-kgKG'],
        '-c',
        'load_system_dawg=0',
        '-c',
        'load_freq_dawg=0',
        '-c',
        'tessedit_create_tsv=1',
      ]);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode.timeout(const Duration(seconds: 15));
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
      return interpretTesseractTsv(text);
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
WeightOcrResult interpretTesseractTsv(String tsv) {
  final words = <String>[];
  final confidences = <double>[];
  for (final line in const LineSplitter().convert(tsv).skip(1)) {
    final cells = line.split('\t');
    if (cells.length < 12 || cells[0] != '5' || cells[11].trim().isEmpty) {
      continue;
    }
    words.add(cells[11].trim());
    confidences.add((double.tryParse(cells[10]) ?? 0) / 100);
  }
  final raw = words.join(' ');
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
  final values = parsed.map((a) => a.result.weight).toSet();
  final best = valid.isNotEmpty ? valid.first : attempts.last;
  final error = values.length > 1
      ? 'OCR_VARIANTES_DIVERGENTES'
      : valid.length < 2 || !attempts.first.result.success
      ? best.result.error ?? 'OCR_SEM_CONSENSO'
      : null;
  return WeightOcrResult(
    rawText: best.result.rawText,
    weight: best.result.weight,
    confidence: best.result.confidence,
    error: error,
    strategy: best.strategy,
    attempts: attempts,
    engineMessage: best.result.engineMessage,
  );
}
