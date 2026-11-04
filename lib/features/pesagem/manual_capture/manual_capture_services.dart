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
    late final ManualCaptureServices services;
    services = ManualCaptureServices(
      cameraFactory: () => DesktopWeighingCameraService(
        mirrorHorizontally: services.configuration.mirrorHorizontally,
      ),
      ocr: TesseractWeightOcrService(),
      evidenceStore: store,
      configurationStore: store,
    );
    return services;
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
    if (!value.region.valid ||
        !value.minimumWeight.isFinite ||
        !value.maximumWeight.isFinite ||
        value.minimumWeight < 0 ||
        value.minimumWeight > value.maximumWeight) {
      throw ArgumentError('ROI ou faixa de peso inválida');
    }
    await configurationStore.saveConfiguration(value);
    configuration = value;
    configurationError = null;
  }
}
