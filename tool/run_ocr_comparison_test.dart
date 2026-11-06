import 'package:flutter_test/flutter_test.dart';

import 'compare_weight_models.dart' as comparison;

/// The image/capture services depend on Flutter: use the Flutter test runner,
/// not `dart run` (which cannot provide dart:ui).
void main() {
  const image = String.fromEnvironment('OCR_IMAGE');
  const region = String.fromEnvironment('OCR_REGION', defaultValue: '0,0,1,1');
  const output = String.fromEnvironment(
    'OCR_OUT',
    defaultValue: 'build/ocr-comparison',
  );
  const full = bool.fromEnvironment('OCR_FULL');
  test(
    'offline OCR comparison',
    () async {
      await comparison.main([
        image,
        ...region.split(','),
        '--out=$output',
        if (full) '--full',
      ]);
    },
    skip: image.isEmpty ? 'Defina OCR_IMAGE e OCR_REGION.' : false,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
