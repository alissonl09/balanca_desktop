import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'capture_models.dart';

abstract interface class WeightOcrService {
  Future<WeightOcrResult> recognize(Uint8List image);
}

/// Real offline adapter. Requires Tesseract 5 + eng.traineddata on the station.
class TesseractWeightOcrService implements WeightOcrService {
  TesseractWeightOcrService({this.executable = 'tesseract'});
  final String executable;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    Directory? temporary;
    Process? process;
    try {
      temporary = await Directory.systemTemp.createTemp('balanca_ocr_');
      final input = File('${temporary.path}/display.png');
      await input.writeAsBytes(image, flush: true);
      process = await Process.start(executable, [
        input.path,
        'stdout',
        '-l',
        'eng',
        '--psm',
        '7',
        'tsv',
      ]);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode.timeout(const Duration(seconds: 15));
      final text = await output;
      await errors;
      if (code != 0) return const WeightOcrResult(error: 'OCR_ENGINE_ERRO');
      return interpretTesseractTsv(text);
    } on ProcessException {
      return const WeightOcrResult(error: 'OCR_ENGINE_INDISPONIVEL');
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

/// Conservative display profile: exactly one integer, optionally followed by kg.
/// Ambiguous separators, clocks, serial labels and multiple values are rejected.
/// Confidence comes from the engine, never from a regex or invented text.
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
  final match = RegExp(
    r'^([0-9]{1,7})\s*(?:kg)?$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null || confidences.isEmpty) {
    return WeightOcrResult(rawText: raw, error: 'OCR_SEM_LEITURA');
  }
  final confidence = confidences.reduce((a, b) => a < b ? a : b);
  return WeightOcrResult(
    rawText: raw,
    weight: double.tryParse(match[1]!),
    confidence: confidence,
    error: confidence < WeightOcrResult.threshold
        ? 'OCR_BAIXA_CONFIANCA'
        : null,
  );
}
