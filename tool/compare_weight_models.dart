import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/decimal_detector.dart';
import 'package:image/image.dart' as img;
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/seven_segment_preprocessor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/tesseract_runtime.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';

/// Offline diagnostic. Original photographs are never modified or versioned.
/// Full grid is deliberately opt-in and is never used by the weighing dialog.
Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length != 5) {
    stderr.writeln(
      'Uso: dart run tool/compare_weight_models.dart foto.png x y largura altura '
      '[--full] [--out=build/ocr-comparison]',
    );
    exitCode = 64;
    return;
  }
  final full = args.contains('--full');
  final outArg = args.where((a) => a.startsWith('--out=')).firstOrNull;
  final output = await Directory(outArg?.substring(6) ?? 'build/ocr-comparison')
      .create(recursive: true);
  final region = DisplayRegion(
    left: double.parse(positional[1]),
    top: double.parse(positional[2]),
    width: double.parse(positional[3]),
    height: double.parse(positional[4]),
  );
  final capture = await LocalCaptureImageProcessor().process(
    CapturedPhoto(await File(positional[0]).readAsBytes(), DateTime.now()),
    region,
  );
  await File('${output.path}/roi.png').writeAsBytes(capture.ocrInput);
  final engine = TesseractWeightOcrService();
  final geometry = analyzeDisplayGeometry(capture.ocrInput);
  final modelDirectory = TesseractRuntime.resolveModelDirectory();
  final report = <Map<String, Object?>>[];
  final baseline = await engine.recognize(capture.ocrInput);
  report.add({
    'model': 'eng_legacy',
    'psm': 7,
    'pipeline': baseline.strategy,
    'weight': baseline.weight,
    'rawText': baseline.rawText,
    'confidence': baseline.confidence,
    'success': baseline.success,
    'error': baseline.error,
    'elapsedMs': baseline.elapsedMs,
  });
  for (final scale in full ? [2, 3, 4] : [2]) {
    final variants = await Isolate.run(
      () => prepareSevenSegmentVariants(
        capture.ocrInput,
        scale: scale,
        experimental: full,
      ),
    );
    for (final entry in variants.entries) {
      if (!full &&
          !entry.key.startsWith('gray_') &&
          !entry.key.startsWith('otsu_')) {
        continue;
      }
      await File('${output.path}/${entry.key}.png').writeAsBytes(entry.value);
      for (final model in ['7seg', 'ssd', 'ssd_int', 'eng']) {
        for (final psm in [7, 8, 13]) {
          final result = await engine.recognizeVariant(
            entry.value,
            model: model,
            psm: psm,
            tessdataDirectory: model == 'eng'
                ? engine.runtime.tessdataDirectory
                : modelDirectory,
            numericOnly: true,
          );
          final row = <String, Object?>{
            'model': model,
            'psm': psm,
            'pipeline': entry.key,
            'weight': result.weight,
            'rawText': result.rawText,
            'confidence': result.confidence,
            'success': result.success,
            'error': result.error,
            'elapsedMs': result.elapsedMs,
            'normalizedText': result.normalizedText,
            'hybridText': reconcileVisualDecimal(
              result,
              geometry,
            ).normalizedText,
            'hybridWeight': reconcileVisualDecimal(result, geometry).weight,
            'hybridSuccess': reconcileVisualDecimal(result, geometry).success,
            'hybridFailure': reconcileVisualDecimal(result, geometry).error,
            'decimalDetected': reconcileVisualDecimal(
              result,
              geometry,
            ).decimalDetected,
            'requestedScale': scale,
            'effectiveScale': effectiveSevenSegmentScale(
              capture.roiWidth,
              capture.roiHeight,
              scale,
            ),
            'inputWidth': img.decodePng(entry.value)!.width,
            'inputHeight': img.decodePng(entry.value)!.height,
          };
          report.add(row);
          stdout.writeln(jsonEncode(row));
        }
      }
    }
  }
  await File('${output.path}/comparison.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'source': File(positional.first).absolute.path,
      'region': region.toJson(),
      'engine': engine.executable,
      'modelDirectory': modelDirectory,
      'comparisonOnly': true,
      'dimensions': capture.dimensions,
      'geometry': geometry.toJson(),
      'temporalConsensusTested': false,
      'results': report,
    }),
  );
  stdout.writeln('Relatório local: ${output.path}/comparison.json');
}
