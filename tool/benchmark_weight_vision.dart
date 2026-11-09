import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/seven_segment_recognition_engine.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/seven_segment_ocr_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_vision_engine.dart';

/// Static ROI or manifest benchmark. Never records a weighing.
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'dart run tool/benchmark_weight_vision.dart roi.png 13880 [13880.0]\n'
      'dart run tool/benchmark_weight_vision.dart --manifest manifest.json',
    );
    exitCode = 64;
    return;
  }
  final samples = args[0] == '--manifest'
      ? (jsonDecode(await File(args[1]).readAsString()) as List)
            .cast<Map<String, dynamic>>()
      : <Map<String, dynamic>>[
          {
            'image': args[0],
            'expected': args[1],
            if (args.length > 2) 'expectedSequence': args[2],
          },
        ];
  final rows = <Map<String, Object?>>[];
  for (final sample in samples) {
    final expected = sample['expected'].toString();
    if (!RegExp(r'^\d+$').hasMatch(expected)) {
      throw const FormatException('expected deve ser peso inteiro em kg');
    }
    final file = File(sample['image'] as String);
    Uint8List image = await file.readAsBytes();
    if (sample['region'] != null) {
      final processed = await LocalCaptureImageProcessor().process(
        CapturedPhoto(image, DateTime.now()),
        DisplayRegion.fromJson(sample['region'] as Map<String, dynamic>),
      );
      image = processed.ocrInput;
    }
    final engines = <String, WeightOcrService>{
      'Geometric': SevenSegmentRecognitionEngine(
        profile: sample['profile'] as String? ?? 'auto',
        diagnostics: true,
      ),
      'Tesseract 7seg': SevenSegmentWeightOcrService(
        generic: const _Unavailable(),
      ),
      'Tesseract generic': TesseractWeightOcrService(),
      'Custom model': const CustomModelEngine(),
    };
    for (final entry in engines.entries) {
      final timer = Stopwatch()..start();
      WeightOcrResult result;
      try {
        result = await entry.value.recognize(image);
      } catch (_) {
        result = const WeightOcrResult(error: 'BENCHMARK_ENGINE_ERROR');
      }
      rows.add(
        benchmarkRow(
          file.path,
          entry.key,
          expected,
          sample['expectedSequence'] as String?,
          result,
          timer.elapsedMilliseconds,
        ),
      );
    }
    // Explicit local Python subprocess. No production dependency, no downloads.
    final temp = await Directory.systemTemp.createTemp('weight_benchmark_');
    try {
      final roi = File('${temp.path}/roi.png');
      await roi.writeAsBytes(image);
      final timer = Stopwatch()..start();
      final paddle = await Process.run(
        Platform.environment['WEIGHT_VISION_PYTHON'] ?? 'python',
        ['tools/weight_vision/scripts/paddle_baseline.py', roi.path],
      ).timeout(const Duration(minutes: 2));
      final data = jsonDecode(paddle.stdout.toString()) as Map<String, dynamic>;
      rows.add(
        benchmarkRow(
          file.path,
          'PaddleOCR',
          expected,
          sample['expectedSequence'] as String?,
          WeightOcrResult(
            rawText: data['sequence'] as String? ?? '',
            weight: double.tryParse(
              (data['sequence'] as String? ?? '').split('.').first,
            ),
            confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
            error: data['error'] as String?,
          ),
          timer.elapsedMilliseconds,
        )..['details'] = data,
      );
    } catch (error) {
      rows.add({
        'image': file.path,
        'engine': 'PaddleOCR',
        'expected': expected,
        'error': 'PADDLE_UNAVAILABLE_OR_ERROR',
        'details': error.toString(),
        'weightCorrect': false,
        'imageCorrect': false,
      });
    } finally {
      await temp.delete(recursive: true);
    }
  }
  final summary = <String, Object?>{};
  for (final name in rows.map((r) => r['engine'] as String).toSet()) {
    final subset = rows.where((r) => r['engine'] == name).toList();
    summary[name] = {
      'images': subset.length,
      'weightCorrect': subset.where((r) => r['weightCorrect'] == true).length,
      'successRate':
          subset.where((r) => r['weightCorrect'] == true).length /
          subset.length,
      'meanElapsedMs':
          subset
              .map((r) => r['elapsedMs'] as int? ?? 0)
              .reduce((a, b) => a + b) /
          subset.length,
    };
  }
  final report = const JsonEncoder.withIndent('  ').convert({
    'note': 'Imagem estática; sem consenso temporal. Tempos incluem preparação e inicialização.',
    'rows': rows,
    'summary': summary,
  });
  final output = await Directory('tools/weight_vision/reports')
      .create(recursive: true);
  await File(
    '${output.path}/benchmark_${DateTime.now().microsecondsSinceEpoch}.json',
  ).writeAsString(report);
  stdout.writeln(report);
}

Map<String, Object?> benchmarkRow(
  String image,
  String engine,
  String expected,
  String? expectedSequence,
  WeightOcrResult result,
  int elapsed,
) {
  final predicted = result.weight?.truncate().toString();
  final sequence = result.recognitionKey;
  return {
    'image': image,
    'engine': engine,
    'expected': expected,
    'expectedSequence': expectedSequence,
    'sequence': sequence,
    'result': predicted,
    'error': result.error,
    'weightCorrect':
        result.success && predicted == int.parse(expected).toString(),
    'imageCorrect': expectedSequence == null
        ? null
        : result.success && sequence == expectedSequence,
    'digitEditDistance': editDistance(
      expectedSequence ?? expected,
      expectedSequence == null ? sequence.split('.').first : sequence,
    ),
    'elapsedMs': elapsed,
    'confidence': result.candidateConfidence,
    'diagnostics': result.diagnostics,
  };
}

int editDistance(String expected, String predicted) {
  var previous = List.generate(predicted.length + 1, (i) => i);
  for (var i = 1; i <= expected.length; i++) {
    final current = <int>[i];
    for (var j = 1; j <= predicted.length; j++) {
      final costs = [
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + (expected[i - 1] == predicted[j - 1] ? 0 : 1),
      ]..sort();
      current.add(costs.first);
    }
    previous = current;
  }
  return previous.last;
}

class _Unavailable implements WeightOcrService {
  const _Unavailable();
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async =>
      const WeightOcrResult(error: 'SPECIALIZED_UNAVAILABLE_OR_FAILED');
}
