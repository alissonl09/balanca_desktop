import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/decimal_detector.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/seven_segment_preprocessor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/seven_segment_ocr_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_recognition_validation.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/roi_editor.dart';

import 'support/display_fixture.dart';

void main() {
  test('optional deskew preserves decimal and leaves photograph unchanged', () {
    final source = img.decodePng(displayFixture('570.0'))!;
    source.backgroundColor = img.ColorRgb8(12, 12, 12);
    final tilted = img.copyRotate(
      source,
      angle: 2,
      interpolation: img.Interpolation.cubic,
    );
    final photo = CapturedPhoto(
      Uint8List.fromList(img.encodePng(tilted)),
      DateTime(2026),
    );
    final plain = processCapture(
      photo,
      const DisplayRegion(left: 0, top: 0, width: 1, height: 1),
    );
    const region = DisplayRegion(
      left: 0,
      top: 0,
      width: 1,
      height: 1,
      deskewDegrees: 2,
    );
    final corrected = processCapture(photo, region);
    expect(corrected.evidence, plain.evidence);
    expect(corrected.original, plain.original);
    expect(corrected.ocrWidth, greaterThan(plain.ocrWidth));
    final geometry = analyzeDisplayGeometry(corrected.ocrInput);
    expect(
      reconcileVisualDecimal(
        parseWeightText('5700', .99),
        geometry,
      ).normalizedText,
      '570.0',
      reason: '${geometry.toJson()}',
    );
    expect(DisplayRegion.fromJson(region.toJson()).deskewDegrees, 2);
    expect(const DisplayRegion(deskewDegrees: 20).valid, isFalse);
  });
  test('each camera restores its normalized ROI from local configuration', () {
    const first = DisplayRegion(left: .2, top: .3, width: .4, height: .2);
    const second = DisplayRegion(left: .1, top: .1, width: .3, height: .3);
    var config = const WebcamConfiguration(cameraId: 'A', region: first);
    config = config.copyWith(cameraId: 'B').copyWith(region: second);
    config = WebcamConfiguration.fromJson(config.toJson());
    expect(config.copyWith(cameraId: 'A').region.toJson(), first.toJson());
    expect(
      config.copyWith(cameraId: 'A').copyWith(cameraId: 'B').region.toJson(),
      second.toJson(),
    );
    expect(config.copyWith(expectedDecimalPlaces: 1).expectedDecimalPlaces, 1);
    expect(
      config
          .copyWith(expectedDecimalPlaces: 1)
          .copyWith(automaticDecimals: true)
          .expectedDecimalPlaces,
      isNull,
    );
  });
  testWidgets('ROI can move and resize in preview coordinates', (tester) async {
    var region = const DisplayRegion(left: .2, top: .2, width: .4, height: .3);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 640,
              height: 360,
              child: StatefulBuilder(
                builder: (context, refresh) => DisplayRegionEditor(
                  region: region,
                  onChanged: (r) => refresh(() => region = r),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('roi-move')),
      const Offset(64, 36),
    );
    await tester.pump();
    expect(region.left, closeTo(.3, .001));
    expect(region.top, closeTo(.3, .001));
    await tester.drag(
      find.byKey(const ValueKey('roi-resize')),
      const Offset(64, 36),
    );
    await tester.pump();
    expect(region.width, closeTo(.5, .001));
    expect(region.height, closeTo(.4, .001));
    expect(region.valid, isTrue);
  });
  test('middle-height specks are not decimals and multiple bottom points are ambiguous', () {
    final image = img.decodePng(displayFixture('5700'))!;
    final boxes = analyzeDisplayGeometry(
      Uint8List.fromList(img.encodePng(image)),
    ).characters;
    final x = boxes[2].right + 3;
    img.fillRect(
      image,
      x1: x,
      y1: 40,
      x2: x + 2,
      y2: 42,
      color: img.ColorRgb8(235, 235, 235),
    );
    var geometry = analyzeDisplayGeometry(
      Uint8List.fromList(img.encodePng(image)),
    );
    expect(geometry.points, isEmpty);
    expect(
      reconcileVisualDecimal(parseWeightText('5700', .99), geometry).weight,
      5700,
    );
    for (final index in [1, 2]) {
      final px = boxes[index].right + 3;
      img.fillRect(
        image,
        x1: px,
        y1: 72,
        x2: px + 2,
        y2: 74,
        color: img.ColorRgb8(235, 235, 235),
      );
    }
    geometry = analyzeDisplayGeometry(Uint8List.fromList(img.encodePng(image)));
    expect(geometry.points, hasLength(2));
    expect(
      reconcileVisualDecimal(parseWeightText('5700', .99), geometry).success,
      isFalse,
    );
  });
  for (final text in ['0.0', '10.0', '100.0', '570.0', '12190', '5700']) {
    test('image geometry reconstructs $text without scaling integers', () {
      final geometry = analyzeDisplayGeometry(displayFixture(text));
      final reading = reconcileVisualDecimal(
        parseWeightText(text.replaceAll('.', ''), .99),
        geometry,
      );
      expect(reading.recognitionKey, text, reason: '${geometry.toJson()}');
      expect(reading.decimalDetected, text.contains('.'));
      expect(reading.weight, double.parse(text));
      expect(reading.success, isTrue);
    });
  }
  test('small point, low light, both polarities and ROI sizes', () {
    for (final bytes in [
      displayFixture('570.0', dotSize: 2),
      displayFixture('570.0', intensity: 85),
      displayFixture('570.0', inverted: true),
      displayFixture('570.0', digitHeight: 24, dotSize: 2),
      displayFixture('570.0', digitHeight: 128, dotSize: 8),
    ]) {
      final geometry = analyzeDisplayGeometry(bytes);
      final reading = reconcileVisualDecimal(
        parseWeightText('5700', .99),
        geometry,
      );
      expect(reading.normalizedText, '570.0', reason: '${geometry.toJson()}');
      expect(reading.success, isTrue);
      for (final scale in [2, 3, 4]) {
        final variants = prepareSevenSegmentVariants(bytes, scale: scale);
        for (final name in ['otsu', 'global128', 'adaptive']) {
          final g = analyzeDisplayGeometry(variants['${name}_${scale}x']!);
          expect(g.points, hasLength(1), reason: '$name $scale ${g.toJson()}');
        }
      }
    }
  });
  test('50 percent never becomes accepted after decimal recovery', () {
    final result = reconcileVisualDecimal(
      parseWeightText('5700', .5),
      analyzeDisplayGeometry(displayFixture('570.0')),
    );
    expect(result.normalizedText, '570.0');
    expect(result.confidence, .5);
    expect(result.success, isFalse);
  });
  test('configured decimals only validate, never insert a dot', () {
    final result = const WeightRecognitionRules(
      minimum: 0,
      maximum: 100000,
      expectedDecimalPlaces: 1,
    ).validate(parseWeightText('5700', .99));
    expect(result.weight, 5700);
    expect(result.error, 'OCR_CASAS_DECIMAIS_DIVERGENTES');
  });
  test(
    'decimal-aware temporal majority tolerates one bad independent frame',
    () {
      final consensus = WeightTemporalConsensus();
      WeightOcrResult result = const WeightOcrResult();
      for (final text in ['570.0', '570.0', '5700', '570.0', '570.0']) {
        result = consensus.observe(parseWeightText(text, .99));
      }
      expect(result.consensus, isTrue);
      expect(result.normalizedText, '570.0');
      expect(result.consensusCount, 4);
      expect(result.finalConfidence, .98);
      final precision = WeightTemporalConsensus();
      for (final text in ['570', '570.0', '570', '570.0', '570']) {
        expect(
          precision.observe(parseWeightText(text, .99)).consensus,
          isFalse,
        );
      }
    },
  );
  test(
    'ROI stays at original resolution irrespective of preview dimensions',
    () {
      final image = img.Image(width: 1920, height: 1080);
      final result = processCapture(
        CapturedPhoto(Uint8List.fromList(img.encodePng(image)), DateTime(2026)),
        const DisplayRegion(left: .2, top: .3, width: .5, height: .2),
      );
      expect(result.frameWidth, 1920);
      expect(result.roiWidth, 960);
      expect(result.roiHeight, 216);
      final variants = prepareSevenSegmentVariants(result.ocrInput);
      expect(
        img.decodePng(variants.values.first)!.width,
        greaterThanOrEqualTo(980),
      );
      expect(effectiveSevenSegmentScale(1920, 1080, 2), 1);
    },
  );
  test(
    'real webcam decimal is recovered from pixels with real Tesseract',
    () async {
      final source = img.decodePng(
        File('test/fixtures/weight_ocr/ind570_webcam_570.png')
            .readAsBytesSync(),
      )!;
      final crop = img.copyCrop(
        source,
        x: 307,
        y: 137,
        width: 317,
        height: 104,
      );
      final bytes = Uint8List.fromList(img.encodePng(crop));
      final geometry = analyzeDisplayGeometry(bytes);
      expect(geometry.characters, hasLength(4), reason: '${geometry.toJson()}');
      expect(geometry.points, hasLength(1), reason: '${geometry.toJson()}');
      final result = await SevenSegmentWeightOcrService().recognize(bytes);
      expect(
        result.normalizedText,
        '570.0',
        reason: '${result.error} ${result.attempts.map((a) => a.toJson())}',
      );
      expect(result.weight, 570);
      expect(result.decimalDetected, isTrue);
      expect(result.success, isTrue);
    },
  );
}
