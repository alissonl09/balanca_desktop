import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:balanca_desktop/features/pesagem/manual_weighing_policy.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_controller.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_dialog.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/captured_image_analysis.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/evidence_store.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/snapshot_weight_recognition.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';

import 'support/manual_capture_mocks.dart';

Uint8List panel() {
  final image = img.Image(width: 500, height: 240);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  for (final row in [
    (10, 10, '1.5'),
    (200, 10, '0.5'),
    (90, 80, '570.0'),
    (90, 190, '570.0'),
  ]) {
    img.drawString(
      image,
      row.$3,
      font: row.$2 == 80 ? img.arial48 : img.arial24,
      x: row.$1,
      y: row.$2,
      color: img.ColorRgb8(255, 255, 255),
    );
  }
  return Uint8List.fromList(img.encodePng(image));
}

OcrAttempt candidate(
  String name,
  String text,
  double confidence, {
  String? error,
}) => OcrAttempt(
  name,
  Uint8List(0),
  WeightOcrResult(rawText: text, confidence: confidence, error: error),
);
const configuration = WebcamConfiguration(
  ocrEnabled: true,
  decimalPlaces: 1,
  region: DisplayRegion(left: 0, top: 0, width: 1, height: 1, calibrated: true),
);

void main() {
  test(
    'snapshot metadata does not promote a single weak legacy OCR reading',
    () {
      final weak = const WeightOcrResult(
        weight: 570,
        confidence: .75,
      ).copyWith(diagnostics: {'analysisKind': 'snapshot'});
      expect(weak.success, isFalse);
      expect(weak.finalWeight, isNull);
    },
  );
  test(
    'largest aligned group wins over first number and small repeated weight',
    () {
      final principal = locatePrincipalDigits(img.decodePng(panel())!);
      expect(principal.ambiguous, isFalse);
      expect(principal.boxes.length, greaterThanOrEqualTo(4));
      expect(
        principal.boxes.every((b) => b.top > 70 && b.bottom < 150),
        isTrue,
      );
      expect(principal.image.height, lessThan(100));
    },
  );
  test(
    'pipeline support 2 vs 1 succeeds, ties/one result/rejected geometry fail',
    () {
      final result = selectSnapshotCandidates([
        candidate('gray', '5700', .58),
        candidate('otsu', '5700', .60),
        candidate('adaptive', '5708', .70),
        candidate('inverse', '', 0),
        candidate('geometry', '5700', .99, error: 'SEGMENT_CLIPPED'),
      ], configuration);
      expect(result.success, isTrue);
      expect(result.weight, 570);
      expect(result.diagnostics['pipelineSupport'], 2);
      expect(result.diagnostics['consensusScope'], 'pipelines');
      expect(
        selectSnapshotCandidates([
          candidate('gray', '5700', .99),
        ], configuration).success,
        isFalse,
      );
      expect(
        selectSnapshotCandidates([
          candidate('gray', '5700', .99),
          candidate('otsu', '5708', .99),
        ], configuration).success,
        isFalse,
      );
      expect(
        selectSnapshotCandidates([
          candidate('gray', '5700', .2),
          candidate('otsu', '5700', .2),
        ], configuration).success,
        isFalse,
      );
    },
  );
  test(
    'scale truncates and explicit configuration/range/format are required',
    () async {
      final rows = [
        candidate('gray', '1342', .8),
        candidate('otsu', '13,42', .8),
      ];
      expect(
        selectSnapshotCandidates(
          rows,
          configuration.copyWith(decimalPlaces: 2),
        ).weight,
        13,
      );
      expect(
        selectSnapshotCandidates([
          candidate('gray', '57O0', .99),
          candidate('otsu', '57O0', .99),
        ], configuration).success,
        isFalse,
      );
      expect(
        selectSnapshotCandidates([
          candidate('gray', '5700', .99),
          candidate('otsu', '5700', .99),
        ], configuration.copyWith(maximumWeight: 100)).success,
        isFalse,
      );
      final engine = SnapshotWeightRecognition(
        configuration: () => const WebcamConfiguration(),
      );
      expect(
        (await engine.recognize(panel())).error,
        'OCR_DECIMAL_CONFIG_REQUIRED',
      );
    },
  );
  test(
    'one photo produces four distinct variants without mutating its bytes',
    () async {
      final original = panel(), backup = Uint8List.fromList(panel());
      var calls = 0;
      final inputs = <Uint8List>[];
      final engine = SnapshotWeightRecognition(
        configuration: () => configuration,
        geometry: false,
        variant: (bytes) async {
          calls++;
          inputs.add(bytes);
          return const WeightOcrResult(rawText: '5700', confidence: .8);
        },
      );
      final result = await engine.recognize(original);
      expect(calls, 4);
      expect(result.success, isTrue);
      expect(result.weight, 570);
      expect(original, backup);
      expect(inputs[0], isNot(equals(inputs[1])));
      expect(result.attempts.length, 4);
    },
  );
  test(
    'camera and file share identical analysis; timestamp never reaches OCR',
    () async {
      final bytes = panel(), backup = Uint8List.fromList(bytes);
      final dir = await Directory.systemTemp.createTemp('snapshot_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File('${dir.path}/image.png').writeAsBytes(bytes);
      final seen = <Uint8List>[];
      final engine = _RecordingEngine(seen);
      const region = DisplayRegion(
        left: .1,
        top: .2,
        width: .8,
        height: .5,
        calibrated: true,
      );
      final config = configuration.copyWith(region: region);
      final time = DateTime(2026, 11, 8, 12, 30);
      final camera = await analyzeCapturedImage(
        CapturedPhoto(bytes, time),
        configuration: config,
        processor: LocalCaptureImageProcessor(),
        recognition: engine,
      );
      final disk = await analyzeCapturedImage(
        CapturedPhoto(await file.readAsBytes(), time),
        configuration: config,
        processor: LocalCaptureImageProcessor(),
        recognition: engine,
      );
      expect(seen[0], seen[1]);
      expect(bytes, backup);
      expect(camera.capture.roiWidth, 400);
      expect(camera.capture.roiHeight, 120);
      expect(camera.capture.evidence, isNot(equals(camera.capture.original)));
      expect(camera.result.weight, disk.result.weight);
      final clean = img.decodePng(camera.capture.original!)!;
      final evidence = img.decodeJpg(camera.capture.evidence)!;
      expect(evidence.width, 640);
      expect(clean.width, 500);
      expect(img.decodeImage(seen.first)!.height, 120);
    },
  );
  test('original is saved before analysis; failure/retry/manual keep immutable identities', () async {
    final camera = MockWeighingCameraService()
      ..photo = CapturedPhoto(panel(), DateTime(2026));
    final store = MockEvidenceStore();
    final blocked = Completer<WeightOcrResult>(), started = Completer<void>();
    final ocr = MockWeightOcrService()
      ..pending = () {
        expect(store.originals.length, 1);
        expect(store.photos.length, 1);
        started.complete();
        return blocked.future;
      };
    final services = mockCaptureServices(
      configured: true,
      camera: camera,
      store: store,
      ocr: ocr,
    );
    final controller = ManualCaptureController(
      authorization: ManualAuthorization(
        user: 'operador',
        justification: 'Contingência',
      ),
      services: services,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(camera.captures, 0);
    expect(ocr.calls, 0);
    final pending = controller.capture();
    await started.future;
    expect(controller.capturedImage, isNotNull);
    expect(controller.stage, CaptureStage.ocrProcessing);
    expect(controller.canConfirm, isFalse);
    blocked.complete(const WeightOcrResult(error: 'OCR_SEM_LEITURA'));
    await pending;
    final first = controller.attemptId;
    expect(controller.manualAllowed, isTrue);
    final previous = controller.imagePath;
    controller.resumeCamera();
    expect(controller.capturedImage, isNull);
    expect(ocr.calls, 1);
    ocr.pending = null;
    ocr.result = const WeightOcrResult(error: 'OCR_SEM_LEITURA');
    await controller.capture();
    expect(camera.captures, 2);
    expect(controller.attemptId, isNot(first));
    expect(controller.imagePath, isNot(previous));
    controller.setManualWeight('570');
    final evidence = await controller.confirm();
    expect(evidence!.source, WeightSource.manualFallback);
    expect(store.photos.containsKey(evidence.imagePath), isTrue);
    expect(store.originals[evidence.originalImagePath], camera.photo.bytes);
  });
  testWidgets(
    'preview does not execute OCR and only capture unlocks confirmation',
    (tester) async {
      final camera = MockWeighingCameraService(), ocr = MockWeightOcrService();
      final services = mockCaptureServices(
        configured: true,
        camera: camera,
        ocr: ocr,
        liveOcr: ocr,
      );
      final controller = ManualCaptureController(
        authorization: ManualAuthorization(
          user: 'operador',
          justification: 'Contingência',
        ),
        services: services,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ManualCaptureDialog(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(ocr.calls, 0);
      expect(camera.captures, 0);
      expect(controller.canConfirm, isFalse);
      expect(find.text('Capturar peso'), findsOneWidget);
      await tester.runAsync(controller.capture);
      await tester.pumpAndSettle();
      expect(camera.captures, 1);
      expect(ocr.calls, 1);
      expect(controller.canConfirm, isTrue);
      expect(find.text('Confirmar'), findsOneWidget);
      expect(find.text('Capturar novamente'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'local original storage preserves exact bytes and refuses overwrite',
    () async {
      final dir = await Directory.systemTemp.createTemp('snapshot_store_');
      addTearDown(() => dir.delete(recursive: true));
      final store = LocalManualWeighingStore(
        directory: () => Future.value(dir),
      );
      final bytes = panel();
      final path = await store.saveOriginal('unique', bytes);
      expect(await File(path).readAsBytes(), bytes);
      await expectLater(
        store.saveOriginal('unique', Uint8List(1)),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}

class _RecordingEngine implements WeightOcrService {
  _RecordingEngine(this.images);
  final List<Uint8List> images;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    images.add(Uint8List.fromList(image));
    return const WeightOcrResult(rawText: '5700', weight: 570, confidence: .99);
  }
}
