import 'dart:convert';
import 'dart:io';

import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/seven_segment_recognition_engine.dart';

/// Geometry only, fully offline. Explicit ROI is mandatory; never modifies input.
Future<void> main(List<String> args) async {
  final usingConfig =
      args.length == 5 && args[1] == '--config' && args[3] == '--output';
  if (!usingConfig && args.length != 6 && args.length != 7) {
    stderr.writeln(
      'Uso: dart run tool/recognize_display.dart foto.png x y largura altura perfil [pasta_saida]\nOu: dart run tool/recognize_display.dart foto.jpg --config webcam.json --output pasta_saida',
    );
    exitCode = 64;
    return;
  }
  final WebcamConfiguration config;
  final String output;
  if (usingConfig) {
    config = WebcamConfiguration.fromJson(
      jsonDecode(await File(args[2]).readAsString()) as Map<String, dynamic>,
    );
    output = args[4];
  } else {
    config = WebcamConfiguration(
      region: DisplayRegion(
        left: double.parse(args[1]),
        top: double.parse(args[2]),
        width: double.parse(args[3]),
        height: double.parse(args[4]),
      ),
      displayProfile: args[5],
    );
    output = args.length > 6 ? args[6] : 'build/display_diagnostics';
  }
  final capture = await LocalCaptureImageProcessor().process(
    CapturedPhoto(await File(args[0]).readAsBytes(), DateTime.now()),
    config.region,
  );
  final result = recognizeDisplay(
    capture.ocrInput,
    profile: config.displayProfile,
    diagnostics: true,
  );
  final dir = await Directory(output).create(recursive: true);
  if (capture.original != null) {
    await File('${dir.path}/original.png').writeAsBytes(capture.original!);
  }
  if (capture.rawRoi != null) {
    await File('${dir.path}/roi.png').writeAsBytes(capture.rawRoi!);
  }
  await File('${dir.path}/rectified.png').writeAsBytes(capture.ocrInput);
  for (var i = 0; i < result.attempts.length; i++) {
    await File('${dir.path}/stage_$i.png')
        .writeAsBytes(result.attempts[i].image);
  }
  final json = const JsonEncoder.withIndent('  ').convert({
    'success': result.success,
    'weight': result.weight,
    'confidence': result.candidateConfidence,
    'rawDigits': result.rawDigits,
    'rawText': result.rawText,
    'integerDigits': result.integerDigits,
    'decimalDetected': result.decimalDetected,
    'profile': result.profile,
    'method': result.strategy,
    'frameCount': 1,
    'consensusCount': 0,
    'failureReason': result.failureReason,
    'elapsedMs': result.elapsedMs,
    'diagnostics': result.diagnostics,
    'note': 'Imagem estática: não confirma estabilidade temporal.',
  });
  await File('${dir.path}/result.json').writeAsString(json);
  stdout.writeln(json);
  exitCode = result.success ? 0 : 1;
}
