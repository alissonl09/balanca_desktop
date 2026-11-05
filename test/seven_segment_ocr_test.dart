import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_dialog.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/ocr_diagnostics_store.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/seven_segment_ocr_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/seven_segment_preprocessor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/tesseract_runtime.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_recognition_validation.dart';

import 'support/manual_capture_mocks.dart';

class RecordingVariantEngine implements OcrVariantEngine {
  final calls = <Map<String, Object?>>[];
  final responses = <String, WeightOcrResult>{};
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
    calls.add({
      'model': model,
      'directory': tessdataDirectory,
      'psm': psm,
      'numericOnly': numericOnly,
      'whitelist': whitelist,
    });
    return (responses[model] ??
            const WeightOcrResult(
              rawText: '12190',
              weight: 12190,
              confidence: .98,
            ))
        .copyWith(model: model, psm: psm, elapsedMs: 1);
  }
}

void main() {
  final roi = File('test/fixtures/seven_segment/12190.png').readAsBytesSync();
  const models = 'assets/ocr/tessdata';
  test(
    'real 7seg model executes locally; printed control remains readable',
    () async {
      final engine = TesseractWeightOcrService();
      try {
        await Process.run(engine.executable, ['--version']);
      } on ProcessException {
        markTestSkipped('Prepare o runtime Tesseract local.');
        return;
      }
      final result =
          await SevenSegmentWeightOcrService(
            engine: engine,
            generic: engine,
            modelDirectory: models,
          ).recognize(
            await File('test/fixtures/weight_ocr/12190.png').readAsBytes(),
          );
      expect(
        result.success,
        isTrue,
        reason: '${result.error}: ${result.attempts.map((a) => a.toJson())}',
      );
      expect(result.weight, 12190);
      expect(result.model, '7seg');
    },
  );
  test('digital fixture cannot be accepted with the wrong high-confidence ssd value', () async {
    final engine = TesseractWeightOcrService();
    try {
      await Process.run(engine.executable, ['--version']);
    } on ProcessException {
      markTestSkipped('Prepare o runtime Tesseract local.');
      return;
    }
    final result = await SevenSegmentWeightOcrService(
      engine: engine,
      generic: engine,
      modelDirectory: models,
    ).recognize(roi);
    expect(
      result.success && result.weight != 12190,
      isFalse,
      reason: '${result.model} ${result.weight} ${result.confidence}',
    );
    expect(result.attempts.any((a) => a.result.model == 'ssd'), isFalse);
  });
  test('real webcam ROI preserves OCR failure instead of reporting a false range violation', () async {
    final engine = TesseractWeightOcrService();
    try {
      await Process.run(engine.executable, ['--version']);
    } on ProcessException {
      markTestSkipped('Prepare o runtime Tesseract local.');
      return;
    }
    final reading =
        await SevenSegmentWeightOcrService(
          engine: engine,
          generic: engine,
          modelDirectory: models,
        ).recognize(
          await File('test/fixtures/weight_ocr/ind570_webcam_570.png')
              .readAsBytes(),
        );
    final validated = const WeightRecognitionRules(
      minimum: 0,
      maximum: 100000,
    ).validate(reading);
    if (reading.success) {
      expect(
        reading.weight,
        570,
        reason: 'Peso visual conhecido da captura real.',
      );
    } else {
      expect(validated.error, reading.error);
      expect(validated.finalConfidence, 0);
    }
  });
  test(
    'three specialized traineddata and Apache license are shipped offline',
    () {
      final source =
          jsonDecode(File('assets/ocr/SOURCE.json').readAsStringSync()) as Map;
      expect(source['license'], 'Apache-2.0');
      expect(source['commit'], 'e493a10a4bf81632506cf24ba99d83854afff9f6');
      for (final model in ['7seg', 'ssd', 'ssd_int']) {
        final file = File('$models/$model.traineddata');
        expect(file.existsSync(), isTrue);
        expect(
          file.lengthSync(),
          source['files']['$model.traineddata']['bytes'],
        );
      }
      expect(
        File('assets/ocr/LICENSE.tessdata_ssd').readAsStringSync(),
        contains('Apache License'),
      );
    },
  );
  test(
    'packaged relative model directory is preferred over development assets',
    () async {
      final temp = await Directory.systemTemp.createTemp('ssd_resolution_');
      try {
        final bundled = await Directory('${temp.path}/app/ocr/tessdata')
            .create(recursive: true);
        expect(
          TesseractRuntime.resolveModelDirectory(
            applicationDirectory: '${temp.path}/app',
            workingDirectory: Directory.current.path,
          ),
          bundled.path,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
  test(
    'offline cascade starts with 7seg, PSM 7 and numeric whitelist',
    () async {
      final engine = RecordingVariantEngine();
      final generic = MockWeightOcrService();
      final result = await SevenSegmentWeightOcrService(
        engine: engine,
        generic: generic,
        modelDirectory: models,
      ).recognize(roi);
      expect(result.success, isTrue);
      expect(result.weight, 12190);
      expect(result.model, '7seg');
      expect(result.attempts.length, 2);
      expect(generic.calls, 0);
      expect(
        engine.calls.every(
          (c) =>
              c['model'] == '7seg' &&
              c['psm'] == 7 &&
              c['numericOnly'] == true &&
              c['whitelist'] == '0123456789.-',
        ),
        isTrue,
      );
    },
  );
  test(
    'integer display configuration can narrow the whitelist further',
    () async {
      final engine = RecordingVariantEngine();
      await SevenSegmentWeightOcrService(
        engine: engine,
        modelDirectory: models,
        whitelist: '0123456789',
      ).recognize(roi);
      expect(engine.calls.first['whitelist'], '0123456789');
    },
  );
  test('7seg failure tries alternate preprocessing then ssd', () async {
    final engine = RecordingVariantEngine()
      ..responses['7seg'] = const WeightOcrResult(error: 'OCR_SEM_LEITURA');
    final result = await SevenSegmentWeightOcrService(
      engine: engine,
      modelDirectory: models,
      models: const ['7seg', 'ssd'],
    ).recognize(roi);
    expect(result.model, 'ssd');
    expect(result.success, isTrue);
    expect(
      engine.calls.any((c) => c['model'] == '7seg' && c['psm'] == 13),
      isTrue,
    );
    expect(
      result.attempts.any((a) => a.strategy.startsWith('close1_')),
      isTrue,
    );
  });
  test(
    'eng remains technical fallback after low confidence specialized output',
    () async {
      final engine = RecordingVariantEngine();
      for (final model in ['7seg', 'ssd']) {
        engine.responses[model] = const WeightOcrResult(
          rawText: '12790',
          weight: 12790,
          confidence: .2,
          error: 'OCR_BAIXA_CONFIANCA',
        );
      }
      final generic = MockWeightOcrService()
        ..result = const WeightOcrResult(
          rawText: '12190',
          weight: 12190,
          confidence: .99,
          model: 'eng',
        );
      final result = await SevenSegmentWeightOcrService(
        engine: engine,
        generic: generic,
        modelDirectory: models,
      ).recognize(roi);
      expect(result.model, 'eng');
      expect(result.success, isTrue);
      expect(generic.calls, 1);
    },
  );
  test('missing specialized models are reported and do not remove generic fallback', () async {
    final temp = await Directory.systemTemp.createTemp('ssd_missing_');
    try {
      final engine = RecordingVariantEngine();
      final generic = MockWeightOcrService();
      final result = await SevenSegmentWeightOcrService(
        engine: engine,
        generic: generic,
        modelDirectory: temp.path,
      ).recognize(roi);
      expect(result.success, isTrue);
      expect(generic.calls, 1);
      expect(engine.calls, isEmpty);
      expect(
        result.attempts.first.result.error,
        'OCR_MODELO_ESPECIALIZADO_INDISPONIVEL',
      );
      expect(
        ocrFailureMessage(result.attempts.first.result.error),
        contains('sete segmentos'),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });
  test('engine failure returns explicit error without blocking or inventing a reading', () async {
    final engine = RecordingVariantEngine()
      ..responses['7seg'] = const WeightOcrResult(error: 'OCR_TIMEOUT');
    final result = await SevenSegmentWeightOcrService(
      engine: engine,
      modelDirectory: models,
    ).recognize(roi);
    expect(result.error, 'OCR_TIMEOUT');
    expect(result.success, isFalse);
  });
  test('untrusted text and date-like values never become a numeric weight', () {
    for (final raw in [
      'SERIAL1234',
      '12:45:31',
      '20261105',
      '99999999',
      '12190 123',
      'O123',
    ]) {
      expect(parseWeightText(raw, .99).success, isFalse, reason: raw);
    }
    expect(parseWeightText('12190', .99).weight, 12190);
  });
  test('explicit range rejects implausible values without a global hardcoded limit', () {
    const rules = WeightRecognitionRules(minimum: 10, maximum: 20000);
    expect(
      rules
          .validate(const WeightOcrResult(weight: 100000, confidence: .99))
          .error,
      'OCR_FORA_DA_FAIXA',
    );
    expect(
      rules
          .validate(const WeightOcrResult(weight: 12190, confidence: .99))
          .success,
      isTrue,
    );
    expect(
      const WeightRecognitionRules(minimum: 0, maximum: 1000000)
          .validate(const WeightOcrResult(weight: 100000, confidence: .99))
          .success,
      isTrue,
    );
  });
  test(
    'invalid OCR candidates keep their original error before range validation',
    () {
      const rules = WeightRecognitionRules(minimum: 0, maximum: 100000);
      const weak = WeightOcrResult(
        rawText: '-570.0',
        weight: -570,
        confidence: 0,
        error: 'OCR_BAIXA_CONFIANCA',
      );
      expect(rules.validate(weak).error, 'OCR_BAIXA_CONFIANCA');
      expect(rules.validate(weak).weight, -570);
      expect(
        rules
            .validate(const WeightOcrResult(weight: -570, confidence: .99))
            .error,
        'OCR_FORA_DA_FAIXA',
      );
      expect(
        rules
            .validate(const WeightOcrResult(weight: 570, confidence: .99))
            .success,
        isTrue,
      );
    },
  );
  test('configurable temporal consensus uses minimum confidence across photographs', () {
    final consensus = WeightTemporalConsensus(requiredReadings: 4);
    for (var i = 0; i < 3; i++) {
      final result = consensus.observe(
        WeightOcrResult(weight: 12190, confidence: i == 1 ? .91 : .99),
      );
      expect(result.consensus, isFalse);
      expect(result.finalConfidence, 0);
    }
    final result = consensus.observe(
      const WeightOcrResult(weight: 12190, confidence: .99),
    );
    expect(result.consensus, isTrue);
    expect(result.finalConfidence, .91);
  });
  test(
    'changing digits and low confidence cannot satisfy temporal consensus',
    () {
      final consensus = WeightTemporalConsensus();
      consensus.observe(const WeightOcrResult(weight: 12190, confidence: .99));
      final changed = consensus.observe(
        const WeightOcrResult(weight: 12790, confidence: .99),
      );
      expect(changed.error, 'OCR_LEITURA_INSTAVEL');
      expect(changed.finalConfidence, 0);
      final weak = WeightTemporalConsensus().observe(
        const WeightOcrResult(
          weight: 12190,
          confidence: .2,
          error: 'OCR_BAIXA_CONFIANCA',
        ),
      );
      expect(weak.consensus, isFalse);
      expect(weak.finalConfidence, 0);
    },
  );
  test('zero is valid after independent photographs agree', () {
    final consensus = WeightTemporalConsensus(requiredReadings: 2);
    consensus.observe(const WeightOcrResult(weight: 0, confidence: .98));
    final result = consensus.observe(
      const WeightOcrResult(weight: 0, confidence: .99),
    );
    expect(result.consensus, isTrue);
    expect(result.weight, 0);
  });
  test(
    '2x 3x 4x and alternative preprocessing stay separate and preserve source',
    () {
      final before = Uint8List.fromList(roi);
      for (final scale in [2, 3, 4]) {
        final variants = prepareSevenSegmentVariants(
          roi,
          scale: scale,
          experimental: true,
        );
        expect(variants.length, 8);
        expect(variants.keys.any((n) => n.startsWith('adaptive_')), isTrue);
        expect(variants.keys.any((n) => n.startsWith('close1_')), isTrue);
        for (final bytes in variants.values) {
          final image = img.decodePng(bytes)!;
          expect(image.width, lessThanOrEqualTo(1620));
          expect(image.height, lessThanOrEqualTo(620));
        }
      }
      expect(roi, before);
    },
  );
  test('original crop excludes timestamp pixels and all OCR preprocessing uses clean ROI', () {
    final source = img.Image(width: 640, height: 480);
    final clean = Uint8List.fromList(img.encodePng(source));
    final first = processCapture(
      CapturedPhoto(clean, DateTime(2026, 11, 5, 12)),
      const DisplayRegion(),
    );
    final later = processCapture(
      CapturedPhoto(clean, DateTime(2026, 11, 5, 14)),
      const DisplayRegion(),
    );
    expect(first.ocrInput, later.ocrInput);
    expect(first.evidence, isNot(later.evidence));
    expect(
      prepareSevenSegmentVariants(first.ocrInput),
      prepareSevenSegmentVariants(later.ocrInput),
    );
  });
  test('debug diagnostic saves original, ROI, pipeline images and metadata with session cap', () async {
    final root = await Directory.systemTemp.createTemp('ssd_debug_test_');
    try {
      final store = LocalOcrDiagnosticsStore(directory: () async => root);
      final result = WeightOcrResult(
        weight: 12190,
        confidence: .99,
        model: '7seg',
        attempts: [
          OcrAttempt(
            'gray_contrast_2x',
            roi,
            const WeightOcrResult(model: '7seg'),
          ),
        ],
      );
      final path = await store.save(
        ProcessedCapture(roi, roi, original: roi),
        result,
        const DisplayRegion(),
      );
      expect(File('$path/original.png').existsSync(), isTrue);
      expect(File('$path/roi.png').existsSync(), isTrue);
      final json =
          jsonDecode(await File('$path/result.json').readAsString()) as Map;
      expect(json['model'], '7seg');
      expect(json['consensus'], isFalse);
      for (var i = 0; i < 9; i++) {
        await store.save(
          ProcessedCapture(roi, roi),
          result,
          const DisplayRegion(),
        );
      }
      expect(
        await store.save(
          ProcessedCapture(roi, roi),
          result,
          const DisplayRegion(),
        ),
        isNull,
      );
      expect(root.listSync().length, 10);
    } finally {
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'Testar leitura captures ROI without recording any weighing or evidence',
    (tester) async {
      final camera = MockWeighingCameraService(),
          ocr = MockWeightOcrService(),
          store = MockEvidenceStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraDiagnosticDialog(
              camera: camera,
              cameraId: 'usb-device-id',
              ocr: ocr,
              processor: MockCaptureImageProcessor(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Testar leitura'));
      await tester.tap(find.text('Testar leitura'));
      await tester.pumpAndSettle();
      expect(camera.captures, 1);
      expect(ocr.calls, 1);
      expect(store.records, isEmpty);
      expect(store.photos, isEmpty);
      expect(find.textContaining('sem registrar pesagem'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(camera.stops, greaterThan(0));
    },
  );
}
