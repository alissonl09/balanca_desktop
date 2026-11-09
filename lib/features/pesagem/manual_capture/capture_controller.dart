import 'dart:math';

import 'package:flutter/foundation.dart';

import '../manual_weighing_policy.dart';
import 'camera_service.dart';
import 'capture_models.dart';
import 'manual_capture_services.dart';
import 'image_processor.dart';
import 'captured_image_analysis.dart';

class ManualCaptureController extends ChangeNotifier {
  ManualCaptureController({
    required this.authorization,
    required this.services,
    this.plate = '',
  }) : camera = services.cameraFactory(),
       configuration = services.configuration;
  final ManualAuthorization authorization;
  final ManualCaptureServices services;
  final WeighingCameraService camera;
  final WebcamConfiguration configuration;
  final String plate;
  DisplayRegion get region => configuration.region;
  ProcessedCapture? diagnosticCapture;
  Uint8List? capturedImage;
  String? originalImagePath;
  int stableReadings = 0;
  CaptureStage stage = CaptureStage.cameraInitializing;
  String message = 'Inicializando câmera';
  String? failureReason, photoFailureReason, imagePath, persistenceError;
  WeightOcrResult ocr = const WeightOcrResult();
  DateTime? capturedAt;
  String? attemptId;
  double? manualWeight;
  bool cameraActive = false;
  bool _closed = false;
  bool _disposed = false;
  bool get previewRecognized => stage == CaptureStage.ocrSuccess;
  String get recognizedText =>
      previewRecognized ? ocr.weight!.truncate().toString() : '';
  bool get busy => [
    CaptureStage.cameraInitializing,
    CaptureStage.capturing,
    CaptureStage.ocrProcessing,
    CaptureStage.saving,
  ].contains(stage);
  bool get manualAllowed =>
      stage == CaptureStage.manualFallback || stage == CaptureStage.manualEntry;
  double? get finalWeight => stage == CaptureStage.ocrSuccess
      ? ocr.weight?.truncateToDouble()
      : manualAllowed
      ? manualWeight
      : null;
  bool get canConfirm =>
      !busy &&
      finalWeight != null &&
      finalWeight!.isFinite &&
      finalWeight! >= 0;
  WeightSource get source => ocr.success && stage == CaptureStage.ocrSuccess
      ? WeightSource.cameraOcr
      : !configuration.ocrEnabled && imagePath != null && failureReason == null
      ? WeightSource.manualPhoto
      : WeightSource.manualFallback;

  void _update(CaptureStage next, String status) {
    if (_closed) return;
    stage = next;
    message = status;
    notifyListeners();
  }

  void _fallback(String code, String status) {
    failureReason = code;
    _update(
      CaptureStage.manualFallback,
      'Não foi possível identificar o peso automaticamente. $status',
    );
  }

  Future<void> initialize() async {
    if (!configuration.enabled || configuration.cameraId == null) {
      photoFailureReason = configuration.enabled
          ? 'CAMERA_NAO_CONFIGURADA'
          : 'CAMERA_DESABILITADA';
      _fallback(
        photoFailureReason!,
        configuration.enabled
            ? 'Nenhuma câmera configurada.'
            : 'Webcam desabilitada.',
      );
      return;
    }
    try {
      await camera.start(configuration.cameraId!);
      if (_closed) return;
      cameraActive = true;
      _update(
        CaptureStage.cameraReady,
        configuration.ocrEnabled
            ? 'Câmera ativa. Enquadre somente o visor na região marcada e capture o peso.'
            : 'OCR desabilitado. Capture a foto para informar o peso.',
      );
    } catch (error) {
      if (_closed) return;
      photoFailureReason = error is CaptureFailure
          ? error.code
          : 'CAMERA_INDISPONIVEL';
      _fallback(
        photoFailureReason!,
        error is CaptureFailure ? error.message : 'Erro ao abrir câmera.',
      );
    }
  }

  static String newId(DateTime time) =>
      '${time.year}${time.month.toString().padLeft(2, '0')}${time.day.toString().padLeft(2, '0')}_${time.hour.toString().padLeft(2, '0')}${time.minute.toString().padLeft(2, '0')}${time.second.toString().padLeft(2, '0')}_${time.microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  Future<void> capture() async {
    if (busy || !cameraActive || _closed) return;
    _update(CaptureStage.capturing, 'Capturando imagem...');
    manualWeight = null;
    ocr = const WeightOcrResult();
    stableReadings = 0;
    failureReason = null;
    diagnosticCapture = null;
    persistenceError = null;
    try {
      final frame = await camera.capture();
      if (_closed) return;
      final photo = CapturedPhoto(
        Uint8List.fromList(frame.bytes),
        frame.capturedAt,
        mirrorHorizontally: frame.mirrorHorizontally,
      );
      final id = newId(photo.capturedAt);
      // Store the exact camera bytes before any decode, crop or preprocessing.
      final originalPath = await services.evidenceStore.saveOriginal(
        id,
        photo.bytes,
      );
      if (_closed) return;
      final evidence = services.processor is EvidenceOnlyImageProcessor
          ? await (services.processor as EvidenceOnlyImageProcessor)
                .processEvidence(photo)
          : await services.processor.process(photo, region);
      imagePath = await services.evidenceStore.savePhoto(id, evidence.evidence);
      originalImagePath = originalPath;
      attemptId = id;
      capturedAt = photo.capturedAt;
      photoFailureReason = null;
      capturedImage = Uint8List.fromList(evidence.evidence);
      if (_closed) return;
      // Journal the immutable photograph even if analysis crashes or is cancelled.
      await services.evidenceStore.save(_evidence(id: id, weight: null));
      if (!configuration.ocrEnabled) {
        _update(
          CaptureStage.manualEntry,
          'Foto salva. Informe o peso manualmente.',
        );
        return;
      }
      _update(CaptureStage.ocrProcessing, 'Analisando imagem...');
      try {
        final analysis = await analyzeCapturedImage(
          photo,
          configuration: configuration,
          processor: services.processor,
          recognition: services.recognitionFor(configuration),
        );
        if (_closed) return;
        diagnosticCapture = analysis.capture;
        ocr = analysis.result.copyWith(
          diagnostics: {
            ...analysis.result.diagnostics,
            'originalImagePath': originalImagePath,
            'evidenceImagePath': imagePath,
          },
        );
      } catch (_) {
        if (_closed) return;
        ocr = const WeightOcrResult(error: 'OCR_ERRO_ANALISE');
      }
      stableReadings = ocr.diagnostics['pipelineSupport'] as int? ?? 0;
      failureReason = ocr.success ? null : ocr.error ?? 'OCR_SEM_LEITURA';
      await services.evidenceStore.save(
        _evidence(id: newId(DateTime.now()), weight: null),
      );
      if (_closed) return;
      if (kDebugMode &&
          configuration.diagnostics &&
          diagnosticCapture != null) {
        try {
          await services.diagnosticsStore?.save(
            diagnosticCapture!,
            ocr,
            region,
          );
        } catch (_) {
          debugPrint('Não foi possível salvar o diagnóstico OCR opcional.');
        }
      }
      if (ocr.success) {
        _update(
          CaptureStage.ocrSuccess,
          'Peso identificado. Confirme o peso para prosseguir.',
        );
      } else {
        _fallback(
          failureReason!,
          'Não foi possível identificar o peso na imagem. '
          'Capture novamente ou informe o peso manualmente. A foto foi preservada.',
        );
      }
    } catch (error) {
      if (_closed) return;
      photoFailureReason = error is CaptureFailure
          ? error.code
          : 'ERRO_CAPTURA_OU_EVIDENCIA';
      _fallback(
        photoFailureReason!,
        error is CaptureFailure ? error.message : 'Falha na captura ou gravação da evidência. A última foto salva foi preservada.',
      );
    }
  }

  void resumeCamera() {
    if (!cameraActive || busy || _closed) return;
    capturedImage = null;
    manualWeight = null;
    ocr = const WeightOcrResult();
    stableReadings = 0;
    _update(
      CaptureStage.cameraReady,
      'Câmera ativa. Enquadre a Área do Peso e capture uma nova foto.',
    );
  }

  void setManualWeight(String text) {
    if (!manualAllowed) return;
    manualWeight = double.tryParse(text.replaceAll(',', '.'));
    notifyListeners();
  }

  ManualWeighingEvidence _evidence({
    required String id,
    required double? weight,
    DateTime? confirmedAt,
  }) => ManualWeighingEvidence(
    id: id,
    dateTime: capturedAt ?? DateTime.now(),
    confirmedAt: confirmedAt,
    authorizer: authorization.user,
    justification: authorization.justification,
    plate: plate,
    source: configuration.ocrEnabled && ocr.success && failureReason == null
        ? WeightSource.cameraOcr
        : source,
    ocrEnabled: configuration.ocrEnabled,
    finalWeight: weight,
    cameraId: configuration.cameraId,
    cameraName: configuration.cameraName,
    imagePath: imagePath,
    originalImagePath: originalImagePath,
    captureAttemptId: attemptId,
    ocr: ocr,
    failureReason: failureReason,
    photoFailureReason: imagePath == null
        ? photoFailureReason ?? failureReason
        : photoFailureReason,
    region: region,
    stableReadings: stableReadings,
  );

  Future<ManualWeighingEvidence?> confirm() async {
    if (!canConfirm) return null;
    final weight = finalWeight!;
    final previous = stage;
    _update(CaptureStage.saving, 'Salvando evidência...');
    final now = DateTime.now();
    // Finalization has its own identity, even when no image can be obtained.
    final evidence = _evidence(
      id: newId(now),
      weight: weight,
      confirmedAt: now,
    );
    try {
      await services.evidenceStore.save(evidence);
      if (_closed) return null;
      _update(CaptureStage.confirmed, 'Peso confirmado');
      await close();
      return evidence;
    } catch (_) {
      persistenceError = 'Não foi possível salvar a auditoria local. Verifique espaço e permissões e tente novamente.';
      _update(previous, message);
      return null;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    cameraActive = false;
    try {
      await camera.stop();
    } catch (_) {
      /* Release failure must not trap the operator. */
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    close();
    super.dispose();
  }
}
