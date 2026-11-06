import 'dart:math';

import 'package:image/image.dart' as img;

/// Locates a clearly larger display line by geometry, without decoding digits.
/// Ambiguous layouts retain the complete ROI for the strict OCR parser.
class LocatedWeightLine {
  const LocatedWeightLine(this.image, {this.left = 0, this.top = 0});
  final img.Image image;
  final int left, top;
}

img.Image isolateDominantWeightLine(img.Image source) =>
    locateDominantWeightLine(source).image;

LocatedWeightLine locateDominantWeightLine(img.Image source) {
  // Bound the component scan, while retaining enough detail for decimal points.
  final image = source.width > 1200
      ? img.copyResize(source, width: 1200)
      : source;
  final gray = img.grayscale(img.Image.from(image));
  final histogram = List<int>.filled(256, 0);
  for (final pixel in gray) {
    histogram[pixel.r.toInt()]++;
  }
  final total = gray.width * gray.height;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * histogram[i];
  }
  var count = 0;
  var subtotal = 0.0;
  var variance = -1.0;
  var threshold = 128;
  for (var i = 0; i < 255; i++) {
    count += histogram[i];
    subtotal += i * histogram[i];
    if (count == 0 || count == total) continue;
    final difference = subtotal / count - (sum - subtotal) / (total - count);
    final score = count * (total - count) * difference * difference;
    if (score > variance) {
      variance = score;
      threshold = i;
    }
  }

  final candidates = <Rectangle<int>>[];
  // Scan the minority polarity, avoiding the holes inside 0/6/8/9 being
  // mistaken for a second display line in the opposite polarity.
  final brightCount = histogram.skip(threshold + 1).fold(0, (a, b) => a + b);
  for (final bright in [brightCount < total / 2]) {
    final visited = List<bool>.filled(total, false);
    bool foreground(int index) =>
        (gray.getPixel(index % gray.width, index ~/ gray.width).r >
            threshold) ==
        bright;
    final components = <Rectangle<int>>[];
    final marks = <Rectangle<int>>[];
    for (var start = 0; start < total; start++) {
      if (visited[start]) continue;
      visited[start] = true;
      if (!foreground(start)) continue;
      final queue = <int>[start];
      var left = start % gray.width, right = left;
      var top = start ~/ gray.width, bottom = top;
      for (var cursor = 0; cursor < queue.length; cursor++) {
        final index = queue[cursor];
        final x = index % gray.width, y = index ~/ gray.width;
        left = min(left, x);
        right = max(right, x);
        top = min(top, y);
        bottom = max(bottom, y);
        for (final next in [
          if (x > 0) index - 1,
          if (x + 1 < gray.width) index + 1,
          if (y > 0) index - gray.width,
          if (y + 1 < gray.height) index + gray.width,
        ]) {
          if (visited[next]) continue;
          visited[next] = true;
          if (foreground(next)) queue.add(next);
        }
      }
      final width = right - left + 1, height = bottom - top + 1;
      if (queue.length >= 3 &&
          left > 0 &&
          top > 0 &&
          right < image.width - 1 &&
          bottom < image.height - 1) {
        marks.add(Rectangle(left, top, width, height));
      }
      if (height < 12 ||
          width < height * .1 ||
          width > height * 1.15 ||
          left == 0 ||
          top == 0 ||
          right == image.width - 1 ||
          bottom == image.height - 1 ||
          queue.length < width * height * .1) {
        continue;
      }
      components.add(Rectangle(left, top, width, height));
    }
    if (components.length < 2) continue;
    final height = components.map((c) => c.height).reduce(max);
    if (height < image.height * .12) continue;
    final large = components.where((c) => c.height >= height * .7).toList();
    if (large.length < 2) continue;
    final top = large.map((c) => c.top).reduce(min);
    final bottom = large.map((c) => c.bottom).reduce(max);
    // Two large lines or unrelated tall shapes are not safe to isolate.
    if (bottom - top > height * 1.45) continue;
    final small = components.where((c) => c.height < height * .7);
    if (small.isEmpty || small.any((c) => c.height > height * .65)) continue;
    var left = large.map((c) => c.left).reduce(min);
    final right = large.map((c) => c.right).reduce(max);
    // A separated minus must not disappear when trimming the keypad. Include
    // every horizontal stroke to the left at the main line's middle height.
    for (final mark in marks) {
      final center = mark.top + mark.height / 2;
      if (mark.right <= left &&
          mark.width >= height * .15 &&
          mark.width > mark.height * 1.5 &&
          mark.height <= height * .3 &&
          center >= top + height * .25 &&
          center <= bottom - height * .2) {
        left = min(left, mark.left);
      }
    }
    // Keep nearby signs, separators and units; never substitute glyphs.
    final x = max(0, (left - height * .75).floor());
    final y = max(0, (top - height * .06).floor());
    final endX = min(image.width, (right + height * .5).ceil());
    final endY = min(image.height, (bottom + height * .06).ceil());
    candidates.add(Rectangle(x, y, endX - x, endY - y));
  }
  if (candidates.length != 1) return LocatedWeightLine(source);
  final bounds = candidates.single;
  final factor = source.width / image.width;
  final left = (bounds.left * factor).floor(),
      top = (bounds.top * factor).floor();
  return LocatedWeightLine(
    img.copyCrop(
      source,
      x: left,
      y: top,
      width: (bounds.width * factor).ceil(),
      height: (bounds.height * factor).ceil(),
    ),
    left: left,
    top: top,
  );
}
