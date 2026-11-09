import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'capture_models.dart';

/// Inverse sampling of a projective homography, unit rectangle -> source quad.
/// Corners are clockwise TL, TR, BR, BL inside the unrotated ROI.
img.Image rectifyDisplay(img.Image source, List<DisplayPoint> points) {
  if (points.isEmpty) return source;
  final p0 = points[0], p1 = points[1], p2 = points[2], p3 = points[3];
  final dx1 = p1.x - p2.x, dx2 = p3.x - p2.x, dx3 = p0.x - p1.x + p2.x - p3.x;
  final dy1 = p1.y - p2.y, dy2 = p3.y - p2.y, dy3 = p0.y - p1.y + p2.y - p3.y;
  final determinant = dx1 * dy2 - dx2 * dy1;
  if (determinant.abs() < 1e-8) {
    throw const FormatException('Degenerate display quadrilateral');
  }
  final g = (dx3 * dy2 - dx2 * dy3) / determinant,
      h = (dx1 * dy3 - dx3 * dy1) / determinant;
  final a = p1.x - p0.x + g * p1.x, b = p3.x - p0.x + h * p3.x;
  final d = p1.y - p0.y + g * p1.y, e = p3.y - p0.y + h * p3.y;
  double distance(DisplayPoint p, DisplayPoint q) => math.sqrt(
    math.pow((p.x - q.x) * source.width, 2) +
        math.pow((p.y - q.y) * source.height, 2),
  );
  final width = math
      .max(distance(p0, p1), distance(p3, p2))
      .round()
      .clamp(8, 1200);
  final height = math
      .max(distance(p0, p3), distance(p1, p2))
      .round()
      .clamp(8, 720);
  final result = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final u = x / (width - 1), v = y / (height - 1), z = g * u + h * v + 1;
      final sx = ((a * u + b * v + p0.x) / z * (source.width - 1))
          .clamp(0, source.width - 1)
          .toDouble();
      final sy = ((d * u + e * v + p0.y) / z * (source.height - 1))
          .clamp(0, source.height - 1)
          .toDouble();
      // Bilinear interpolation avoids holes and aliasing in perspective views.
      final ix = sx.floor(), iy = sy.floor(), fx = sx - ix, fy = sy - iy;
      final c00 = source.getPixel(ix, iy),
          c10 = source.getPixel(math.min(ix + 1, source.width - 1), iy);
      final c01 = source.getPixel(ix, math.min(iy + 1, source.height - 1)),
          c11 = source.getPixel(
            math.min(ix + 1, source.width - 1),
            math.min(iy + 1, source.height - 1),
          );
      num mix(num c0, num c1, num c2, num c3) =>
          c0 * (1 - fx) * (1 - fy) +
          c1 * fx * (1 - fy) +
          c2 * (1 - fx) * fy +
          c3 * fx * fy;
      result.setPixelRgb(
        x,
        y,
        mix(c00.r, c10.r, c01.r, c11.r).round(),
        mix(c00.g, c10.g, c01.g, c11.g).round(),
        mix(c00.b, c10.b, c01.b, c11.b).round(),
      );
    }
  }
  return result;
}
