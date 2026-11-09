import 'dart:convert';
import 'dart:io';

import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/configured_digits_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/persistent_digits_ocr.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_recognition_validation.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'dart run tool/benchmark_configured_digits.dart roi.png decimalPlaces',
    );
    exitCode = 64;
    return;
  }
  final config = WebcamConfiguration(decimalPlaces: int.parse(args[1]));
  final engine = ConfiguredDigitsService(() => config);
  final consensus = WeightTemporalConsensus(
    requiredReadings: 4,
    digitsMode: true,
  );
  final image = await File(args[0]).readAsBytes();
  final rows = <Map<String, Object?>>[];
  try {
    for (var i = 0; i < 5; i++) {
      final reading = await engine.recognize(image);
      final result = consensus.observe(reading);
      rows.add({
        'frame': i + 1,
        'rawDigits': result.rawDigits,
        'rawText': result.rawText,
        'ocrConfidence': result.ocrConfidence,
        'confidence': result.confidence,
        'elapsedMs': reading.elapsedMs,
        'weight': result.weight,
        'success': result.success,
        'error': result.error,
        'engineMessage': reading.engineMessage,
        'diagnostics': result.diagnostics,
      });
    }
    final report = const JsonEncoder.withIndent('  ').convert({
      'note': 'Same static image repeated; tests engine reuse, not independent-photo consensus.',
      'rows': rows,
    });
    final directory = await Directory('tools/weight_vision/reports')
        .create(recursive: true);
    await File(
      '${directory.path}/digits_${DateTime.now().microsecondsSinceEpoch}.json',
    ).writeAsString(report);
    stdout.writeln(report);
  } finally {
    await PersistentDigitsOcr.shared.close();
  }
}
