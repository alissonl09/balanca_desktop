import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'capture_models.dart';
import 'dominant_weight_line.dart';

/// Pixel geometry only. Does not classify or invent digits. All coordinates are
/// in the original ROI, before enlargement, padding or optional morphology.
class DisplayGeometry {
  const DisplayGeometry({
    this.characters = const [],
    this.points = const [],
    this.digitHeight = 0,
    this.quality = 0,
    this.contrast = 0,
    this.sharpness = 0,
    this.clippedFraction = 0,
    this.width = 0,
    this.height = 0,
    this.threshold = 128,
  });
  final List<math.Rectangle<int>> characters, points;
  final double digitHeight, quality, contrast, sharpness, clippedFraction;
  final int width, height, threshold;
  Map<String, Object?> toJson() => {
    'roiWidth': width,
    'roiHeight': height,
    'digitHeightPixels': digitHeight,
    'roiQuality': quality,
    'contrast': contrast,
    'sharpness': sharpness,
    'clippedFraction': clippedFraction,
    'geometryThreshold': threshold,
    'characterPositions': characters.map(boxJson).toList(),
    'decimalCandidates': points.map(boxJson).toList(),
  };
}

Map<String, num> boxJson(math.Rectangle<int> r) => {
  'x': r.left,
  'y': r.top,
  'width': r.width,
  'height': r.height,
};

int displayOtsu(img.Image gray) {
  final histogram = List<int>.filled(256, 0);
  for (final p in gray) {
    histogram[p.r.toInt()]++;
  }
  final total = gray.width * gray.height;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * histogram[i];
  }
  var count = 0, threshold = 128;
  var subtotal = 0.0, best = -1.0;
  for (var i = 0; i < 255; i++) {
    count += histogram[i];
    subtotal += i * histogram[i];
    if (count == 0 || count == total) continue;
    final delta = subtotal / count - (sum - subtotal) / (total - count);
    final score = count * (total - count) * delta * delta;
    if (score > best) {
      best = score;
      threshold = i;
    }
  }
  return threshold;
}

DisplayGeometry analyzeDisplayGeometry(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const DisplayGeometry();
  final line = locateDominantWeightLine(decoded);
  final source = line.image;
  final gray = img.grayscale(source);
  final w = gray.width, h = gray.height;
  final threshold = displayOtsu(gray);
  var bright = 0, minimum = 255.0, maximum = 0.0, sharpness = 0.0, clipped = 0;
  for (final p in gray) {
    if (p.r > threshold) bright++;
    minimum = math.min(minimum, p.r.toDouble());
    maximum = math.max(maximum, p.r.toDouble());
    if (p.r > 250) clipped++;
    if (p.x > 0) sharpness += (p.r - gray.getPixel(p.x - 1, p.y).r).abs();
  }
  var borderBright = 0, borderCount = 0;
  for (final p in gray) {
    if (p.x == 0 || p.y == 0 || p.x == w - 1 || p.y == h - 1) {
      borderCount++;
      if (p.r > threshold) borderBright++;
    }
  }
  // Tight ROIs can contain >50% lit segments. Their perimeter is a better
  // background estimate than the minority of all pixels.
  final lightInk = borderCount > 0
      ? borderBright < borderCount / 2
      : bright < w * h / 2;
  bool ink(int x, int y) => (gray.getPixel(x, y).r > threshold) == lightInk;
  // Vertical projection keeps disconnected seven-segment strokes together.
  // No erosion, opening, or component-area deletion is used for decimal data.
  final rows = List<int>.filled(h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (ink(x, y)) rows[y]++;
    }
  }
  final bands = <(int, int)>[];
  int? start;
  var last = 0;
  final gap = (h * .025).round().clamp(2, 4);
  for (var y = 0; y <= h + gap; y++) {
    if (y < h && rows[y] >= 2) {
      start ??= y;
      last = y;
    } else if (start != null && y - last > gap) {
      bands.add((start, last + 1));
      start = null;
    }
  }
  bands.sort((a, b) => (b.$2 - b.$1).compareTo(a.$2 - a.$1));
  if (bands.isEmpty) return DisplayGeometry(width: w, height: h);
  final top = bands.first.$1, bottom = bands.first.$2;
  final bandHeight = bottom - top;
  final columns = List<int>.filled(w, 0);
  // Baseline labels and the decimal must not merge neighbouring digit slots.
  // Segment columns on the upper body; scan decimal components on the full band.
  final bodyBottom = top + (bandHeight * .8).round();
  for (var x = 0; x < w; x++) {
    for (var y = top; y < bodyBottom; y++) {
      if (ink(x, y)) columns[x]++;
    }
  }
  final characters = <math.Rectangle<int>>[];
  int? left;
  for (var x = 0; x <= w; x++) {
    if (x < w && columns[x] > 0) {
      left ??= x;
      continue;
    }
    if (left == null) continue;
    var t = bottom, b = top;
    for (var cx = left; cx < x; cx++) {
      for (var y = top; y < bottom; y++) {
        if (ink(cx, y)) {
          t = math.min(t, y);
          b = math.max(b, y + 1);
        }
      }
    }
    if (b - t >= bandHeight * .68 &&
        x - left <= bandHeight * 1.1 &&
        x - left >= bandHeight * .06) {
      characters.add(math.Rectangle(left, t, x - left, b - t));
    }
    left = null;
  }
  // Connected components include even one-pixel marks. A weak tiny mark is
  // reported as ambiguous instead of silently discarded as noise.
  final points = <math.Rectangle<int>>[];
  final visited = Uint8List(w * h);
  for (var y = top; y < bottom; y++) {
    for (var x = 0; x < w; x++) {
      final index = y * w + x;
      if (visited[index] != 0 || !ink(x, y)) continue;
      final queue = <int>[index];
      visited[index] = 1;
      var l = x, r = x, t = y, b = y;
      for (var i = 0; i < queue.length; i++) {
        final cx = queue[i] % w, cy = queue[i] ~/ w;
        l = math.min(l, cx);
        r = math.max(r, cx);
        t = math.min(t, cy);
        b = math.max(b, cy);
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = cx + dx, ny = cy + dy;
            if (nx < 0 || nx >= w || ny < top || ny >= bottom) continue;
            final next = ny * w + nx;
            if (visited[next] != 0) continue;
            visited[next] = 1;
            if (ink(nx, ny)) queue.add(next);
          }
        }
      }
      final pw = r - l + 1, ph = b - t + 1;
      if (pw > bandHeight * .25 ||
          ph > bandHeight * .25 ||
          pw / ph < .4 ||
          pw / ph > 2.5 ||
          t < top + bandHeight * .68 ||
          b < bottom - bandHeight * .2 ||
          queue.length < pw * ph * .35) {
        continue;
      }
      for (var i = 0; i + 1 < characters.length; i++) {
        final before = characters[i], after = characters[i + 1];
        if (l >= before.right &&
            r < after.left &&
            l - before.right <= bandHeight * .6 &&
            after.left - r <= bandHeight * .6 &&
            after.left - before.right <= bandHeight) {
          points.add(math.Rectangle(l, t, pw, ph));
        }
      }
    }
  }
  final digitHeight = characters.isEmpty
      ? 0.0
      : characters.map((c) => c.height).reduce((a, b) => a + b) /
            characters.length;
  final contrast = (maximum - minimum) / 255;
  // Resolution/contrast constrain acceptance; blur/clipping are exposed for
  // calibration, not sold as a statistically calibrated camera focus score.
  final quality = math.min(1.0, math.min(digitHeight / 20, contrast / .25));
  return DisplayGeometry(
    characters: [
      for (final c in characters)
        math.Rectangle(c.left + line.left, c.top + line.top, c.width, c.height),
    ],
    points: [
      for (final c in points)
        math.Rectangle(c.left + line.left, c.top + line.top, c.width, c.height),
    ],
    digitHeight: digitHeight,
    quality: quality,
    width: decoded.width,
    height: decoded.height,
    threshold: threshold,
    contrast: contrast,
    sharpness: sharpness / (w * h),
    clippedFraction: clipped / (w * h),
  );
}

/// Reconstruct only when the actual digit boxes match the OCR digit sequence
/// and exactly one bottom component lies in an internal character gap.
WeightOcrResult reconcileVisualDecimal(
  WeightOcrResult reading,
  DisplayGeometry geometry,
) {
  final positions = geometry.characters.map(boxJson).toList();
  var result = reading.copyWith(
    characterPositions: positions,
    diagnostics: {...reading.diagnostics, ...geometry.toJson()},
  );
  if (reading.weight == null) return result;
  if (geometry.characters.isNotEmpty) {
    result = result.copyWith(roiQuality: geometry.quality);
  }
  if (geometry.characters.length != reading.digitSequence.length ||
      geometry.characters.length < 2) {
    // Geometry may be inapplicable to a printed font. Keep legacy recognition,
    // but never ignore a visible candidate that would change the scale.
    if (geometry.points.isNotEmpty) {
      return result.copyWith(failure: 'OCR_DECIMAL_AMBIGUO');
    }
    // A layout with units or unrelated components is not a verified digit
    // segmentation. Preserve legacy OCR if no visual separator contradicts it;
    // never reconstruct a decimal using guessed/equally spaced character slots.
    return result;
  }
  result = result.copyWith(roiQuality: geometry.quality);
  if (geometry.points.length > 1) {
    return result.copyWith(failure: 'OCR_DECIMAL_AMBIGUO');
  }
  if (geometry.points.isEmpty) {
    // An OCR separator without pixel support remains untrusted on a segmented
    // display. Integers stay integers; no expected-decimals inference is used.
    if (reading.recognitionKey.contains('.')) {
      return result.copyWith(
        decimalConfidence: .5,
        failure: 'OCR_DECIMAL_NAO_CONFIRMADO',
      );
    }
    return result;
  }
  final point = geometry.points.single;
  final position = geometry.characters
      .where((c) => c.right <= point.left)
      .length;
  if (point.width * point.height < 2) {
    return result.copyWith(
      decimalConfidence: .5,
      failure: 'OCR_DECIMAL_AMBIGUO',
    );
  }
  final digits = reading.digitSequence;
  final text =
      '${reading.weight! < 0 ? '-' : ''}${digits.substring(0, position)}.${digits.substring(position)}';
  if (reading.recognitionKey.contains('.') && reading.recognitionKey != text) {
    return result.copyWith(failure: 'OCR_DECIMAL_DIVERGENTE');
  }
  return result.copyWith(
    normalizedText: text,
    weight: double.parse(text),
    decimalDetected: true,
    decimalPosition: position,
    decimalConfidence: .98,
  );
}
