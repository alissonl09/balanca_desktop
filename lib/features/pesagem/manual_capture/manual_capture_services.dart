import 'camera_service.dart';
import 'capture_models.dart';
import 'evidence_store.dart';
import 'image_processor.dart';
import 'weight_ocr_service.dart';
import 'snapshot_weight_recognition.dart';
import 'ocr_diagnostics_store.dart';

/// Application composition root; tests replace dependencies explicitly.
class ManualCaptureServices {
  ManualCaptureServices({
    required this.cameraFactory,
    required this.ocr,
    required this.evidenceStore,
    required this.configurationStore,
    CaptureImageProcessor? processor,
    this.diagnosticsStore,
    this.liveOcr,
    this.recognitionFactory,
  }) : processor = processor ?? LocalCaptureImageProcessor();
  factory ManualCaptureServices.local() {
    final store = LocalManualWeighingStore();
    late final ManualCaptureServices services;
    services = ManualCaptureServices(
      cameraFactory: () => DesktopWeighingCameraService(
        mirrorHorizontally: services.configuration.mirrorHorizontally,
      ),
      ocr: SnapshotWeightRecognition(
        configuration: () => services.configuration,
      ),
      recognitionFactory: (config) =>
          SnapshotWeightRecognition(configuration: () => config),
      evidenceStore: store,
      configurationStore: store,
      diagnosticsStore: LocalOcrDiagnosticsStore(),
    );
    return services;
  }
  static ManualCaptureServices current = ManualCaptureServices.local();
  final WeighingCameraService Function() cameraFactory;
  final WeightOcrService Function(WebcamConfiguration)? recognitionFactory;
  WeightOcrService recognitionFor(WebcamConfiguration config) =>
      recognitionFactory?.call(config) ?? ocr;
  final WeightOcrService ocr;
  final WeightOcrService? liveOcr;
  final ManualWeighingEvidenceStore evidenceStore;
  final WebcamConfigurationStore configurationStore;
  final CaptureImageProcessor processor;
  final OcrDiagnosticsStore? diagnosticsStore;
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
    if ((value.decimalPlaces != null &&
            ![0, 1, 2, 3].contains(value.decimalPlaces)) ||
        !value.region.valid ||
        !value.minimumWeight.isFinite ||
        !value.maximumWeight.isFinite ||
        value.minimumWeight < 0 ||
        value.requiredReadings < 2 ||
        value.requiredReadings > 5 ||
        (value.expectedDecimalPlaces != null &&
            ![0, 1, 2].contains(value.expectedDecimalPlaces)) ||
        value.minimumWeight > value.maximumWeight) {
      throw ArgumentError('ROI ou faixa de peso inválida');
    }
    await configurationStore.saveConfiguration(value);
    configuration = value;
    configurationError = null;
  }
}
