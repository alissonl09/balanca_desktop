import 'dart:convert';
import 'dart:io';

import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';

/// Offline replay. Input is never overwritten. Optional ROI: x y width height.
Future<void> main(List<String> args) async {
  if (args.isEmpty || (args.length != 1 && args.length != 5)) {
    stderr.writeln(
      'Uso: dart tool/diagnose_weight_ocr.dart foto.png [x y largura altura]',
    );
    exitCode = 64;
    return;
  }
  final region = args.length == 1
      ? const DisplayRegion(left: 0, top: 0, width: 1, height: 1)
      : DisplayRegion(
          left: double.parse(args[1]),
          top: double.parse(args[2]),
          width: double.parse(args[3]),
          height: double.parse(args[4]),
        );
  final capture = await LocalCaptureImageProcessor().process(
    CapturedPhoto(await File(args.first).readAsBytes(), DateTime.now()),
    region,
  );
  final engine = TesseractWeightOcrService();
  final result = await engine.recognize(capture.ocrInput);
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'engine': engine.executable,
      'tessdata': engine.runtime.tessdataDirectory,
      'rawText': result.rawText,
      'weight': result.weight,
      'confidence': result.confidence,
      'error': result.error,
      'engineMessage': result.engineMessage,
      'attempts': result.attempts.map((a) => a.toJson()).toList(),
    }),
  );
  exitCode = result.success ? 0 : 1;
}
