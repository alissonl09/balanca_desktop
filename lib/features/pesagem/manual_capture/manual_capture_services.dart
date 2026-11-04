import 'camera_service.dart';
import 'capture_models.dart';
import 'evidence_store.dart';
import 'image_processor.dart';
import 'weight_ocr_service.dart';

/// Application composition root; tests replace dependencies explicitly.
class ManualCaptureServices {
  ManualCaptureServices({
    required this.cameraFactory,
    required this.ocr,
    required this.evidenceStore,
    required this.configurationStore,
    CaptureImageProcessor? processor,
  }) : processor = processor ?? LocalCaptureImageProcessor();
  factory ManualCaptureServices.local() {
    final store = LocalManualWeighingStore();
    return ManualCaptureServices(
      cameraFactory: DesktopWeighingCameraService.new,
      ocr: TesseractWeightOcrService(),
      evidenceStore: store,
      configurationStore: store,
    );
  }
  static ManualCaptureServices current = ManualCaptureServices.local();
  final WeighingCameraService Function() cameraFactory;
  final WeightOcrService ocr;
  final ManualWeighingEvidenceStore evidenceStore;
  final WebcamConfigurationStore configurationStore;
  final CaptureImageProcessor processor;
  WebcamConfiguration configuration = const WebcamConfiguration();
  String? configurationError;
  Future<void> loadConfiguration() async {
    try {
      configuration = await configurationStore.load();
    } catch (_) {
      configurationError = 'Não foi possível carregar a configuração local da webcam. Selecione e salve novamente.';
    }
  }

  Future<void> configure(WebcamConfiguration value) async {
    await configurationStore.saveConfiguration(value);
    configuration = value;
    configurationError = null;
  }
}
