import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/seven_segment_recognition_engine.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_recognition_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_recognition_validation.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/display_perspective.dart';

import 'support/display_fixture.dart';
import 'support/manual_capture_mocks.dart';

import 'package:balanca_desktop/features/pesagem/manual_capture/capture_controller.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/manual_capture_services.dart';
import 'package:balanca_desktop/features/pesagem/manual_weighing_policy.dart';

class StubEngine implements WeightOcrService {
  StubEngine(this.result);
  final WeightOcrResult result;
  int calls = 0;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    calls++;
    return result;
  }
}

void main() {
  for (final text in [
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '13880',
    '12190',
    '13.42',
    '570.0',
    '13.99',
    '570.9',
  ]) {
    test('geometry decodes $text and truncates decimals', () {
      final result = recognizeDisplay(displayFixture(text), diagnostics: true);
      expect(
        result.success,
        isTrue,
        reason: '${result.error} ${result.diagnostics}',
      );
      expect(result.weight, double.parse(text).truncateToDouble());
      expect(result.rawText, text);
      expect(result.decimalDetected, text.contains('.'));
      expect(result.integerDigits, text.split('.').first);
      expect(result.attempts, hasLength(3));
    });
  }
  test('green and cyan, different resolutions and profiles', () {
    for (final profile in ['auto', 'ind560', 'ind570', 'generic']) {
      for (final height in [32, 64, 128]) {
        final source = img.decodePng(
          displayFixture('13880', digitHeight: height),
        )!;
        for (final p in source) {
          final value = p.r;
          p.setRgb(0, value, profile == 'ind570' ? 0 : value);
        }
        final result = recognizeDisplay(
          Uint8List.fromList(img.encodePng(source)),
          profile: profile,
        );
        expect(
          result.success,
          isTrue,
          reason: '$profile $height ${result.error} ${result.diagnostics}',
        );
        expect(result.weight, 13880);
      }
    }
  });
  test('actual IND570 calibrated fixture decodes 570.0 without Tesseract', () {
    final photo = CapturedPhoto(
      File('test/fixtures/weight_ocr/ind570_webcam_570.png').readAsBytesSync(),
      DateTime(2026),
    );
    // The old broad fixture includes keyboard and labels. Calibrate weight only.
    final capture = processCapture(
      photo,
      const DisplayRegion(left: .305, top: .38, width: .292, height: .278),
    );
    final result = recognizeDisplay(
      capture.ocrInput,
      profile: 'ind570',
      diagnostics: true,
    );
    expect(
      result.success,
      isTrue,
      reason: '${result.error} ${result.diagnostics}',
    );
    expect(result.rawText, '570.0');
    expect(result.weight, 570);
    expect(recognizeDisplay(capture.ocrInput).weight, 570);
  });
  test('rounded graphic 5 alone must not be decoded as segmented 6', () {
    final source = img.decodePng(
      File('test/fixtures/weight_ocr/ind570_webcam_570.png').readAsBytesSync(),
    )!;
    final crop = img.copyCrop(source, x: 318, y: 137, width: 70, height: 100);
    final bytes = Uint8List.fromList(img.encodePng(crop));
    for (final profile in ['auto', 'ind570']) {
      final result = recognizeDisplay(bytes, profile: profile);
      expect(
        result.success,
        isTrue,
        reason: '$profile ${result.error} ${result.diagnostics}',
      );
      expect(result.weight, 5);
    }
  });
  test('uncalibrated ROI cannot execute the primary engine', () async {
    final primary = StubEngine(
      const WeightOcrResult(weight: 100, confidence: 1),
    );
    final fallback = StubEngine(const WeightOcrResult(error: 'OCR_FAIL'));
    final result = await WeightRecognitionService(
      configuration: () => const WebcamConfiguration(),
      primary: primary,
      fallback: fallback,
    ).recognize(displayFixture('100'));
    expect(primary.calls, 0);
    expect(fallback.calls, 1);
    expect(result.diagnostics['primaryFailure'], 'SEGMENT_ROI_NOT_CALIBRATED');
  });
  test(
    'negative sign cannot silently become a positive geometric weight',
    () async {
      final digits = img.decodePng(displayFixture('13880'))!;
      final frame = img.Image(width: digits.width + 30, height: digits.height);
      img.fill(frame, color: img.ColorRgb8(12, 12, 12));
      img.compositeImage(frame, digits, dstX: 30);
      img.fillRect(
        frame,
        x1: 2,
        y1: 40,
        x2: 20,
        y2: 45,
        color: img.ColorRgb8(235, 235, 235),
      );
      final fallback = StubEngine(
        const WeightOcrResult(weight: 13880, confidence: 1),
      );
      final result = await WeightRecognitionService(
        configuration: () =>
            const WebcamConfiguration(region: DisplayRegion(calibrated: true)),
        fallback: fallback,
      ).recognize(Uint8List.fromList(img.encodePng(frame)));
      expect(result.success, isFalse);
      expect(result.error, 'SEGMENT_NEGATIVE');
      expect(fallback.calls, 0);
    },
  );
  test('primary success avoids Tesseract; zero is valid', () async {
    final fallback = StubEngine(const WeightOcrResult(error: 'OCR_FAIL'));
    final service = WeightRecognitionService(
      configuration: () =>
          const WebcamConfiguration(region: DisplayRegion(calibrated: true)),
      fallback: fallback,
    );
    final result = await service.recognize(displayFixture('0'));
    expect(result.success, isTrue);
    expect(result.weight, 0);
    expect(fallback.calls, 0);
  });
  test('primary failure enables Tesseract and truncates its result', () async {
    final fallback = StubEngine(
      const WeightOcrResult(rawText: '13.99', weight: 13.99, confidence: .99),
    );
    final service = WeightRecognitionService(
      configuration: () =>
          const WebcamConfiguration(region: DisplayRegion(calibrated: true)),
      primary: StubEngine(const WeightOcrResult(error: 'AMBIGUOUS')),
      fallback: fallback,
    );
    final result = await service.recognize(Uint8List(0));
    expect(fallback.calls, 1);
    expect(result.success, isTrue);
    expect(result.weight, 13);
    expect(result.strategy, startsWith('Tesseract fallback'));
  });
  test('total failure remains failure for manual fallback', () async {
    final service = WeightRecognitionService(
      configuration: () =>
          const WebcamConfiguration(region: DisplayRegion(calibrated: true)),
      primary: StubEngine(const WeightOcrResult(error: 'AMBIGUOUS')),
      fallback: StubEngine(const WeightOcrResult(error: 'OCR_FAIL')),
    );
    final result = await service.recognize(Uint8List(0));
    expect(result.success, isFalse);
    expect(result.weight, isNull);
  });
  test('implausible primary does not bypass validation', () async {
    final fallback = StubEngine(const WeightOcrResult(error: 'OCR_FAIL'));
    final service = WeightRecognitionService(
      configuration: () => const WebcamConfiguration(
        maximumWeight: 1000,
        region: DisplayRegion(calibrated: true),
      ),
      fallback: fallback,
    );
    final result = await service.recognize(displayFixture('13880'));
    expect(result.success, isFalse);
    expect(fallback.calls, 1);
  });
  WeightOcrResult reading(int w) =>
      WeightOcrResult(rawText: '$w', weight: w.toDouble(), confidence: .99);
  test('consecutive frames, isolated divergence and moving weight', () {
    final stable = WeightTemporalConsensus();
    expect(stable.observe(reading(13880)).consensus, isFalse);
    expect(stable.observe(reading(13880)).consensus, isFalse);
    expect(stable.observe(reading(13880)).consensus, isTrue);
    final noisy = WeightTemporalConsensus();
    WeightOcrResult? result;
    for (final w in [13880, 13880, 13800, 13880, 13880]) {
      result = noisy.observe(reading(w));
    }
    expect(result!.success, isTrue);
    expect(result.consensus, isTrue);
    expect(result.consensusCount, 4);
    expect(result.frameCount, 5);
    final moving = WeightTemporalConsensus();
    for (final w in [13850, 13860, 13870, 13880, 13890]) {
      expect(moving.observe(reading(w)).consensus, isFalse);
    }
  });
  test(
    'both engines fail: controller retains evidence and enables manual entry',
    () async {
      final camera = MockWeighingCameraService(), store = MockEvidenceStore();
      final services = ManualCaptureServices(
        cameraFactory: () => camera,
        ocr: WeightRecognitionService(
          configuration: () => const WebcamConfiguration(
            region: DisplayRegion(calibrated: true),
          ),
          primary: StubEngine(
            const WeightOcrResult(error: 'SEGMENT_AMBIGUOUS'),
          ),
          fallback: StubEngine(const WeightOcrResult(error: 'OCR_FAIL')),
        ),
        evidenceStore: store,
        configurationStore: store,
        processor: MockCaptureImageProcessor(),
      );
      services.configuration = const WebcamConfiguration(
        cameraId: 'usb-device-id',
        ocrEnabled: true,
      );
      final controller = ManualCaptureController(
        authorization: ManualAuthorization(
          user: 'operator',
          justification: 'Test',
        ),
        services: services,
      );
      try {
        await controller.initialize();
        await controller.capture();
        expect(controller.manualAllowed, isTrue);
        expect(controller.imagePath, isNotNull);
        expect(store.photos, isNotEmpty);
        expect(controller.finalWeight, isNull);
        controller.setManualWeight('570');
        final evidence = await controller.confirm();
        expect(evidence!.finalWeight, 570);
        expect(evidence.authorizer, 'operator');
        expect(evidence.justification, 'Test');
        expect(evidence.source, WeightSource.manualFallback);
      } finally {
        controller.dispose();
      }
    },
  );
  test('projective quadrilateral restores corners and non-affine centre', () {
    final gradient = img.Image(width: 201, height: 201);
    for (final p in gradient) {
      p.setRgb(p.x, p.y, 0);
    }
    const corners = [
      DisplayPoint(.1, .1),
      DisplayPoint(.9, .1),
      DisplayPoint(.7, .9),
      DisplayPoint(.3, .9),
    ];
    final result = rectifyDisplay(gradient, corners);
    expect(result.getPixel(0, 0).r, closeTo(20, 1));
    expect(
      result.getPixel(result.width - 1, result.height - 1).r,
      closeTo(140, 1),
    );
    final centre = result.getPixel(result.width ~/ 2, result.height ~/ 2);
    expect(centre.r, closeTo(100, 2));
    expect(centre.g, closeTo(126.7, 2));
  });
  test('homography identity, corner validation and evidence preservation', () {
    final source = img.decodePng(displayFixture('570.0'))!;
    const corners = [
      DisplayPoint(0, 0),
      DisplayPoint(1, 0),
      DisplayPoint(1, 1),
      DisplayPoint(0, 1),
    ];
    final rectified = rectifyDisplay(source, corners);
    expect(rectified.getBytes(), source.getBytes());
    const region = DisplayRegion(
      left: 0,
      top: 0,
      width: 1,
      height: 1,
      corners: corners,
    );
    expect(region.valid, isTrue);
    expect(DisplayRegion.fromJson(region.toJson()).corners, hasLength(4));
    expect(const DisplayRegion(corners: [DisplayPoint(0, 0)]).valid, isFalse);
    const crossed = DisplayRegion(
      corners: [
        DisplayPoint(0, 0),
        DisplayPoint(1, 1),
        DisplayPoint(1, 0),
        DisplayPoint(0, 1),
      ],
    );
    expect(crossed.valid, isFalse);
    final photo = CapturedPhoto(
      Uint8List.fromList(img.encodePng(source)),
      DateTime(2026),
    );
    final plain = processCapture(
      photo,
      const DisplayRegion(left: 0, top: 0, width: 1, height: 1),
    );
    final corrected = processCapture(photo, region);
    expect(corrected.evidence, plain.evidence);
    expect(recognizeDisplay(corrected.ocrInput).weight, 570);
  });
}
