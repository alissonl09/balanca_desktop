import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_vision_engine.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_dataset_store.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_recognition_validation.dart';

import '../tool/benchmark_weight_vision.dart' show benchmarkRow, editDistance;

DigitModelOutput sequence(String text, {bool complete = true}) =>
    DigitModelOutput([
      for (var i = 0; i < text.length; i++)
        DigitDetection(
          text[i] == '.' ? 10 : int.parse(text[i]),
          .02 + i * .08,
          .1,
          .06,
          .7,
          .99,
        ),
    ], complete: complete);

void main() {
  for (final item in {
    '570.0': 570,
    '13.42': 13,
    '13.99': 13,
    '12190': 12190,
    '0': 0,
  }.entries) {
    test('sort boxes and truncate ${item.key}', () {
      final output = sequence(item.key);
      final result = reconstructDetections(
        DigitModelOutput(output.detections.reversed.toList(), complete: true),
      );
      expect(result.success, isTrue);
      expect(result.weight, item.value);
      expect(result.recognitionKey, item.key);
    });
  }
  test('invalid, incomplete, ambiguous and weak results fail', () {
    for (final text in ['.13', '13.', '1..2']) {
      expect(reconstructDetections(sequence(text)).success, isFalse);
    }
    expect(
      reconstructDetections(sequence('1388', complete: false)).success,
      isFalse,
    );
    expect(
      reconstructDetections(sequence('13880'), maximum: 100).success,
      isFalse,
    );
    for (final box in [
      const DigitDetection(11, .1, .1, .1, .5, .99),
      const DigitDetection(1, .1, .1, .1, .5, double.nan),
      const DigitDetection(1, .1, .1, .1, .5, .5),
      const DigitDetection(1, .95, .1, .1, .5, .99),
    ]) {
      expect(
        reconstructDetections(DigitModelOutput([box], complete: true)).success,
        isFalse,
      );
    }
    expect(
      reconstructDetections(
        DigitModelOutput([
          const DigitDetection(1, .1, .1, .2, .5, .99),
          const DigitDetection(2, .15, .1, .2, .5, .99),
        ], complete: true),
      ).success,
      isFalse,
    );
  });
  test('absence, exception, invalid fallback and early exit', () async {
    final bytes = Uint8List(0);
    expect(
      (await const CustomModelEngine().recognize(bytes)).error,
      'CUSTOM_MODEL_UNAVAILABLE',
    );
    final valid = _Engine(reconstructDetections(sequence('13880')));
    final unused = _Engine(const WeightOcrResult());
    final result = await WeightEngineCascade([
      const CustomModelEngine(),
      _Engine(const WeightOcrResult(weight: -1, confidence: .99)),
      valid,
      unused,
    ]).recognize(bytes);
    expect(result.weight, 13880);
    expect(unused.calls, 0);
    expect(
      (await WeightEngineCascade([_Engine(const WeightOcrResult())])
              .recognize(bytes))
          .success,
      isFalse,
    );
    expect(
      (await CustomModelEngine(model: _BrokenModel()).recognize(bytes)).error,
      'CUSTOM_MODEL_ERROR',
    );
  });
  test('custom detections retain decimal precision in temporal votes', () {
    final consensus = WeightTemporalConsensus(requiredReadings: 4);
    final a = reconstructDetections(sequence('13.42'));
    final b = reconstructDetections(sequence('13.99'));
    for (final result in [a, b, a, a]) {
      expect(consensus.observe(result).consensus, isFalse);
    }
    expect(consensus.observe(a).consensus, isTrue);
  });
  test('benchmark counts a partial weight as failure', () {
    final row = benchmarkRow(
      'sample.png',
      'custom',
      '13880',
      '13880',
      reconstructDetections(sequence('1388')),
      1,
    );
    expect(row['weightCorrect'], isFalse);
    expect(row['imageCorrect'], isFalse);
    expect(row['digitEditDistance'], 1);
    expect(editDistance('13.42', '13.99'), 2);
  });
  test('dataset preserves clean image, ROI and manual ground truth', () async {
    final dir = await Directory.systemTemp.createTemp('dataset_test_');
    addTearDown(() => dir.delete(recursive: true));
    final image = img.Image(width: 100, height: 80);
    final photo = CapturedPhoto(
      Uint8List.fromList(img.encodePng(image)),
      DateTime.utc(2026, 11, 7),
    );
    const roi = DisplayRegion(
      left: .1,
      top: .1,
      width: .8,
      height: .8,
      calibrated: true,
    );
    final store = WeightDatasetStore(directory: dir);
    final path = await store.save(photo, roi, 'ind570');
    final metadata = jsonDecode(
      await File('$path/metadata.json').readAsString(),
    );
    expect(metadata['expected'], isNull);
    expect(metadata['indicatorModel'], 'IND570');
    expect(metadata['timestampDrawn'], false);
    final clean = img.decodePng(
      await File('$path/original.png').readAsBytes(),
    )!;
    expect(clean.width, 100);
    expect(clean.getPixel(10, 60).r, 0);
    expect(img.decodePng(await File('$path/roi.png').readAsBytes())!.width, 80);
    expect(() => store.save(photo, roi, 'auto'), throwsFormatException);
  });
}

class _Engine implements WeightOcrService {
  _Engine(this.result);
  final WeightOcrResult result;
  int calls = 0;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    calls++;
    return result;
  }
}

class _BrokenModel implements LocalDigitModel {
  @override
  Future<bool> get available async => true;
  @override
  Future<DigitModelOutput> detect(Uint8List rectifiedRoi) async =>
      throw StateError('runtime');
}
