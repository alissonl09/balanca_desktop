import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/dominant_weight_line.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';

void main() {
  for (final fixture in {
    '12190': 12190.0,
    'zero': 0.0,
    '10000': 10000.0,
    'ind560_decimal': 0.0,
    'ind570_decimal': 570.0,
    'panel_570': 570.0,
  }.entries) {
    test('real Tesseract recognizes ${fixture.key} fixture', () async {
      final engine = TesseractWeightOcrService();
      try {
        final version = await Process.run(engine.executable, ['--version']);
        if (version.exitCode != 0) {
          markTestSkipped('Engine indisponível; prepare o runtime Windows.');
          return;
        }
      } on ProcessException {
        markTestSkipped('Engine indisponível; prepare o runtime Windows.');
        return;
      }
      final result = await engine.recognize(
        File('test/fixtures/weight_ocr/${fixture.key}.png').readAsBytesSync(),
      );
      expect(
        result.success,
        isTrue,
        reason: '${result.error}: ${result.attempts.map((a) => a.toJson())}',
      );
      expect(result.weight, fixture.value);
    });
  }
  test(
    'panel crop preserves distant minus and decimal, keeps evidence whole',
    () {
      final source = img.decodePng(
        File('test/fixtures/weight_ocr/panel_570.png').readAsBytesSync(),
      )!;
      final crop = isolateDominantWeightLine(source);
      expect(crop.height, lessThan(source.height / 2));
      expect(crop.width, lessThan(source.width));
      final signed = img.Image.from(source);
      img.fillRect(
        signed,
        x1: 10,
        y1: 128,
        x2: 35,
        y2: 133,
        color: img.ColorRgb8(225, 225, 225),
      );
      final signedCrop = isolateDominantWeightLine(signed);
      expect(signedCrop.width, greaterThan(crop.width));
      expect(signedCrop.height, crop.height);
      // Locate the added sign in the crop, so a remote minus cannot be dropped.
      expect(signedCrop.getPixel(12, 25).r, greaterThan(200));
      final variants = prepareOcrVariants(
        Uint8List.fromList(img.encodePng(source)),
      );
      for (final value in variants.values) {
        expect(img.decodePng(value)!.width, greaterThan(300));
      }
    },
  );

  test('two similarly sized lines do not select a convenient reading', () {
    final image = img.Image(width: 640, height: 260);
    img.fill(image, color: img.ColorRgb8(0, 0, 0));
    for (final y in [30, 130]) {
      img.drawString(
        image,
        '570.0',
        font: img.arial48,
        x: 90,
        y: y,
        color: img.ColorRgb8(255, 255, 255),
      );
    }
    expect(identical(isolateDominantWeightLine(image), image), isTrue);
  });
  test('negative panel cannot become an accepted positive weight', () async {
    final engine = TesseractWeightOcrService();
    try {
      await Process.run(engine.executable, ['--version']);
    } on ProcessException {
      markTestSkipped('Engine indisponível; prepare o runtime Windows.');
      return;
    }
    final result = await engine.recognize(
      File('test/fixtures/weight_ocr/panel_negative.png').readAsBytesSync(),
    );
    expect(
      result.success && result.weight! >= 0,
      isFalse,
      reason: '${result.attempts.map((a) => a.toJson())}',
    );
  });
  test('parser accepts display decimals and explicit space grouping only', () {
    for (final entry in {
      '12190 kg': 12190,
      '12 190': 12190,
      '0': 0,
      '10000': 10000,
      '570.0': 570,
      '0.00': 0,
      '0.000': 0,
      '12,190': 12.190,
      '-12.5': -12.5,
    }.entries) {
      final result = parseWeightText(entry.key, .99);
      expect(result.success, isTrue, reason: entry.key);
      expect(result.weight, entry.value);
    }
    for (final raw in [
      'I2I90',
      '1219O',
      '12O90',
      '12:45',
      'SN123',
      '12190 123',
      '12.190.000',
      'kg',
      '',
      '570.0 PT 570.0',
    ]) {
      expect(parseWeightText(raw, .99).success, isFalse, reason: raw);
    }
    expect(parseWeightText('12190', .89).success, isFalse);
    expect(parseWeightText('12190', double.nan).success, isFalse);
  });

  OcrAttempt attempt(String raw, {double confidence = .99}) =>
      OcrAttempt('test', Uint8List(0), parseWeightText(raw, confidence));
  test(
    'variant consensus rejects conflicting, weak and constrained-only output',
    () {
      expect(
        selectConsistentOcr([attempt('12190'), attempt('12190')]).success,
        isTrue,
      );
      expect(selectConsistentOcr([attempt('12190')]).success, isFalse);
      expect(
        selectConsistentOcr([
          attempt('12190'),
          attempt('12180', confidence: .1),
          attempt('12190'),
        ]).error,
        'OCR_VARIANTES_DIVERGENTES',
      );
      expect(
        selectConsistentOcr([
          attempt('SN12190'),
          attempt('12190'),
          attempt('12190'),
        ]).success,
        isFalse,
      );
    },
  );

  for (final name in [
    '12190',
    'zero',
    '10000',
    'ind560_decimal',
    'ind570_decimal',
    'low_contrast',
    'mirrored',
    'noise',
    'perspective',
    'no_number',
    'two_numbers',
  ]) {
    test('fixture $name: real crop and preprocessing, separate evidence', () {
      final bytes = File('test/fixtures/weight_ocr/$name.png')
          .readAsBytesSync();
      final processed = processCapture(
        CapturedPhoto(
          bytes,
          DateTime(2026, 11, 4),
          mirrorHorizontally: name == 'mirrored',
        ),
        const DisplayRegion(left: 0, top: 0, width: 1, height: 1),
      );
      expect(processed.ocrInput, processed.original);
      expect(processed.evidence, isNot(processed.ocrInput));
      final variants = prepareOcrVariants(processed.ocrInput);
      expect(variants.length, 3);
      for (final variant in variants.values) {
        final decoded = img.decodePng(variant)!;
        expect(decoded.width, greaterThan(360));
        expect(decoded.every((p) => p.r == p.g && p.g == p.b), isTrue);
      }
      if (name == 'mirrored') {
        expect(
          processed.ocrInput,
          File('test/fixtures/weight_ocr/12190.png').readAsBytesSync(),
        );
      }
    });
  }

  test('invalid ROI rejected; station settings survive JSON', () {
    const config = WebcamConfiguration(
      cameraId: 'camera',
      region: DisplayRegion(left: .2, top: .3, width: .5, height: .2),
      minimumWeight: 10,
      maximumWeight: 50000,
      diagnostics: true,
    );
    final restored = WebcamConfiguration.fromJson(config.toJson());
    expect(restored.region.toJson(), config.region.toJson());
    expect(restored.minimumWeight, 10);
    expect(restored.maximumWeight, 50000);
    expect(restored.copyWith(enabled: false).diagnostics, isTrue);
    expect(const DisplayRegion(left: .9, width: .5).valid, isFalse);
  });
}
