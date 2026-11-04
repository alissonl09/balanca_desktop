import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'capture_models.dart';

abstract interface class WeighingCameraService {
  Future<List<WeighingCamera>> listCameras();
  Future<void> start(String cameraId);
  Widget preview();
  Future<CapturedPhoto> capture();
  Future<void> stop();
}

abstract interface class WeighingCameraGeometry {
  double get previewAspectRatio;
}

class DesktopWeighingCameraService
    implements WeighingCameraService, WeighingCameraGeometry {
  DesktopWeighingCameraService({this.mirrorHorizontally = false});
  final bool mirrorHorizontally;
  CameraController? _controller;
  bool _stopped = false;
  @override
  double get previewAspectRatio => _controller?.value.aspectRatio ?? 16 / 9;
  @override
  Future<List<WeighingCamera>> listCameras() async {
    try {
      final cameras = await availableCameras().timeout(
        const Duration(seconds: 10),
      );
      // camera_windows returns "Friendly name <symbolic device link>".
      return cameras.map((c) {
        final separator = c.name.lastIndexOf(' <');
        final label = separator > 0 ? c.name.substring(0, separator) : c.name;
        return WeighingCamera(c.name, label);
      }).toList();
    } catch (_) {
      throw const CaptureFailure(
        'CAMERA_INDISPONIVEL',
        'Não foi possível listar as webcams. Verifique conexão e permissões do Windows.',
      );
    }
  }

  @override
  Future<void> start(String cameraId) async {
    try {
      final devices = await availableCameras().timeout(
        const Duration(seconds: 10),
      );
      if (_stopped) return;
      final matches = devices.where((c) => c.name == cameraId);
      if (matches.isEmpty) {
        throw const CaptureFailure(
          'CAMERA_INDISPONIVEL',
          'Webcam selecionada indisponível ou removida.',
        );
      }
      final controller = CameraController(
        matches.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      // A late initialization is still disposed if the dialog closes or times out.
      final initialization = controller.initialize();
      unawaited(
        initialization.then((_) async {
          if (_stopped) {
            try {
              await controller.dispose();
            } catch (_) {
              /* Already released. */
            }
          }
        }, onError: (Object _) {}),
      );
      await initialization.timeout(const Duration(seconds: 15));
      if (_stopped) return;
    } on CaptureFailure {
      rethrow;
    } catch (_) {
      await stop();
      throw const CaptureFailure(
        'CAMERA_INDISPONIVEL',
        'Erro ao abrir câmera. Verifique se está em uso, conectada e com acesso permitido no Windows.',
      );
    }
  }

  @override
  Widget preview() {
    final controller = _controller;
    if (controller == null) {
      return const Center(
        child: Text(
          'Câmera indisponível',
          style: TextStyle(color: Color(0xffffffff)),
        ),
      );
    }
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.hasError) {
          return const Center(
            child: Text(
              'Câmera indisponível. Verifique a conexão e tente capturar novamente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xffffffff)),
            ),
          );
        }
        if (!value.isInitialized) {
          return const Center(
            child: Text(
              'Inicializando câmera',
              style: TextStyle(color: Color(0xffffffff)),
            ),
          );
        }
        return UnmirroredCameraPreview(
          mirrorHorizontally: mirrorHorizontally,
          child: CameraPreview(controller),
        );
      },
    );
  }

  @override
  Future<CapturedPhoto> capture() async {
    final controller = _controller;
    if (_stopped ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.hasError) {
      throw const CaptureFailure('CAMERA_INDISPONIVEL', 'Câmera indisponível.');
    }
    try {
      var expired = false;
      final capture = controller.takePicture();
      unawaited(
        capture.then((latePhoto) async {
          if (expired) {
            try {
              await File(latePhoto.path).delete();
            } catch (_) {
              /* Temporary snapshot only. */
            }
          }
        }, onError: (Object _) {}),
      );
      final photo = await capture.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          expired = true;
          throw TimeoutException('Snapshot timeout');
        },
      );
      final capturedAt = DateTime.now();
      try {
        return CapturedPhoto(
          await photo.readAsBytes(),
          capturedAt,
          mirrorHorizontally: mirrorHorizontally,
        );
      } finally {
        final temporary = File(photo.path);
        if (await temporary.exists()) await temporary.delete();
      }
    } catch (_) {
      throw const CaptureFailure(
        'ERRO_CAPTURA',
        'Não foi possível capturar a foto. Verifique a webcam.',
      );
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    final controller = _controller;
    _controller = null;
    try {
      await controller?.dispose();
    } catch (_) {
      /* Device may be unplugged. */
    }
  }
}

/// camera_windows 0.3.0+1 mirrors only its native preview texture, with no
/// public Dart setter. Its photo sink does not apply that software mirror.
/// Cancel it here; apply any explicit driver adjustment to BOTH paths.
class UnmirroredCameraPreview extends StatelessWidget {
  const UnmirroredCameraPreview({
    super.key,
    required this.child,
    this.mirrorHorizontally = false,
  });
  final Widget child;
  final bool mirrorHorizontally;

  @override
  Widget build(BuildContext context) {
    final pluginMirrorsPreview =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    return Transform.flip(
      flipX: pluginMirrorsPreview != mirrorHorizontally,
      child: child,
    );
  }
}
