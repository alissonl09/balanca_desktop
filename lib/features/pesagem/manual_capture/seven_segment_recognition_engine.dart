import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'capture_models.dart';
import 'decimal_detector.dart';
import 'weight_ocr_service.dart';

/// Independent deterministic implementation; no code imported from OCR projects.
class DisplayRecognizerProfile {
  const DisplayRecognizerProfile(this.id, this.color, {this.activation = .32});
  final String id, color;
  final double activation;
  bool get graphic => id == 'ind560' || id == 'ind570';
  static const profiles = {
    'auto': DisplayRecognizerProfile('auto', 'adaptive'),
    'ind560': DisplayRecognizerProfile('ind560', 'cyan'),
    'ind570': DisplayRecognizerProfile('ind570', 'green'),
    'generic': DisplayRecognizerProfile('generic', 'luminance'),
  };
}

/// Segment order A B C D E F G. Exact mapping, never nearest-digit guessing.
const sevenSegmentPatterns = <String, String>{
  '1111110': '0',
  '0110000': '1',
  '1101101': '2',
  '1111001': '3',
  '0110011': '4',
  '1011011': '5',
  '1011111': '6',
  '1110000': '7',
  '1111111': '8',
  '1111011': '9',
};

class SevenSegmentRecognitionEngine implements WeightOcrService {
  const SevenSegmentRecognitionEngine({
    this.profile = 'auto',
    this.diagnostics = false,
  });
  final String profile;
  final bool diagnostics;
  @override
  Future<WeightRecognitionResult> recognize(Uint8List image) => Isolate.run(
    () => recognizeDisplay(image, profile: profile, diagnostics: diagnostics),
  );
}

/// Input is a clean, calibrated and rectified ROI, never the full camera image.
WeightRecognitionResult recognizeDisplay(
  Uint8List bytes, {
  String profile = 'auto',
  bool diagnostics = false,
  bool graphicGeometry = false,
}) {
  final clock = Stopwatch()..start();
  final source = img.decodeImage(bytes);
  if (source == null || source.width < 8 || source.height < 12) {
    return const WeightOcrResult(error: 'SEGMENT_IMAGE_INVALID');
  }
  final settings =
      DisplayRecognizerProfile.profiles[profile] ??
      DisplayRecognizerProfile.profiles['auto']!;
  // Bound processing cost; preserve small decimal components (no erosion).
  final scale = math.min(
    3.0,
    math.min(1200 / source.width, 180 / source.height),
  );
  final roi = img.copyResize(
    source,
    width: (source.width * scale).round(),
    height: (source.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );
  final channel = img.Image(width: roi.width, height: roi.height);
  var low = 255, high = 0;
  for (final p in roi) {
    final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
    final maxValue = math.max(r, math.max(g, b));
    final minValue = math.min(r, math.min(g, b));
    // RGB opponent channels are equivalent to selecting lit green/cyan hue
    // families, retaining low-saturation luminous strokes in automatic mode.
    final value = switch (settings.color) {
      'green' => math.max(0.0, g - (r + b) * .25),
      'cyan' => math.max(0.0, math.min(g, b) - r * .5),
      'adaptive' => maxValue - minValue * .35,
      _ => .2126 * r + .7152 * g + .0722 * b,
    };
    final v = value.round().clamp(0, 255);
    low = math.min(low, v);
    high = math.max(high, v);
    channel.setPixelRgb(p.x, p.y, v, v, v);
  }
  final threshold = displayOtsu(channel);
  final binary = img.Image(width: roi.width, height: roi.height);
  for (final p in channel) {
    final v = p.r > threshold ? 255 : 0;
    binary.setPixelRgb(p.x, p.y, v, v, v);
  }
  Uint8List png(img.Image i) => Uint8List.fromList(img.encodePng(i));
  final geometry = analyzeDisplayGeometry(png(binary), isolateLine: false);
  final components = _components(binary);
  final boxes = [
    for (final box in geometry.characters) _refineBox(box, components),
  ];
  // A rounded graphic 5 can look like a seven-segment 6. Select the font
  // geometry before decoding, using connected full-height bodies, not the
  // numeric answer. A pure segmented display normally has disconnected bars.
  final graphicBodies = components
      .where(
        (c) =>
            c.box.height >= geometry.digitHeight * .9 &&
            c.box.width >= geometry.digitHeight * .32 &&
            c.area >= c.box.width * c.box.height * .3,
      )
      .isNotEmpty;
  if (!graphicGeometry && graphicBodies && settings.graphic) {
    return recognizeDisplay(
      bytes,
      profile: profile,
      diagnostics: diagnostics,
      graphicGeometry: true,
    );
  }
  if (!graphicGeometry && graphicBodies && profile == 'auto') {
    final candidates = [
      for (final id in ['ind570', 'ind560'])
        recognizeDisplay(
          bytes,
          profile: id,
          diagnostics: diagnostics,
          graphicGeometry: true,
        ),
    ];
    final valid = candidates.where((r) => r.success).toList();
    if (valid.isEmpty) return candidates.first;
    if (valid.map((r) => r.recognitionKey).toSet().length > 1) {
      return const WeightOcrResult(error: 'SEGMENT_PROFILES_DISAGREE');
    }
    return valid.reduce(
      (a, b) => a.candidateConfidence >= b.candidateConfidence ? a : b,
    );
  }
  final segmentData = <Map<String, Object?>>[];
  final overlay = img.Image.from(roi);
  final stages = <OcrAttempt>[];
  var digits = '', confidence = 1.0;
  String? failure;
  double density(
    math.Rectangle<int> box,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    var active = 0, count = 0;
    for (
      var y = box.top + (box.height * y1).floor();
      y < box.top + (box.height * y2).ceil();
      y++
    ) {
      for (
        var x = box.left + (box.width * x1).floor();
        x < box.left + (box.width * x2).ceil();
        x++
      ) {
        if (x < 0 || y < 0 || x >= binary.width || y >= binary.height) continue;
        count++;
        if (binary.getPixel(x, y).r > 0) active++;
      }
    }
    return count == 0 ? 0 : active / count;
  }

  const regions = [
    [.3, .01, .7, .13],
    [.76, .18, .99, .4],
    [.76, .60, .99, .82],
    [.3, .87, .7, .99],
    [.01, .60, .24, .82],
    [.01, .18, .24, .4],
    [.3, .44, .7, .56],
  ];
  for (var index = 0; index < boxes.length; index++) {
    final box = boxes[index];
    final narrow = box.width / box.height < .29;
    final values = [
      for (final r in regions) density(box, r[0], r[1], r[2], r[3]),
    ];
    final thresholds = List<double>.filled(7, settings.activation);
    if (settings.graphic && graphicGeometry) {
      // Graphic Toledo fonts have rounded lower-left hooks and a diagonal 7.
      // Probe the centre of G (avoid the sides of 0), and require a broad D/E.
      values[3] = density(box, .15, .85, .85, .98);
      values[4] = density(box, .1, .52, .3, .65);
      values[6] = density(box, .4, .45, .6, .55);
      thresholds[3] = .52;
      thresholds[4] = .72;
    }
    String bits;
    if (narrow &&
        density(box, 0, .05, 1, .4) > .55 &&
        density(box, 0, .6, 1, .95) > .55) {
      bits = '0110000';
      confidence = math.min(confidence, .96);
    } else {
      bits = [
        for (var i = 0; i < 7; i++) values[i] >= thresholds[i] ? '1' : '0',
      ].join();
      // Distance to the decision boundary is evidence, not Tesseract confidence.
      for (var i = 0; i < values.length; i++) {
        final v = values[i];
        confidence = math.min(
          confidence,
          .9 + .1 * ((v - thresholds[i]).abs() / .3).clamp(0, 1),
        );
      }
    }
    final digit = settings.graphic && graphicGeometry && bits == '1100001'
        ? '7'
        : sevenSegmentPatterns[bits];
    if (digit == null ||
        List.generate(
              7,
              (i) => (values[i] - thresholds[i]).abs(),
            ).any((distance) => distance < .06) &&
            !narrow) {
      failure = 'SEGMENT_AMBIGUOUS';
    }
    digits += digit ?? '?';
    segmentData.add({
      'index': index,
      'digit': digit,
      'bits': bits,
      'activation': values,
      ...boxJson(box),
    });
    if (diagnostics) {
      final probes = [for (final region in regions) List<double>.of(region)];
      if (settings.graphic && graphicGeometry) {
        probes[3] = [.15, .85, .85, .98];
        probes[4] = [.1, .52, .3, .65];
        probes[6] = [.4, .45, .6, .55];
      }
      for (var segment = 0; segment < 7; segment++) {
        if (bits[segment] != '1') {
          continue;
        }
        final r = probes[segment];
        img.drawRect(
          overlay,
          x1: box.left + (box.width * r[0]).round(),
          y1: box.top + (box.height * r[1]).round(),
          x2: box.left + (box.width * r[2]).round(),
          y2: box.top + (box.height * r[3]).round(),
          color: img.ColorRgb8(0, 255, 255),
        );
      }
    }
    img.drawRect(
      overlay,
      x1: box.left,
      y1: box.top,
      x2: box.right,
      y2: box.bottom,
      color: img.ColorRgb8(255, 160, 0),
    );
    img.drawString(
      overlay,
      '$index:${digit ?? "?"} $bits',
      font: img.arial14,
      x: box.left,
      y: math.max(0, box.top - 15),
      color: img.ColorRgb8(255, 255, 255),
    );
  }
  if (boxes.isEmpty || boxes.length > 8) failure = 'SEGMENT_DIGITS_NOT_FOUND';
  if (geometry.points.length > 1) failure = 'SEGMENT_DECIMAL_AMBIGUOUS';
  int? decimalPosition;
  if (geometry.points.length == 1) {
    decimalPosition = boxes
        .where((b) => b.right <= geometry.points.single.left)
        .length;
    if (decimalPosition == 0 || decimalPosition >= boxes.length) {
      failure = 'SEGMENT_DECIMAL_AMBIGUOUS';
    }
  }
  // A partial or low-resolution glyph must not be promoted to a valid weight.
  if (geometry.digitHeight / scale < 16 || high - low < 25) {
    failure = 'SEGMENT_POOR_IMAGE';
  }
  if (boxes.any(
    (b) =>
        b.left == 0 ||
        b.top == 0 ||
        b.right >= binary.width ||
        (b.bottom >= binary.height && density(b, 0, .99, 1, 1) > .5),
  )) {
    failure = 'SEGMENT_CLIPPED';
  }
  if (boxes.isNotEmpty) {
    final first = boxes.first, height = geometry.digitHeight;
    final negative = components.any(
      (c) =>
          c.box.right <= first.left &&
          c.box.width >= height * .18 &&
          c.box.height < height * .28 &&
          c.box.top + c.box.height / 2 > first.top + height * .25 &&
          c.box.top + c.box.height / 2 < first.top + height * .72,
    );
    if (negative) failure = 'SEGMENT_NEGATIVE';
  }
  final raw = decimalPosition == null
      ? digits
      : '${digits.substring(0, decimalPosition)}.${digits.substring(decimalPosition)}';
  final integer = raw.split('.').first;
  final weight = double.tryParse(integer);
  final result = WeightOcrResult(
    rawText: raw,
    normalizedText: raw,
    weight: weight,
    confidence: confidence,
    error: failure,
    model: 'geometry',
    strategy: 'Seven Segment',
    decimalDetected: decimalPosition != null,
    decimalPosition: decimalPosition,
    characterPositions: boxes.map(boxJson).toList(),
    roiQuality: math.min(1.0, (high - low) / 50),
    structuralConfidence: confidence,
    elapsedMs: clock.elapsedMilliseconds,
    diagnostics: {
      ...geometry.toJson(),
      'profile': settings.id,
      'geometry': graphicGeometry ? 'graphic' : 'seven-segment',
      'color': settings.color,
      'thresholdMethod': 'Otsu on selected color channel',
      'threshold': threshold,
      'segments': segmentData,
      'rawDigits': digits,
      'integerDigits': integer,
      'sourceWidth': source.width,
      'sourceHeight': source.height,
    },
  );
  if (diagnostics) {
    img.drawString(
      overlay,
      'Peso: ${weight ?? "?"}',
      font: img.arial14,
      x: 0,
      y: math.max(0, overlay.height - 16),
      color: img.ColorRgb8(255, 255, 255),
    );
    stages.add(OcrAttempt('Canal de cor', png(channel), result));
    stages.add(OcrAttempt('Binarizada', png(binary), result));
    stages.add(OcrAttempt('Digitos e segmentos', png(overlay), result));
  }
  final completed = result.copyWith(attempts: stages);
  if (settings.graphic && !graphicGeometry && !completed.success) {
    return recognizeDisplay(
      bytes,
      profile: profile,
      diagnostics: diagnostics,
      graphicGeometry: true,
    );
  }
  if (profile == 'auto' && !completed.success) {
    final alternatives = [
      for (final id in ['ind570', 'ind560'])
        recognizeDisplay(bytes, profile: id, diagnostics: diagnostics),
    ];
    final valid = alternatives.where((r) => r.success).toList();
    if (valid.map((r) => r.recognitionKey).toSet().length > 1) {
      return completed.copyWith(failure: 'SEGMENT_PROFILES_DISAGREE');
    }
    if (valid.isNotEmpty) {
      return valid.reduce(
        (a, b) => a.candidateConfidence >= b.candidateConfidence ? a : b,
      );
    }
  }
  return completed;
}

class _InkComponent {
  const _InkComponent(this.box, this.area);
  final math.Rectangle<int> box;
  final int area;
}

List<_InkComponent> _components(img.Image image) {
  final w = image.width,
      h = image.height,
      seen = Uint8List(image.width * image.height);
  final components = <_InkComponent>[];
  for (var start = 0; start < w * h; start++) {
    if (seen[start] != 0 || image.getPixel(start % w, start ~/ w).r == 0) {
      continue;
    }
    final queue = <int>[start];
    seen[start] = 1;
    var left = start % w, right = left, top = start ~/ w, bottom = top;
    for (var i = 0; i < queue.length; i++) {
      final x = queue[i] % w, y = queue[i] ~/ w;
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          final next = ny * w + nx;
          if (seen[next] != 0) continue;
          seen[next] = 1;
          if (image.getPixel(nx, ny).r > 0) queue.add(next);
        }
      }
    }
    components.add(
      _InkComponent(
        math.Rectangle(left, top, right - left + 1, bottom - top + 1),
        queue.length,
      ),
    );
  }
  return components;
}

math.Rectangle<int> _refineBox(
  math.Rectangle<int> box,
  List<_InkComponent> components,
) {
  final candidates =
      components
          .where(
            (c) =>
                c.box.left >= box.left - box.height * .08 &&
                c.box.right <= box.right + box.height * .08 &&
                c.box.height >= box.height * .9 &&
                c.box.width <= box.width * 1.25,
          )
          .toList()
        ..sort((a, b) => b.area.compareTo(a.area));
  return candidates.isEmpty ? box : candidates.first.box;
}
