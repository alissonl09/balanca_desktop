import 'dart:io';
import 'dart:typed_data';

import 'package:balanca_desktop/features/pesagem/manual_capture/camera_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_controller.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/evidence_store.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_normalizer.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/manual_capture_services.dart';
import 'package:balanca_desktop/features/pesagem/manual_weighing_policy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/manual_capture_mocks.dart';

void main() {
  final time = DateTime(2026, 11, 4, 12, 45, 31);
  img.Image display() {
    final image = img.Image(width: 640, height: 480);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      image,
      x1: 70,
      y1: 130,
      x2: 200,
      y2: 300,
      color: img.ColorRgb8(0, 0, 0),
    );
    img.drawString(
      image,
      '12190',
      font: img.arial48,
      x: 230,
      y: 180,
      color: img.ColorRgb8(0, 0, 0),
    );
    return image;
  }

  CapturedPhoto photo(
    img.Image image, {
    bool mirror = false,
    bool jpeg = false,
  }) => CapturedPhoto(
    Uint8List.fromList(
      jpeg ? img.encodeJpg(image, quality: 100) : img.encodePng(image),
    ),
    time,
    mirrorHorizontally: mirror,
  );

  test('mirror de pixels é corrigido antes do recorte e timestamp', () {
    final original = display();
    final expected = processCapture(photo(original), const DisplayRegion());
    final mirrored = photo(
      img.flipHorizontal(img.Image.from(original)),
      mirror: true,
    );
    final actual = processCapture(mirrored, const DisplayRegion());
    // Exact equality also checks the full timestamp glyphs, not only their presence.
    expect(actual.evidence, expected.evidence);
    expect(actual.ocrInput, expected.ocrInput);
    final evidence = img.decodeJpg(actual.evidence)!;
    expect(evidence.getPixel(100, 200).r, lessThan(10));
    expect(evidence.getPixel(540, 200).r, greaterThan(245));
  });

  test('imagem correta não sofre flip e normalização é idempotente', () {
    final first = normalizeCameraImage(photo(display()));
    final second = normalizeCameraImage(photo(first));
    expect(img.encodePng(second), img.encodePng(display()));
  });

  test(
    'EXIF mirror é aplicado uma vez e removido antes de nova codificação',
    () {
      final raw = img.flipHorizontal(display());
      raw.exif.imageIfd.orientation = 2;
      final normalized = normalizeCameraImage(photo(raw, jpeg: true));
      expect(normalized.getPixel(100, 200).r, lessThan(10));
      expect(normalized.getPixel(540, 200).r, greaterThan(245));
      expect(normalized.exif.imageIfd.hasOrientation, isFalse);
      final again = normalizeCameraImage(photo(normalized));
      expect(img.encodePng(again), img.encodePng(normalized));
    },
  );

  test('EXIF rotação é corrigida antes da ROI', () {
    final rotated = img.copyRotate(display(), angle: -90);
    rotated.exif.imageIfd.orientation = 6;
    final normalized = normalizeCameraImage(photo(rotated, jpeg: true));
    expect(normalized.width, 640);
    expect(normalized.height, 480);
    expect(normalized.getPixel(100, 200).r, lessThan(10));
    expect(normalized.getPixel(540, 200).r, greaterThan(245));
  });

  test(
    'OCR e arquivo salvo recebem imagem normalizada no fluxo real',
    () async {
      final camera = MockWeighingCameraService()
        ..photo = photo(img.flipHorizontal(display()), mirror: true);
      final ocr = MockWeightOcrService();
      final root = await Directory.systemTemp.createTemp(
        'balanca_orientation_',
      );
      final store = LocalManualWeighingStore(directory: () async => root);
      final services = ManualCaptureServices(
        cameraFactory: () => camera,
        ocr: ocr,
        evidenceStore: store,
        configurationStore: store,
      )..configuration = const WebcamConfiguration(cameraId: 'usb-device-id');
      final controller = ManualCaptureController(
        authorization: ManualAuthorization(
          user: 'balanca',
          justification: 'Serial caiu',
        ),
        services: services,
      );
      try {
        await controller.initialize();
        await controller.capture();
        final expected = processCapture(
          photo(display()),
          const DisplayRegion(),
        );
        expect(ocr.lastImage, expected.ocrInput);
        expect(
          await File(controller.imagePath!).readAsBytes(),
          expected.evidence,
        );
        expect(controller.finalWeight, 12190);
        expect((await controller.confirm())!.source, WeightSource.cameraOcr);
      } finally {
        controller.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'configuração antiga não ativa inversão; ajuste local persiste',
    () async {
      expect(
        WebcamConfiguration.fromJson({'enabled': true}).mirrorHorizontally,
        isFalse,
      );
      final root = await Directory.systemTemp.createTemp(
        'balanca_mirror_config_',
      );
      try {
        final store = LocalManualWeighingStore(directory: () async => root);
        await store.saveConfiguration(
          const WebcamConfiguration(mirrorHorizontally: true),
        );
        expect((await store.load()).mirrorHorizontally, isTrue);
        final services = ManualCaptureServices.local();
        expect(
          (services.cameraFactory() as DesktopWeighingCameraService)
              .mirrorHorizontally,
          isFalse,
        );
        services.configuration = await store.load();
        expect(
          (services.cameraFactory() as DesktopWeighingCameraService)
              .mirrorHorizontally,
          isTrue,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    for (final adjustment in [false, true]) {
      testWidgets(
        'preview $platform compensa mirror nativo e ajuste=$adjustment',
        (tester) async {
          await tester.pumpWidget(
            UnmirroredCameraPreview(
              mirrorHorizontally: adjustment,
              child: const SizedBox(width: 100, height: 100),
            ),
          );
          final transform = tester.widget<Transform>(find.byType(Transform));
          final nativeMirrors = platform == TargetPlatform.windows;
          expect(
            transform.transform.entry(0, 0),
            nativeMirrors != adjustment ? -1 : 1,
          );
          // Native texture reflection multiplied by our correction matches capture.
          expect(
            (nativeMirrors ? -1 : 1) * transform.transform.entry(0, 0),
            adjustment ? -1 : 1,
          );
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }
}
