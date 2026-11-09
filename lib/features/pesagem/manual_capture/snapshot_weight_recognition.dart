import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'capture_models.dart';
import 'configured_digits.dart';
import 'decimal_detector.dart';
import 'persistent_digits_ocr.dart';
import 'seven_segment_preprocessor.dart';
import 'seven_segment_recognition_engine.dart';
import 'weight_ocr_service.dart';

class PrincipalDigits {
  const PrincipalDigits(
    this.image,
    this.boxes, {
    this.ambiguous = false,
    this.negative = false,
  });
  final img.Image image;
  final List<math.Rectangle<int>> boxes;
  final bool ambiguous, negative;
}

/// Candidate groups are ranked by height, occupied area, horizontal extent,
/// baseline and proximity. Both polarities are inspected; holes are normally
/// smaller than whole glyphs. Similar distinct groups fail closed.
PrincipalDigits locatePrincipalDigits(img.Image original) {
  final factor = math.min(
    1.0,
    math.min(1000 / original.width, 600 / original.height),
  );
  final source = img.copyResize(
    original,
    width: (original.width * factor).round(),
    height: (original.height * factor).round(),
  );
  final gray = img.grayscale(img.Image.from(source));
  final threshold = displayOtsu(gray);
  final groups = <List<math.Rectangle<int>>>[];
  final scores = <double>[];
  final signs = <bool>[];
  final keys = <String>{};
  for (final bright in [true, false]) {
    final seen = Uint8List(gray.width * gray.height);
    final components = <math.Rectangle<int>>[];
    for (var start = 0; start < seen.length; start++) {
      if (seen[start] != 0) continue;
      seen[start] = 1;
      bool ink(int i) =>
          (gray.getPixel(i % gray.width, i ~/ gray.width).r > threshold) ==
          bright;
      if (!ink(start)) continue;
      final queue = <int>[start];
      var left = start % gray.width,
          right = left,
          top = start ~/ gray.width,
          bottom = top;
      for (var cursor = 0; cursor < queue.length; cursor++) {
        final i = queue[cursor], x = i % gray.width, y = i ~/ gray.width;
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
        for (final next in [
          if (x > 0) i - 1,
          if (x + 1 < gray.width) i + 1,
          if (y > 0) i - gray.width,
          if (y + 1 < gray.height) i + gray.width,
        ]) {
          if (seen[next] != 0) continue;
          seen[next] = 1;
          if (ink(next)) queue.add(next);
        }
      }
      final w = right - left + 1, h = bottom - top + 1;
      if (left == 0 ||
          top == 0 ||
          right == gray.width - 1 ||
          bottom == gray.height - 1 ||
          queue.length < 3) {
        continue;
      }
      if (queue.length < w * h * .12) continue;
      components.add(math.Rectangle(left, top, w, h));
    }
    final bodies = components
        .where(
          (c) =>
              c.height >= 12 &&
              c.width >= c.height * .08 &&
              c.width <= c.height * 1.2,
        )
        .toList();
    for (final seed in bodies) {
      final aligned =
          bodies
              .where(
                (b) =>
                    b.height >= seed.height * .72 &&
                    b.height <= seed.height * 1.35 &&
                    (b.bottom - seed.bottom).abs() <= seed.height * .25,
              )
              .toList()
            ..sort((a, b) => a.left.compareTo(b.left));
      var group = <math.Rectangle<int>>[];
      final runs = <List<math.Rectangle<int>>>[];
      for (final box in aligned) {
        if (group.isNotEmpty && box.left - group.last.right > seed.height) {
          runs.add(group);
          group = [];
        }
        group.add(box);
      }
      if (group.isNotEmpty) runs.add(group);
      for (final run in runs) {
        if (run.length < 2) {
          continue; // A single digit uses the operator's tight ROI.
        }
        final l = run.first.left, r = run.last.right;
        final t = run.map((b) => b.top).reduce(math.min),
            b = run.map((b) => b.bottom).reduce(math.max);
        if (!keys.add('$l,$t,$r,$b')) continue;
        final height =
            run.map((b) => b.height).reduce((a, b) => a + b) / run.length;
        final area = run.fold<int>(0, (sum, c) => sum + c.width * c.height);
        groups.add(run);
        scores.add(height * height + area * .15 + (r - l) * height * .1);
        signs.add(
          components.any(
            (c) =>
                c.right <= l &&
                l - c.right < height * 1.5 &&
                c.width >= height * .18 &&
                c.width > c.height * 2 &&
                c.height < height * .28 &&
                c.top + c.height / 2 > t + height * .25 &&
                c.top + c.height / 2 < t + height * .72,
          ),
        );
      }
    }
  }
  if (groups.isEmpty) {
    return PrincipalDigits(img.Image.from(original), const []);
  }
  final order = List.generate(groups.length, (i) => i)
    ..sort((a, b) => scores[b].compareTo(scores[a]));
  final best = groups[order.first];
  final bestTop = best.map((b) => b.top).reduce(math.min);
  final bestHeight = best.map((b) => b.height).reduce(math.max);
  final ambiguous = order
      .skip(1)
      .any(
        (i) =>
            scores[i] >= scores[order.first] * .85 &&
            ((groups[i].first.top - bestTop).abs() > bestHeight * .5 ||
                groups[i].last.right < best.first.left ||
                groups[i].first.left > best.last.right),
      );
  final boxes = best
      .map(
        (b) => math.Rectangle(
          (b.left / factor).round(),
          (b.top / factor).round(),
          (b.width / factor).round(),
          (b.height / factor).round(),
        ),
      )
      .toList();
  final margin = (bestHeight / factor * .1).ceil();
  final left = math.max(0, boxes.first.left - margin),
      top = math.max(0, boxes.map((b) => b.top).reduce(math.min) - margin);
  final right = math.min(original.width, boxes.last.right + margin),
      bottom = math.min(
        original.height,
        boxes.map((b) => b.bottom).reduce(math.max) + margin,
      );
  return PrincipalDigits(
    img.copyCrop(
      original,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    ),
    boxes,
    ambiguous: ambiguous,
    negative: signs[order.first],
  );
}

class SnapshotInputs {
  const SnapshotInputs(this.roi, this.variants, this.boxes, this.error);
  final Uint8List roi;
  final Map<String, Uint8List> variants;
  final List<Map<String, num>> boxes;
  final String? error;
}

SnapshotInputs prepareSnapshotInputs(Uint8List roi) {
  final image = img.decodeImage(roi);
  if (image == null) throw const FormatException('Invalid ROI');
  final principal = locatePrincipalDigits(image);
  final bytes = Uint8List.fromList(img.encodePng(principal.image));
  if (principal.ambiguous || principal.negative) {
    return SnapshotInputs(
      bytes,
      {},
      principal.boxes.map(boxJson).toList(),
      principal.negative ? 'SEGMENT_NEGATIVE' : 'OCR_MAIN_NUMBER_AMBIGUOUS',
    );
  }
  // Reuse the existing bounded, copied-image preprocessing implementation.
  final variants = prepareSevenSegmentVariants(bytes);
  return SnapshotInputs(
    bytes,
    {
      for (final key in [
        'gray_contrast_2x',
        'otsu_2x',
        'adaptive_2x',
        'inverse_2x',
      ])
        key: variants[key]!,
    },
    principal.boxes.map(boxJson).toList(),
    null,
  );
}

typedef SnapshotVariantRecognizer = Future<WeightOcrResult> Function(
  Uint8List image,
);

class SnapshotWeightRecognition implements WeightOcrService {
  SnapshotWeightRecognition({
    required this.configuration,
    SnapshotVariantRecognizer? variant,
    this.geometry = true,
  }) : variant =
           variant ??
           ((image) =>
               PersistentDigitsOcr.shared.recognize(image, prepared: true));
  final WebcamConfiguration Function() configuration;
  final SnapshotVariantRecognizer variant;
  final bool geometry;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    final timer = Stopwatch()..start();
    final config = configuration();
    if (config.decimalPlaces == null) {
      return const WeightOcrResult(error: 'OCR_DECIMAL_CONFIG_REQUIRED');
    }
    final inputs = await Isolate.run(() => prepareSnapshotInputs(image));
    if (inputs.error != null) {
      return WeightOcrResult(
        error: inputs.error,
        characterPositions: inputs.boxes,
      );
    }
    final attempts = <OcrAttempt>[];
    for (final entry in inputs.variants.entries) {
      WeightOcrResult reading;
      try {
        reading = await variant(entry.value);
      } catch (_) {
        reading = const WeightOcrResult(error: 'OCR_ENGINE_ERRO');
      }
      attempts.add(OcrAttempt(entry.key, entry.value, reading));
      if (reading.error == 'OCR_ENGINE_INDISPONIVEL') break;
    }
    if (geometry) {
      final result = await SevenSegmentRecognitionEngine(
        profile: config.displayProfile,
      ).recognize(inputs.roi);
      attempts.add(OcrAttempt('geometry', inputs.roi, result));
    }
    final selected = selectSnapshotCandidates(attempts, config);
    return selected.copyWith(
      elapsedMs: timer.elapsedMilliseconds,
      characterPositions: inputs.boxes,
      diagnostics: {'principalBoxes': inputs.boxes, ...selected.diagnostics},
    );
  }
}

WeightOcrResult selectSnapshotCandidates(
  List<OcrAttempt> attempts,
  WebcamConfiguration config,
) {
  if (config.decimalPlaces == null) {
    return WeightOcrResult(
      error: 'OCR_DECIMAL_CONFIG_REQUIRED',
      attempts: attempts,
    );
  }
  final groups = <String, List<WeightOcrResult>>{};
  final sources = <String, Set<String>>{};
  final rejected = <WeightOcrResult>[];
  for (final attempt in attempts) {
    final r = attempt.result;
    if (attempt.strategy == 'geometry' && !r.success) continue;
    // Error-free native output can still have moderate confidence. A rejected
    // geometric candidate is never promoted into a vote.
    if (r.error != null && r.error != 'OCR_BAIXA_CONFIANCA') continue;
    final candidate = configuredDigits(
      r.rawText,
      r.ocrConfidence,
      config.decimalPlaces!,
      minimum: config.minimumWeight,
      maximum: config.maximumWeight,
    );
    if (candidate.diagnostics['numericAndRangeValid'] != true) {
      rejected.add(candidate);
      continue;
    }
    final key = candidate.rawDigits;
    if (!(sources[key] ??= <String>{}).add(attempt.strategy)) continue;
    (groups[key] ??= []).add(candidate);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));
  final winner = keys.isEmpty ? null : keys.first;
  final support = winner == null ? 0 : groups[winner]!.length;
  final total = groups.values.fold<int>(0, (sum, g) => sum + g.length);
  final mean = winner == null
      ? 0.0
      : groups[winner]!.map((r) => r.ocrConfidence).reduce((a, b) => a + b) /
            support;
  final agreement = total == 0 ? 0.0 : support / total;
  final score = .4 * mean + .5 * agreement + (support > 0 ? .1 : 0);
  final accepted =
      support >= 2 &&
      agreement >= 2 / 3 &&
      mean >= .45 &&
      score >= .65 &&
      (keys.length < 2 || support > groups[keys[1]]!.length);
  final chosen = winner == null ? null : groups[winner]!.first;
  final observed =
      winner ??
      rejected
          .where((r) => RegExp(r'^\d+$').hasMatch(r.rawDigits))
          .firstOrNull
          ?.rawDigits ??
      '';
  final interpreted =
      (chosen ?? rejected.firstOrNull)?.diagnostics['interpretedValue'] as num?;
  return WeightOcrResult(
    rawText: observed,
    normalizedText: observed,
    weight: accepted ? interpreted!.truncateToDouble() : null,
    confidence: score.clamp(0, 1),
    error: accepted
        ? null
        : total > 0
        ? 'OCR_PIPELINES_NO_CONSENSUS'
        : attempts.any((a) => a.result.error == 'OCR_ENGINE_INDISPONIVEL')
        ? 'OCR_ENGINE_INDISPONIVEL'
        : rejected.firstOrNull?.error ?? 'OCR_SEM_LEITURA',
    strategy: 'snapshot_pipeline_consensus',
    model: 'eng / geometry',
    attempts: attempts,
    consensusReadings: accepted ? support : 0,
    requiredReadings: 2,
    diagnostics: {
      'analysisKind': 'snapshot',
      'consensusScope': 'pipelines',
      'configuredDigits': true,
      'rawDigits': observed,
      'decimalPlaces': config.decimalPlaces,
      'interpretedValue': interpreted,
      'finalWeight': accepted ? interpreted!.truncate() : null,
      'ocrConfidence': mean,
      'pipelineSupport': support,
      'eligibleCandidates': total,
      'pipelineAgreement': agreement,
      'acceptanceScore': score,
      'numericAndRangeValid': accepted,
    },
  );
}
