import 'package:image/image.dart' as img;

import 'capture_models.dart';

/// Bake EXIF rotation/reflection into the pixels before cropping or stamping.
/// The station adjustment describes a residual driver reflection AFTER EXIF;
/// a front-facing lens or the preview's mirror is not capture metadata.
img.Image normalizeCameraImage(CapturedPhoto photo) {
  final decoded = img.decodeImage(photo.bytes);
  if (decoded == null || decoded.width < 64 || decoded.height < 64) {
    throw const CaptureFailure(
      'IMAGEM_INVALIDA',
      'Imagem inválida. Capture novamente.',
    );
  }
  final oriented = img.bakeOrientation(decoded);
  return photo.mirrorHorizontally ? img.flipHorizontal(oriented) : oriented;
}
