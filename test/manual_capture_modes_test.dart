import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:balanca_desktop/features/configuracoes/manual_webcam_settings.dart';
import 'package:balanca_desktop/features/pesagem/manual_weighing_policy.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_controller.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_dialog.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/live_weight_reader.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/live_weight_ocr_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';

import 'support/manual_capture_mocks.dart';
import 'support/display_fixture.dart';

class QuickEngine implements OcrVariantEngine {
  int calls = 0;
  @override
  Future<WeightOcrResult> recognizeVariant(
    Uint8List image, {
    String model = 'eng',
    String? tessdataDirectory,
    int psm = 7,
    bool restrict = false,
    bool numericOnly = false,
    String whitelist = '0123456789.-',
  }) async {
    calls++;
    expect(model, 'eng');
    expect(psm, 7);
    expect(numericOnly, isTrue);
    expect(whitelist, '0123456789.-');
    return parseWeightText('5700', .99).copyWith(model: model, psm: psm);
  }
}

void main() {
  ManualCaptureController controllerFor(services) => ManualCaptureController(
    authorization: ManualAuthorization(
      user: 'operador',
      justification: 'Contingência',
    ),
    services: services,
  );

  test('OCR defaults off and survives station configuration roundtrip', () {
    expect(const WebcamConfiguration().ocrEnabled, isFalse);
    expect(WebcamConfiguration.fromJson({'enabled': true}).ocrEnabled, isFalse);
    final config = const WebcamConfiguration().copyWith(ocrEnabled: true);
    expect(WebcamConfiguration.fromJson(config.toJson()).ocrEnabled, isTrue);
    expect(config.copyWith(enabled: false).ocrEnabled, isTrue);
  });
  test(
    'photo-only records exactly one photograph and never calls OCR',
    () async {
      final camera = MockWeighingCameraService(),
          ocr = MockWeightOcrService(),
          store = MockEvidenceStore();
      final services = mockCaptureServices(
        camera: camera,
        ocr: ocr,
        liveOcr: ocr,
        store: store,
        configured: true,
      );
      services.configuration = services.configuration.copyWith(
        ocrEnabled: false,
      );
      final c = controllerFor(services);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.manualAllowed, isFalse);
      await c.capture();
      expect(camera.captures, 1);
      expect(ocr.calls, 0);
      expect(c.stage, CaptureStage.manualEntry);
      expect(c.failureReason, isNull);
      expect(c.manualAllowed, isTrue);
      expect(c.canConfirm, isFalse);
      c.setManualWeight('570,0');
      final evidence = await c.confirm();
      expect(evidence!.finalWeight, 570);
      expect(evidence.source, WeightSource.manualPhoto);
      expect(evidence.toJson()['ocrEnabled'], isFalse);
      expect(evidence.failureReason, isNull);
      expect(store.photos, hasLength(1));
    },
  );
  test(
    'photo-only processor skips crop, filters and OCR PNG encoding',
    () async {
      final photo = CapturedPhoto(displayFixture('570.0'), DateTime(2026));
      final capture = await LocalCaptureImageProcessor().processEvidence(photo);
      expect(img.decodeJpg(capture.evidence), isNotNull);
      expect(capture.ocrInput, isEmpty);
      expect(capture.original, isNull);
      expect(capture.roiWidth, 0);
    },
  );
  test(
    'live OCR uses only two passes and keeps the detected decimal',
    () async {
      final engine = QuickEngine();
      final result = await LiveWeightOcrService(engine: engine)
          .recognize(displayFixture('570.0'));
      expect(engine.calls, 2);
      expect(result.success, isTrue);
      expect(result.normalizedText, '570.0');
      expect(result.decimalDetected, isTrue);
    },
  );
  test(
    'live reader expires green while the next OCR is still pending',
    () async {
      final ocr = MockWeightOcrService();
      ocr.sequence.addAll(List.filled(3, parseWeightText('570.0', .99)));
      final blocked = Completer<WeightOcrResult>();
      ocr.pending = () => blocked.future;
      final ready = Completer<void>(), expired = Completer<void>();
      late LiveWeightReader reader;
      reader = LiveWeightReader(
        camera: MockWeighingCameraService(),
        processor: MockCaptureImageProcessor(),
        ocr: ocr,
        configuration: const WebcamConfiguration(ocrEnabled: true),
        interval: const Duration(milliseconds: 2),
        freshness: const Duration(milliseconds: 50),
        onChanged: () {
          if (reader.ready && !ready.isCompleted) ready.complete();
          if (ready.isCompleted && !reader.ready && !expired.isCompleted) {
            expired.complete();
          }
        },
      );
      reader.start();
      await ready.future.timeout(const Duration(seconds: 2));
      expect(reader.result.normalizedText, '570.0');
      await expired.future.timeout(const Duration(seconds: 2));
      expect(reader.ready, isFalse);
      expect(reader.photo, isNull);
      blocked.complete(parseWeightText('570.0', .99));
      await reader.stop();
    },
  );
  test(
    'closing live reader ignores a late OCR result and does not queue captures',
    () async {
      final camera = MockWeighingCameraService(), ocr = MockWeightOcrService();
      final pending = Completer<WeightOcrResult>(), started = Completer<void>();
      ocr.pending = () {
        started.complete();
        return pending.future;
      };
      var updates = 0;
      final reader = LiveWeightReader(
        camera: camera,
        processor: MockCaptureImageProcessor(),
        ocr: ocr,
        configuration: const WebcamConfiguration(ocrEnabled: true),
        onChanged: () => updates++,
      );
      reader.start();
      await started.future;
      final stopped = reader.stop();
      pending.complete(parseWeightText('570.0', .99));
      await stopped;
      expect(updates, 0);
      expect(reader.ready, isFalse);
      expect(camera.captures, 1);
    },
  );
  test('low confidence never produces a green live reading', () async {
    final ocr = MockWeightOcrService()..result = parseWeightText('5700', .5);
    final observed = Completer<void>();
    final reader = LiveWeightReader(
      camera: MockWeighingCameraService(),
      processor: MockCaptureImageProcessor(),
      ocr: ocr,
      configuration: const WebcamConfiguration(ocrEnabled: true),
      onChanged: () {
        if (!observed.isCompleted) observed.complete();
      },
    );
    reader.start();
    await observed.future;
    await reader.stop();
    expect(reader.ready, isFalse);
    expect(reader.photo, isNull);
  });
  testWidgets('photo-only capture unlocks the empty weight field', (
    tester,
  ) async {
    final ocr = MockWeightOcrService();
    final services = mockCaptureServices(
      configured: true,
      ocr: ocr,
      liveOcr: ocr,
    );
    services.configuration = services.configuration.copyWith(ocrEnabled: false);
    final c = controllerFor(services);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManualCaptureDialog(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Capturar foto'));
    await tester.tap(find.text('Capturar foto'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('manual-weight')),
    );
    expect(field.enabled, isTrue);
    expect(field.controller!.text, isEmpty);
    expect(ocr.calls, 0);
    await tester.enterText(
      find.byKey(const ValueKey('manual-weight')),
      '570.0',
    );
    expect(c.finalWeight, 570);
    await tester.pumpWidget(const SizedBox());
  });
  for (final mode in ['photo', 'ocr', 'fallback']) {
    testWidgets('captured photo and return to camera in $mode mode', (
      tester,
    ) async {
      final camera = MockWeighingCameraService()
        ..photo = CapturedPhoto(displayFixture('570.0'), DateTime(2026));
      final ocr = MockWeightOcrService()
        ..result = mode == 'fallback'
            ? const WeightOcrResult(error: 'OCR_ENGINE_INDISPONIVEL')
            : parseWeightText('570.0', .99);
      final store = MockEvidenceStore();
      final services = mockCaptureServices(
        configured: true,
        camera: camera,
        ocr: ocr,
        store: store,
      );
      services.configuration = services.configuration.copyWith(
        ocrEnabled: mode != 'photo',
      );
      final c = controllerFor(services);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ManualCaptureDialog(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('captured-weight-image')), findsNothing);
      await tester.runAsync(c.capture);
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(
        find.byKey(const ValueKey('captured-weight-image')),
      );
      expect((image.image as MemoryImage).bytes, store.photos[c.imagePath]);
      expect(
        tester
            .widget<CameraEvidencePreview>(find.byType(CameraEvidencePreview))
            .capturedImage,
        isNotNull,
      );
      if (c.manualAllowed) c.setManualWeight('570');
      expect(c.canConfirm, isTrue);
      final captures = camera.captures;
      await tester.ensureVisible(find.text('Voltar para a câmera'));
      await tester.tap(find.text('Voltar para a câmera'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('captured-weight-image')), findsNothing);
      expect(c.stage, CaptureStage.cameraReady);
      expect(c.canConfirm, isFalse);
      expect(c.manualWeight, isNull);
      expect(camera.captures, captures);
      final label = mode == 'photo' ? 'Capturar foto' : 'Capturar peso';
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(camera.captures, greaterThan(captures));
      expect(
        find.byKey(const ValueKey('captured-weight-image')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
  test(
    'capturing live result preserves its photograph without rerunning OCR',
    () async {
      final ocr = MockWeightOcrService()
        ..result = parseWeightText('570.0', .99);
      final camera = MockWeighingCameraService(), store = MockEvidenceStore();
      final services = mockCaptureServices(
        camera: camera,
        store: store,
        configured: true,
        liveOcr: ocr,
      );
      final c = controllerFor(services);
      addTearDown(c.dispose);
      final ready = Completer<void>();
      c.addListener(() {
        if (c.previewRecognized && !ready.isCompleted) ready.complete();
      });
      await c.initialize();
      await ready.future.timeout(const Duration(seconds: 3));
      expect(c.recognizedText, '570.0');
      expect(c.canConfirm, isFalse);
      expect(store.photos, isEmpty); // no disk evidence for preview frames
      final calls = ocr.calls, captures = camera.captures;
      await c.capture();
      expect(ocr.calls, calls);
      expect(camera.captures, captures);
      expect(c.stage, CaptureStage.ocrSuccess);
      expect(c.manualAllowed, isFalse);
      expect(c.canConfirm, isTrue);
      expect(store.photos, hasLength(1));
      expect(c.capturedImage, store.photos[c.imagePath]);
      c.resumeCamera();
      expect(c.capturedImage, isNull);
      expect(c.canConfirm, isFalse);
      final resumed = Completer<void>();
      c.addListener(() {
        if (c.previewRecognized && !resumed.isCompleted) resumed.complete();
      });
      await resumed.future.timeout(const Duration(seconds: 3));
      await c.capture();
      c.setManualWeight('999');
      expect(c.finalWeight, 570);
      expect((await c.confirm())!.source, WeightSource.cameraOcr);
    },
  );
  testWidgets(
    'OCR setting is hidden when manual weighing is disabled and persists choices',
    (tester) async {
      final services = mockCaptureServices(configured: true);
      Widget screen(bool enabled) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ManualWebcamSettings(
              services: services,
              manualWeighingEnabled: enabled,
            ),
          ),
        ),
      );
      await tester.pumpWidget(screen(false));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<bool>), findsNothing);
      await tester.pumpWidget(screen(true));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Não ler a imagem: foto e digitação do peso').last,
      );
      await tester.pumpAndSettle();
      expect(services.configuration.ocrEnabled, isFalse);
    },
  );
  testWidgets(
    'live result fills locked field and green indicator before capture',
    (tester) async {
      final ocr = MockWeightOcrService()
        ..result = parseWeightText('570.0', .99);
      final services = mockCaptureServices(configured: true, liveOcr: ocr);
      final c = controllerFor(services);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ManualCaptureDialog(controller: c)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('manual-weight')),
      );
      expect(field.controller!.text, '570.0');
      expect(field.enabled, isFalse);
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('live-ocr-indicator')))
            .color,
        Colors.green,
      );
      expect(c.canConfirm, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('real Tesseract fast path recognizes webcam decimal using two passes', () async {
    final source = img.decodePng(
      File('test/fixtures/weight_ocr/ind570_webcam_570.png').readAsBytesSync(),
    )!;
    final crop = img.copyCrop(source, x: 307, y: 137, width: 317, height: 104);
    final result = await LiveWeightOcrService().recognize(
      Uint8List.fromList(img.encodePng(crop)),
    );
    expect(
      result.success,
      isTrue,
      reason: '${result.error}: ${result.attempts.map((a) => a.toJson())}',
    );
    expect(result.normalizedText, '570.0');
    expect(result.attempts, hasLength(2));
    // Recorded for comparison; wall-clock speed depends on the station.
    // ignore: avoid_print
    print(
      'Live OCR real: ${result.elapsedMs} ms, confidence ${result.confidence}',
    );
  });
}
