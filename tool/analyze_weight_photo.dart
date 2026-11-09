import 'dart:convert';
import 'dart:io';

import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/captured_image_analysis.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/persistent_digits_ocr.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/snapshot_weight_recognition.dart';

/// Full camera photo, same analyzeCapturedImage function as the application.
Future<void> main(List<String> args) async {
  if (args.length != 5 || args[1] != '--config' || args[3] != '--output') {
    stderr.writeln(
      'dart run tool/analyze_weight_photo.dart foto.jpg --config webcam.json --output build/photo_analysis',
    );
    exitCode = 64;
    return;
  }
  final config = WebcamConfiguration.fromJson(
    jsonDecode(await File(args[2]).readAsString()) as Map<String, dynamic>,
  );
  final directory = await Directory(args[4]).create(recursive: true);
  final run = await directory.createTemp('photo_');
  final photo = CapturedPhoto(
    await File(args[0]).readAsBytes(),
    DateTime.now(),
    mirrorHorizontally: config.mirrorHorizontally,
  );
  final original = '${run.path}/original.bin';
  await File(original).writeAsBytes(photo.bytes, flush: true);
  final processor = LocalCaptureImageProcessor();
  final stamped = await processor.processEvidence(photo);
  final evidence = '${run.path}/evidence.jpg';
  await File(evidence).writeAsBytes(stamped.evidence, flush: true);
  try {
    final analysis = await analyzeCapturedImage(
      photo,
      configuration: config,
      processor: processor,
      recognition: SnapshotWeightRecognition(configuration: () => config),
    );
    final result = analysis.result.copyWith(
      diagnostics: {
        ...analysis.result.diagnostics,
        'originalImagePath': original,
        'evidenceImagePath': evidence,
      },
    );
    final diagnostics = run.path;
    await File('${run.path}/original_clean.png')
        .writeAsBytes(analysis.capture.original!);
    await File('${run.path}/roi.png').writeAsBytes(analysis.capture.ocrInput);
    if (analysis.capture.rawRoi != null) {
      await File('${run.path}/roi_original.png')
          .writeAsBytes(analysis.capture.rawRoi!);
    }
    for (var i = 0; i < result.attempts.length; i++) {
      final attempt = result.attempts[i];
      if (attempt.image.isNotEmpty) {
        await File('${run.path}/pipeline_$i.png').writeAsBytes(attempt.image);
      }
    }
    final report = const JsonEncoder.withIndent('  ').convert({
      'rawDigits': result.rawDigits,
      'decimalPlaces': result.decimalPlaces,
      'interpretedValue': result.interpretedValue,
      'finalWeight': result.finalWeight,
      'confidence': result.finalConfidence,
      'success': result.success,
      'failureReason': result.error,
      'method': result.strategy,
      'elapsedMs': result.elapsedMs,
      'originalImagePath': original,
      'evidenceImagePath': evidence,
      'diagnosticPath': diagnostics,
      'diagnostics': result.diagnostics,
      'attempts': result.attempts.map((a) => a.toJson()).toList(),
      'note': 'Static image; no weighing registered or human confirmation simulated.',
    });
    await File('${run.path}/result.json').writeAsString(report);
    stdout.writeln(report);
  } finally {
    await PersistentDigitsOcr.shared.close();
  }
}
