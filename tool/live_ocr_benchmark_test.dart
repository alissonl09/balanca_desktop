import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/live_weight_reader.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/live_weight_ocr_service.dart';

import '../test/support/manual_capture_mocks.dart';

void main() {
  test('benchmark live replay of historical photo', () async {
    final source = img.decodePng(
      File('test/fixtures/weight_ocr/ind570_webcam_570.png').readAsBytesSync(),
    )!;
    final roi = Uint8List.fromList(
      img.encodePng(
        img.copyCrop(source, x: 307, y: 137, width: 317, height: 104),
      ),
    );
    final camera = MockWeighingCameraService()
      ..photo = CapturedPhoto(roi, DateTime.now());
    final ready = Completer<void>();
    final timings = <int>[];
    late LiveWeightReader reader;
    reader = LiveWeightReader(
      camera: camera,
      processor: LocalCaptureImageProcessor(),
      ocr: LiveWeightOcrService(),
      configuration: const WebcamConfiguration(
        ocrEnabled: true,
        region: DisplayRegion(left: 0, top: 0, width: 1, height: 1),
      ),
      onChanged: () {
        timings.add(reader.result.elapsedMs);
        if (reader.ready && !ready.isCompleted) ready.complete();
      },
    );
    final clock = Stopwatch()..start();
    reader.start();
    try {
      await ready.future.timeout(const Duration(seconds: 20));
    } finally {
      await reader.stop();
      clock.stop();
    }
    final report = {
      'fixture': 'test/fixtures/weight_ocr/ind570_webcam_570.png',
      'replayOnly': true,
      'hardwareCapturePerformed': false,
      'sameHistoricalImageRepeated': true,
      'roiWidth': 317,
      'roiHeight': 104,
      'cameraSnapshots': camera.captures,
      'perFrameMs': timings,
      'greenAfterMs': clock.elapsedMilliseconds,
      'normalizedText': reader.result.normalizedText,
      'confidence': reader.result.finalConfidence,
      'passesPerFrame': reader.result.attempts.length,
      'consensusCount': reader.result.consensusCount,
    };
    await File('build/live-ocr-benchmark.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln(jsonEncode(report));
    expect(reader.result.normalizedText, '570.0');
  });
}
