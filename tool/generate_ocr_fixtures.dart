// Deterministic synthetic fixtures, not photographs of certified indicators.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

void main() {
  final root = Directory('test/fixtures/weight_ocr')
    ..createSync(recursive: true);
  img.Image display(String text, {bool low = false, bool green = false}) {
    final image = img.Image(width: 360, height: 100);
    img.fill(image, color: img.ColorRgb8(12, 22, 30));
    img.drawString(
      image,
      text,
      font: img.arial48,
      x: 24,
      y: 25,
      color: low
          ? img.ColorRgb8(48, 65, 68)
          : green
          ? img.ColorRgb8(25, 245, 35)
          : img.ColorRgb8(20, 240, 245),
    );
    return image;
  }

  final base = display('12190');
  final random = Random(560570);
  final noisy = img.Image.from(base);
  for (final p in noisy) {
    final delta = random.nextInt(21) - 10;
    p.setRgb(
      (p.r + delta).clamp(0, 255),
      (p.g + delta).clamp(0, 255),
      (p.b + delta).clamp(0, 255),
    );
  }
  final fixtures = {
    '12190': base,
    'zero': display('0'),
    '10000': display('10000'),
    'ind560_decimal': display('0.000'),
    'ind570_decimal': display('570.0', green: true),
    'low_contrast': display('12190', low: true),
    'mirrored': img.flipHorizontal(img.Image.from(base)),
    'noise': noisy,
    'no_number': display('kg'),
    'two_numbers': display('12190 123'),
    'perspective': img.copyRectify(
      base,
      topLeft: img.Point(0, -8),
      topRight: img.Point(359, 8),
      bottomLeft: img.Point(-12, 108),
      bottomRight: img.Point(371, 92),
      interpolation: img.Interpolation.cubic,
    ),
  };
  img.Image panel(String text) {
    final image = img.Image(width: 640, height: 260);
    img.fill(image, color: img.ColorRgb8(48, 52, 54));
    final white = img.ColorRgb8(225, 225, 225);
    img.drawString(
      image,
      'METTLER TOLEDO',
      font: img.arial24,
      x: 15,
      y: 10,
      color: white,
    );
    img.drawString(
      image,
      'Max 1.5 t/d=0.5 kg',
      font: img.arial14,
      x: 25,
      y: 55,
      color: white,
    );
    final digits = display(text);
    img.compositeImage(
      image,
      img.copyResize(digits, width: 480, height: 133),
      dstX: 45,
      dstY: 70,
    );
    img.drawString(
      image,
      '570.0 PT     kg Net',
      font: img.arial14,
      x: 55,
      y: 215,
      color: white,
    );
    for (final y in [70, 115, 160, 205]) {
      for (final x in [555, 600]) {
        img.fillCircle(image, x: x, y: y, radius: 13, color: white);
        img.drawString(
          image,
          '2',
          font: img.arial14,
          x: x - 4,
          y: y - 7,
          color: img.ColorRgb8(50, 50, 50),
        );
      }
    }
    return image;
  }

  fixtures['panel_570'] = panel('570.0');
  fixtures['panel_negative'] = panel('-570.0');
  for (final entry in fixtures.entries) {
    File('${root.path}/${entry.key}.png')
        .writeAsBytesSync(img.encodePng(entry.value));
  }
}
