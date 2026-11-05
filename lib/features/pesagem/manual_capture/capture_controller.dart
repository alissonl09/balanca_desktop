import 'dart:math';

import 'package:flutter/foundation.dart';

import '../manual_weighing_policy.dart';
import 'camera_service.dart';
import 'capture_models.dart';
import 'manual_capture_services.dart';
import 'image_processor.dart';
import 'tesseract_runtime.dart';
import 'weight_recognition_validation.dart';

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
  bool get busy => [
    CaptureStage.cameraInitializing,
    CaptureStage.capturing,
    CaptureStage.ocrProcessing,
    CaptureStage.saving,
  ].contains(stage);
  bool get manualAllowed => stage == CaptureStage.manualFallback;
  double? get finalWeight => stage == CaptureStage.ocrSuccess
      ? ocr.weight
      : manualAllowed
      ? manualWeight
      : null;
  bool get canConfirm =>
      !busy &&
      finalWeight != null &&
      finalWeight!.isFinite &&
      finalWeight! >= 0;
  WeightSource get source => ocr.success && stage != CaptureStage.manualFallback
      ? WeightSource.cameraOcr
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
        'Câmera ativa. Enquadre somente o visor na região marcada e capture o peso.',
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
    // Keep the most recent saved photograph if a subsequent capture fails.
    ocr = const WeightOcrResult();
    stableReadings = 0;
    diagnosticCapture = null;
    try {
      final consensus = WeightTemporalConsensus(
        requiredReadings: configuration.requiredReadings,
      );
      final rules = WeightRecognitionRules(
        minimum: configuration.minimumWeight,
        maximum: configuration.maximumWeight,
      );
      for (var frame = 0; frame < configuration.requiredReadings; frame++) {
        if (_closed) return;
        final photo = await camera.capture();
        if (_closed) return;
        final processed = await services.processor.process(photo, region);
        if (kDebugMode && configuration.diagnostics) {
          diagnosticCapture = processed;
        }
        if (_closed) return;
        final id = newId(photo.capturedAt);
        final path = await services.evidenceStore.savePhoto(
          id,
          processed.evidence,
        );
        attemptId = id;
        imagePath = path;
        capturedAt = photo.capturedAt;
        photoFailureReason = null;
        persistenceError = null;
        if (_closed) return;
        _update(
          CaptureStage.ocrProcessing,
          'Analisando visor... ${frame + 1}/${configuration.requiredReadings}',
        );
        ocr = await services.ocr.recognize(processed.ocrInput);
        if (_closed) return;
        ocr = consensus.observe(rules.validate(ocr));
        if (kDebugMode && configuration.diagnostics) {
          try {
            await services.diagnosticsStore?.save(processed, ocr, region);
          } catch (_) {
            debugPrint('Não foi possível salvar o diagnóstico OCR opcional.');
          }
          for (final attempt in ocr.attempts) {
            debugPrint('OCR ${attempt.toJson()}');
          }
          debugPrint(
            'OCR rawText: ${ocr.rawText}; confidence: ${ocr.confidence}; '
            'parsedWeight: ${ocr.weight}; preprocessingStrategy: ${ocr.strategy}; '
            'failureReason: ${ocr.error}; frame: ${frame + 1}/${configuration.requiredReadings}',
          );
        }
        stableReadings = consensus.stableReadings;
        failureReason = ocr.success
            ? null
            : ocr.error ??
                  (ocr.weight != null
                      ? 'OCR_BAIXA_CONFIANCA'
                      : 'OCR_SEM_LEITURA');
        // Every successful photo/OCR attempt has its own immutable audit record.
        await services.evidenceStore.save(_evidence(id: id, weight: null));
        if (_closed) return;
        if (ocr.success) {
          if (ocr.consensus) {
            _update(CaptureStage.ocrSuccess, 'Leitura confirmada pela câmera');
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        } else {
          _fallback(
            failureReason!,
            '${ocrFailureMessage(failureReason)} Informe o peso manual. A foto foi preservada. Código: $failureReason.',
          );
          return;
        }
      }
    } catch (error) {
      if (_closed) return;
      photoFailureReason = error is CaptureFailure
          ? error.code
          : 'ERRO_CAPTURA_OU_EVIDENCIA';
      _fallback(
        photoFailureReason!,
        error is CaptureFailure
            ? error.message
            : 'Falha na captura, OCR ou gravação da evidência.',
      );
    }
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
    source: ocr.success && failureReason == null
        ? WeightSource.cameraOcr
        : WeightSource.manualFallback,
    finalWeight: weight,
    cameraId: configuration.cameraId,
    cameraName: configuration.cameraName,
    imagePath: imagePath,
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
