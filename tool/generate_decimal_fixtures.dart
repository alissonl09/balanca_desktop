import 'dart:io';

import '../test/support/display_fixture.dart';

void main() {
  final dir = Directory('test/fixtures/decimal_geometry')
    ..createSync(recursive: true);
  for (final text in ['0.0', '10.0', '100.0', '570.0', '12190', '5700']) {
    File('${dir.path}/${text.replaceAll('.', '_')}.png')
        .writeAsBytesSync(displayFixture(text));
  }
  File('${dir.path}/small_point.png')
      .writeAsBytesSync(displayFixture('570.0', dotSize: 2));
  File('${dir.path}/low_light.png')
      .writeAsBytesSync(displayFixture('570.0', intensity: 85));
  File('${dir.path}/small_roi.png')
      .writeAsBytesSync(displayFixture('570.0', digitHeight: 24, dotSize: 2));
  File('${dir.path}/large_roi.png')
      .writeAsBytesSync(displayFixture('570.0', digitHeight: 128, dotSize: 8));
}
