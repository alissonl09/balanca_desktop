import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Analytic seven-segment test display, not a photograph or learned output.
Uint8List displayFixture(
  String text, {
  int digitHeight = 64,
  int dotSize = 5,
  int intensity = 235,
  bool inverted = false,
}) {
  final h = digitHeight,
      w = (h * .55).round(),
      t = (h * .1).round().clamp(2, 20);
  final image = img.Image(width: 20 + text.length * (w + 10), height: h + 24);
  img.fill(image, color: img.ColorRgb8(12, 12, 12));
  const masks = {
    '0': [0, 1, 2, 4, 5, 6],
    '1': [2, 5],
    '2': [0, 2, 3, 4, 6],
    '3': [0, 2, 3, 5, 6],
    '4': [1, 2, 3, 5],
    '5': [0, 1, 3, 5, 6],
    '6': [0, 1, 3, 4, 5, 6],
    '7': [0, 2, 5],
    '8': [0, 1, 2, 3, 4, 5, 6],
    '9': [0, 1, 2, 3, 5, 6],
  };
  final color = img.ColorRgb8(intensity, intensity, intensity);
  var x = 10;
  for (final char in text.split('')) {
    if (char == '.') {
      img.fillRect(
        image,
        x1: x,
        y1: 12 + h - dotSize,
        x2: x + dotSize - 1,
        y2: 11 + h,
        color: color,
      );
      x += dotSize + 7;
      continue;
    }
    // The digit 1 retains its actual narrow bounding box, without fake slots.
    final rects = [
      [t, 0, w - t, t],
      [0, t + 1, t, h ~/ 2 - 1],
      [w - t, t + 1, w, h ~/ 2 - 1],
      [t, h ~/ 2 - t ~/ 2, w - t, h ~/ 2 + t ~/ 2],
      [0, h ~/ 2 + 1, t, h - t - 1],
      [w - t, h ~/ 2 + 1, w, h - t - 1],
      [t, h - t, w - t, h],
    ];
    for (final s in masks[char]!) {
      final r = rects[s];
      img.fillRect(
        image,
        x1: x + r[0],
        y1: 12 + r[1],
        x2: x + r[2] - 1,
        y2: 12 + r[3] - 1,
        color: color,
      );
    }
    x += w + 10;
  }
  final cropped = img.copyCrop(
    image,
    x: 0,
    y: 0,
    width: x + 4,
    height: image.height,
  );
  return Uint8List.fromList(
    img.encodePng(inverted ? img.invert(cropped) : cropped),
  );
}
