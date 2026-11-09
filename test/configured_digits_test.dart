import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:balanca_desktop/features/configuracoes/manual_webcam_settings.dart';
import 'package:balanca_desktop/features/pesagem/manual_weighing_policy.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_controller.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/configured_digits.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/snapshot_weight_recognition.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/live_weight_reader.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_recognition_validation.dart';

import 'support/manual_capture_mocks.dart';

void main() {
  for (final safe in [true, false]) {
    test(
      'configured capture preserves evidence, authorization and ${safe ? "OCR confirmation" : "manual fallback"}',
      () async {
        final ocr = MockWeightOcrService()
          ..result = selectSnapshotCandidates([
            for (final name in ['gray', 'otsu'])
              OcrAttempt(
                name,
                Uint8List(0),
                WeightOcrResult(rawText: '5700', confidence: safe ? .58 : .20),
              ),
          ], const WebcamConfiguration(decimalPlaces: 1));
        final camera = MockWeighingCameraService();
        final store = MockEvidenceStore();
        final services = mockCaptureServices(
          configured: true,
          ocr: ocr,
          camera: camera,
          store: store,
        );
        services.configuration = services.configuration.copyWith(
          decimalPlaces: 1,
        );
        final controller = ManualCaptureController(
          services: services,
          authorization: ManualAuthorization(
            user: 'operador',
            justification: 'Teste autorizado',
          ),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        expect(controller.canConfirm, isFalse);
        await controller.capture();
        expect(camera.captures, 1);
        expect(store.photos, isNotEmpty);
        expect(controller.manualAllowed, !safe);
        if (!safe) {
          expect(controller.finalWeight, isNull);
          controller.setManualWeight('570');
        }
        expect(controller.finalWeight, 570);
        final evidence = await controller.confirm();
        expect(evidence!.authorizer, 'operador');
        expect(
          evidence.source,
          safe ? WeightSource.cameraOcr : WeightSource.manualFallback,
        );
        expect(evidence.toJson()['ocrRawDigits'], '5700');
        expect(evidence.toJson()['ocrDecimalPlaces'], 1);
      },
    );
  }
  testWidgets('physical decimal selector persists an explicit station choice', (
    tester,
  ) async {
    final services = mockCaptureServices(configured: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManualWebcamSettings(services: services)),
      ),
    );
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('display-decimals-null'));
    expect(selector, findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    expect(services.configuration.decimalPlaces, 1);
    expect(find.byKey(const ValueKey('display-decimals-1')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'capture errors and overridden range failures cannot be skipped in voting',
    () {
      final c = WeightTemporalConsensus(requiredReadings: 4, digitsMode: true);
      final candidate = configuredDigits('5700', .6, 1);
      c.observe(candidate);
      c.observe(candidate);
      c.observe(candidate);
      c.observe(const WeightOcrResult(error: 'OCR_ENGINE_ERRO'));
      expect(c.observe(candidate).consensusCount, 4);
      final invalid = ConfiguredDigitsConsensus();
      for (var i = 0; i < 5; i++) {
        expect(
          invalid
              .observe(candidate.copyWith(failure: 'OCR_FORA_DA_FAIXA'))
              .success,
          isFalse,
        );
      }
    },
  );
  for (final item in <(String, int, int)>[
    ('5700', 1, 570),
    ('1342', 2, 13),
    ('13880', 0, 13880),
    ('138809', 1, 13880),
    ('138805', 1, 13880),
    ('1388099', 2, 13880),
    ('000', 1, 0),
    ('1', 3, 0),
    ('1399', 2, 13),
  ]) {
    test(
      '${item.$1} with ${item.$2} decimals -> ${item.$3}, only after consensus',
      () {
        final consensus = WeightTemporalConsensus(
          requiredReadings: 4,
          digitsMode: true,
        );
        final candidate = configuredDigits(item.$1, .58, item.$2);
        expect(candidate.weight, isNull);
        for (var i = 0; i < 4; i++) {
          expect(consensus.observe(candidate).success, isFalse);
        }
        final result = consensus.observe(candidate);
        expect(result.success, isTrue);
        expect(result.weight, item.$3);
        expect(result.rawDigits, item.$1);
        expect(result.ocrConfidence, .58);
        expect(result.finalConfidence, greaterThan(.58));
        expect(result.consensusCount, 5);
      },
    );
  }
  test('4 of 5 raw sequences accepted; integer truncation does not merge different digits', () {
    final c = ConfiguredDigitsConsensus();
    WeightOcrResult? result;
    for (final digits in ['5700', '5700', '5700', '5708', '5700']) {
      result = c.observe(configuredDigits(digits, .58, 1));
    }
    expect(result!.success, isTrue);
    expect(result.consensusCount, 4);
    final divergent = ConfiguredDigitsConsensus();
    for (final digits in ['5700', '5701', '5702', '5703', '5704']) {
      result = divergent.observe(configuredDigits(digits, .99, 1));
    }
    expect(result!.success, isFalse);
    expect(result.weight, isNull);
  });
  test('moving weights, weak confidence and invalid grammar never vote', () {
    for (final values in [
      ['5680', '5690', '5700', '5710', '5720'],
      List.filled(5, '57O0'),
      List.filled(5, '-5700'),
      List.filled(5, '.5700'),
      List.filled(5, '5700 kg'),
    ]) {
      final c = ConfiguredDigitsConsensus();
      for (final raw in values) {
        final result = c.observe(configuredDigits(raw, .99, 1));
        expect(result.success, isFalse);
        expect(result.weight, isNull);
      }
    }
    for (final confidence in [.0, .2, .39, .40, double.nan, double.infinity]) {
      final c = ConfiguredDigitsConsensus();
      for (var i = 0; i < 5; i++) {
        expect(
          c.observe(configuredDigits('5700', confidence, 1)).success,
          isFalse,
        );
      }
    }
  });
  test('internal separator normalizes, range applies to scaled value', () {
    expect(configuredDigits('570.0', .9, 1).rawDigits, '5700');
    expect(
      configuredDigits('13,42', .9, 2).diagnostics['interpretedValue'],
      13.42,
    );
    expect(
      configuredDigits('5700', .9, 1, maximum: 100).error,
      'OCR_FORA_DA_FAIXA',
    );
    expect(
      configuredDigits('5700', .9, 1, minimum: 1000, maximum: 100).error,
      'OCR_FAIXA_INVALIDA',
    );
    expect(configuredDigits('5700', .9, 4).error, 'OCR_DECIMAL_CONFIG_INVALID');
  });
  test(
    'station precision persists, legacy config does not guess physical scale',
    () {
      expect(WebcamConfiguration.fromJson({}).decimalPlaces, isNull);
      for (final places in [0, 1, 2, 3]) {
        final config = WebcamConfiguration(decimalPlaces: places);
        expect(
          WebcamConfiguration.fromJson(config.toJson()).decimalPlaces,
          places,
        );
        expect(config.copyWith(diagnostics: true).decimalPlaces, places);
      }
    },
  );
  test(
    'live reader fills only after five independent camera captures',
    () async {
      final camera = MockWeighingCameraService();
      final ocr = MockWeightOcrService()
        ..result = configuredDigits('5700', .58, 1);
      final ready = Completer<void>();
      late LiveWeightReader reader;
      reader = LiveWeightReader(
        camera: camera,
        processor: MockCaptureImageProcessor(),
        ocr: ocr,
        configuration: const WebcamConfiguration(decimalPlaces: 1),
        interval: const Duration(milliseconds: 5),
        onChanged: () {
          if (reader.ready && !ready.isCompleted) ready.complete();
        },
      );
      reader.start();
      await ready.future.timeout(const Duration(seconds: 3));
      expect(camera.captures, greaterThanOrEqualTo(5));
      expect(reader.result.weight, 570);
      await reader.stop();
    },
  );
}
