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
import 'package:balanca_desktop/features/pesagem/manual_capture/evidence_store.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';

import 'support/manual_capture_mocks.dart';

void main() {
  late MockWeighingCameraService camera;
  late MockWeightOcrService ocr;
  late MockEvidenceStore store;
  late ManualCaptureController controller;
  setUp(() {
    camera = MockWeighingCameraService();
    ocr = MockWeightOcrService();
    store = MockEvidenceStore();
    controller = ManualCaptureController(
      authorization: ManualAuthorization(
        user: 'balanca',
        justification: 'Serial caiu',
      ),
      services: mockCaptureServices(
        camera: camera,
        ocr: ocr,
        store: store,
        configured: true,
      ),
    );
  });
  tearDown(() => controller.dispose());

  test(
    'enumera câmeras e inicia somente quando etapa autorizada é inicializada',
    () async {
      expect((await camera.listCameras()).single.name, 'USB Camera');
      expect(camera.starts, 0);
      expect(
        () => ManualAuthorization(user: 'balanca', justification: ' '),
        throwsArgumentError,
      );
      await controller.initialize();
      expect(camera.selected, 'usb-device-id');
      expect(controller.stage, CaptureStage.cameraReady);
      expect(controller.manualAllowed, isFalse);
      expect(controller.canConfirm, isFalse);
    },
  );
  test(
    'OCR válido preenche peso, bloqueia manual e registra CAMERA_OCR',
    () async {
      await controller.initialize();
      await controller.capture();
      expect(controller.finalWeight, 12190);
      expect(camera.captures, 3);
      expect(controller.stableReadings, 3);
      expect(store.records.length, 3);
      expect(controller.manualAllowed, isFalse);
      controller.setManualWeight('99');
      expect(controller.finalWeight, 12190);
      final evidence = await controller.confirm();
      expect(evidence!.source.code, 'CAMERA_OCR');
      expect(evidence.authorizer, 'balanca');
      expect(evidence.justification, 'Serial caiu');
      expect(evidence.imagePath, isNotNull);
      expect(camera.stops, 1);
    },
  );
  test('peso zero é leitura válida e pode ser confirmado', () async {
    ocr.result = const WeightOcrResult(
      rawText: '0 kg',
      weight: 0,
      confidence: .99,
    );
    await controller.initialize();
    await controller.capture();
    expect(controller.canConfirm, isTrue);
    expect((await controller.confirm())!.finalWeight, 0);
  });
  test(
    'changing frames without 80 percent consensus never propose weight',
    () async {
      ocr.sequence.addAll([
        const WeightOcrResult(weight: 12190, confidence: .99),
        const WeightOcrResult(weight: 12180, confidence: .99),
        const WeightOcrResult(weight: 12190, confidence: .99),
        const WeightOcrResult(weight: 12180, confidence: .99),
        const WeightOcrResult(weight: 12190, confidence: .99),
      ]);
      await controller.initialize();
      await controller.capture();
      expect(controller.failureReason, 'OCR_LEITURA_INSTAVEL');
      expect(controller.finalWeight, isNull);
      expect(controller.manualAllowed, isTrue);
      expect(controller.stableReadings, 3);
      expect(camera.captures, 5);
      expect(store.photos.length, 5);
    },
  );
  test('out of station range and negative OCR never proposed', () async {
    for (final weight in [-1.0, 100001.0]) {
      ocr.result = WeightOcrResult(weight: weight, confidence: .99);
      await controller.initialize();
      await controller.capture();
      expect(controller.failureReason, 'OCR_FORA_DA_FAIXA');
      expect(controller.finalWeight, isNull);
      expect(controller.imagePath, isNotNull);
    }
  });
  test('570.0 majority survives a 5700 frame, preserves last photo and requires confirmation', () async {
    ocr.sequence.addAll([
      for (final raw in ['570.0', '570.0', '5700', '570.0', '570.0'])
        parseWeightText(raw, .99),
    ]);
    await controller.initialize();
    await controller.capture();
    expect(controller.stage, CaptureStage.ocrSuccess);
    expect(controller.ocr.normalizedText, '570.0');
    expect(controller.ocr.consensusReadings, 4);
    expect(controller.ocr.finalConfidence, .98);
    expect(camera.captures, 5);
    expect(store.records.every((r) => r.confirmedAt == null), isTrue);
    expect(controller.imagePath, store.records.last.imagePath);
    expect(controller.manualAllowed, isFalse);
    expect((await controller.confirm())!.finalWeight, 570);
  });
  test(
    'hallucinated minus with zero confidence keeps OCR failure and evidence',
    () async {
      ocr.result = const WeightOcrResult(
        rawText: '-570.0',
        weight: -570,
        confidence: 0,
        error: 'OCR_BAIXA_CONFIANCA',
      );
      await controller.initialize();
      await controller.capture();
      expect(controller.failureReason, 'OCR_BAIXA_CONFIANCA');
      expect(controller.manualAllowed, isTrue);
      expect(controller.canConfirm, isFalse);
      expect(controller.imagePath, isNotNull);
      controller.setManualWeight('570');
      final evidence = await controller.confirm();
      expect(evidence!.source, WeightSource.manualFallback);
      expect(evidence.failureReason, 'OCR_BAIXA_CONFIANCA');
      expect(store.photos.containsKey(evidence.imagePath), isTrue);
    },
  );
  for (final result in [
    const WeightOcrResult(error: 'OCR_SEM_LEITURA'),
    const WeightOcrResult(
      weight: 20,
      confidence: .4,
      error: 'OCR_BAIXA_CONFIANCA',
    ),
  ]) {
    test('${result.error} libera fallback e preserva imagem', () async {
      ocr.result = result;
      await controller.initialize();
      await controller.capture();
      expect(controller.manualAllowed, isTrue);
      expect(controller.canConfirm, isFalse);
      controller.setManualWeight('-1');
      expect(controller.canConfirm, isFalse);
      controller.setManualWeight('12,5');
      final evidence = await controller.confirm();
      expect(evidence!.source.code, 'MANUAL_FALLBACK');
      expect(evidence.finalWeight, 12.5);
      expect(store.photos.containsKey(evidence.imagePath), isTrue);
      expect(evidence.failureReason, result.error);
    });
  }
  test(
    'câmera indisponível não trava operação e registra ausência de evidência',
    () async {
      camera.unavailable = true;
      await controller.initialize();
      expect(controller.manualAllowed, isTrue);
      controller.setManualWeight('10');
      final evidence = await controller.confirm();
      expect(evidence!.imagePath, isNull);
      expect(evidence.photoFailureReason, 'CAMERA_INDISPONIVEL');
    },
  );
  test('câmera não configurada libera fallback sem abrir hardware', () async {
    final c = ManualCaptureController(
      authorization: controller.authorization,
      services: mockCaptureServices(camera: camera),
    );
    await c.initialize();
    expect(c.failureReason, 'CAMERA_NAO_CONFIGURADA');
    expect(camera.starts, 0);
    c.dispose();
  });
  test('captura falha preserva foto da tentativa anterior', () async {
    await controller.initialize();
    await controller.capture();
    final path = controller.imagePath;
    camera.captureFails = true;
    await controller.capture();
    expect(controller.manualAllowed, isTrue);
    expect(controller.imagePath, path);
    controller.setManualWeight('10');
    expect((await controller.confirm())!.imagePath, path);
  });
  test(
    'OCR assíncrono mantém estado de progresso e não libera digitação',
    () async {
      final pending = Completer<WeightOcrResult>();
      final entered = Completer<void>();
      ocr.pending = () {
        if (!entered.isCompleted) entered.complete();
        return pending.future;
      };
      await controller.initialize();
      final capture = controller.capture();
      await entered.future;
      expect(controller.stage, CaptureStage.ocrProcessing);
      expect(controller.manualAllowed, isFalse);
      expect(controller.canConfirm, isFalse);
      pending.complete(ocr.result);
      await capture;
      expect(controller.stage, CaptureStage.ocrSuccess);
    },
  );
  test('fechar durante OCR ignora retorno tardio e libera câmera', () async {
    final pending = Completer<WeightOcrResult>();
    final entered = Completer<void>();
    ocr.pending = () {
      if (!entered.isCompleted) entered.complete();
      return pending.future;
    };
    await controller.initialize();
    final capture = controller.capture();
    await entered.future;
    await controller.close();
    pending.complete(ocr.result);
    await capture;
    expect(camera.stops, 1);
    expect(controller.stage, CaptureStage.ocrProcessing);
  });
  test('falha de armazenamento impede perda silenciosa de auditoria', () async {
    await controller.initialize();
    await controller.capture();
    store.failSave = true;
    expect(await controller.confirm(), isNull);
    expect(controller.persistenceError, isNotNull);
    expect(controller.canConfirm, isTrue);
  });
  test(
    'timestamp usa data/hora local e é desenhado nos pixels finais',
    () async {
      final time = DateTime(2026, 11, 4, 12, 45, 31);
      expect(localTimestamp(time), '04/11/2026 12:45:31');
      expect(localTimestamp(time.toUtc()), localTimestamp(time));
      final blank = img.Image(width: 640, height: 480);
      final processed = await LocalCaptureImageProcessor().process(
        CapturedPhoto(Uint8List.fromList(img.encodePng(blank)), time),
        const DisplayRegion(),
      );
      final evidence = img.decodeJpg(processed.evidence)!;
      expect(evidence.any((p) => p.y >= 440 && p.r > 180 && p.g > 180), isTrue);
      final crop = img.decodePng(processed.ocrInput)!;
      expect(crop.width, 512);
      expect(crop.height, 240);
      expect(crop.every((p) => p.r == 0), isTrue);
    },
  );
  test('foto inválida é rejeitada', () {
    expect(
      () => processCapture(camera.photo, const DisplayRegion()),
      throwsA(isA<CaptureFailure>()),
    );
  });
  String tsv(List<(String, int)> words) =>
      'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n${words.map((w) => '5\t1\t1\t1\t1\t1\t0\t0\t100\t30\t${w.$2}\t${w.$1}').join('\n')}';
  test('perfil OCR usa confiança real e rejeita horário, série e múltiplos números', () {
    expect(
      interpretTesseractTsv(tsv([('12190', 98), ('kg', 97)])).success,
      isTrue,
    );
    expect(interpretTesseractTsv(tsv([('0', 99)])).weight, 0);
    expect(interpretTesseractTsv(tsv([('12190', 20)])).success, isFalse);
    for (final text in ['12:45:31', 'SN12345', '12190 123', 'SERIAL 12345']) {
      expect(
        interpretTesseractTsv(tsv([(text, 99)])).success,
        isFalse,
        reason: text,
      );
    }
  });
  test('engine ausente retorna erro explícito, sem simular OCR', () async {
    final result = await TesseractWeightOcrService(
      executable: 'missing_balanca_ocr_engine',
    ).recognize(Uint8List(1));
    expect(result.error, 'OCR_ENGINE_INDISPONIVEL');
    expect(result.weight, isNull);
  });

  test('adapter executa Tesseract real quando instalado (imagem sintética)', () async {
    try {
      final version = await Process.run(
        TesseractWeightOcrService().executable,
        ['--version'],
      );
      if (version.exitCode != 0) {
        markTestSkipped('Tesseract não instalado nesta estação de teste.');
        return;
      }
    } on ProcessException {
      markTestSkipped('Tesseract não instalado nesta estação de teste.');
      return;
    }
    final image = img.Image(width: 640, height: 160);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.drawString(
      image,
      '12190 kg',
      font: img.arial48,
      x: 40,
      y: 50,
      color: img.ColorRgb8(0, 0, 0),
    );
    final result = await TesseractWeightOcrService().recognize(
      Uint8List.fromList(img.encodePng(image)),
    );
    expect(result.weight, 12190, reason: '${result.rawText}: ${result.error}');
    expect(
      result.success,
      isTrue,
      reason:
          '${result.confidence}: ${result.error}; ${result.attempts.map((a) => a.toJson())}',
    );
  });
  test(
    'armazenamento real persiste configuração, foto e JSON sem sobrescrever',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'balanca_evidence_test_',
      );
      try {
        final disk = LocalManualWeighingStore(directory: () async => root);
        const config = WebcamConfiguration(
          cameraId: 'id',
          cameraName: 'USB Camera',
        );
        await disk.saveConfiguration(config);
        expect((await disk.load()).cameraId, 'id');
        await disk.saveConfiguration(const WebcamConfiguration(enabled: false));
        expect((await disk.load()).enabled, isFalse);
        final path = await disk.savePhoto('test', Uint8List.fromList([1, 2]));
        expect(await File(path).readAsBytes(), [1, 2]);
        await expectLater(
          disk.savePhoto('test', Uint8List(0)),
          throwsA(isA<FileSystemException>()),
        );
        await controller.initialize();
        await controller.capture();
        final evidence = await controller.confirm();
        await disk.save(evidence!);
        await expectLater(
          disk.save(evidence),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'webcam configurada aparece selecionada e diagnóstico não captura peso',
    (tester) async {
      final services = mockCaptureServices(
        camera: camera,
        ocr: ocr,
        store: store,
        configured: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ManualWebcamSettings(services: services)),
        ),
      );
      await tester.pumpAndSettle();
      final mirrorSwitch = find.widgetWithText(
        SwitchListTile,
        'Inverter horizontalmente',
      );
      expect(tester.widget<SwitchListTile>(mirrorSwitch).value, isFalse);
      await tester.tap(mirrorSwitch);
      await tester.pumpAndSettle();
      expect(services.configuration.mirrorHorizontally, isTrue);
      expect(store.config.mirrorHorizontally, isTrue);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        'usb-device-id',
      );
      await tester.tap(find.text('Testar câmera'));
      await tester.pumpAndSettle();
      expect(camera.starts, 1);
      expect(camera.captures, 0);
      expect(ocr.calls, 0);
      expect(store.records, isEmpty);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(camera.stops, greaterThan(0));
    },
  );
  testWidgets('lista vazia informa nenhuma webcam encontrada', (tester) async {
    camera.devices = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManualWebcamSettings(
            services: mockCaptureServices(camera: camera),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma webcam encontrada.'), findsOneWidget);
  });
  testWidgets('campo manual bloqueado antes e após OCR válido; fecha câmera', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManualCaptureDialog(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('manual-weight')))
          .enabled,
      isFalse,
    );
    await tester.ensureVisible(find.text('Capturar peso'));
    await tester.tap(find.text('Capturar peso'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Peso identificado:'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('manual-weight')))
          .enabled,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    expect(camera.stops, 1);
  });
}
