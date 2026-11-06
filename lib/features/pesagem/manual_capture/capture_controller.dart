import 'dart:math';

import 'package:flutter/foundation.dart';

import '../manual_weighing_policy.dart';
import 'camera_service.dart';
import 'capture_models.dart';
import 'manual_capture_services.dart';
import 'image_processor.dart';
import 'tesseract_runtime.dart';
import 'weight_recognition_validation.dart';
import 'live_weight_reader.dart';

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
  bool get liveEnabled => configuration.ocrEnabled && services.liveOcr != null;
  late final LiveWeightReader? liveReader = !liveEnabled
      ? null
      : LiveWeightReader(
          camera: camera,
          processor: services.processor,
          ocr: services.liveOcr!,
          configuration: configuration,
          onChanged: () {
            if (!_closed) notifyListeners();
          },
        );
  bool get previewRecognized =>
      stage == CaptureStage.ocrSuccess || (liveReader?.ready ?? false);
  String get recognizedText => stage == CaptureStage.ocrSuccess
      ? ocr.recognitionKey
      : (liveReader?.ready ?? false)
      ? liveReader!.result.recognitionKey
      : '';
  bool get busy => [
    CaptureStage.cameraInitializing,
    CaptureStage.capturing,
    CaptureStage.ocrProcessing,
    CaptureStage.saving,
  ].contains(stage);
  bool get manualAllowed =>
      stage == CaptureStage.manualFallback || stage == CaptureStage.manualEntry;
  double? get finalWeight => stage == CaptureStage.ocrSuccess
      ? ocr.weight
      : manualAllowed
      ? manualWeight
      : null;
  bool get canConfirm =>
      !busy &&
      (stage != CaptureStage.ocrSuccess || ocr.consensus) &&
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
      if (liveEnabled) liveReader!.start();
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
    if (liveEnabled) {
      await _captureLive();
      return;
    }
    _update(CaptureStage.capturing, 'Capturando imagem...');
    manualWeight = null;
    // Keep the most recent saved photograph if a subsequent capture fails.
    ocr = const WeightOcrResult();
    stableReadings = 0;
    failureReason = null;
    diagnosticCapture = null;
    try {
      final consensus = WeightTemporalConsensus(
        requiredReadings: configuration.requiredReadings,
      );
      final rules = WeightRecognitionRules(
        minimum: configuration.minimumWeight,
        maximum: configuration.maximumWeight,
        expectedDecimalPlaces: configuration.expectedDecimalPlaces,
      );
      for (var frame = 0; frame < consensus.maximumFrames; frame++) {
        if (_closed) return;
        final photo = await camera.capture();
        if (_closed) return;
        final processed =
            !configuration.ocrEnabled &&
                services.processor is EvidenceOnlyImageProcessor
            ? await (services.processor as EvidenceOnlyImageProcessor)
                  .processEvidence(photo)
            : await services.processor.process(photo, region);
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
        capturedImage = processed.evidence;
        capturedAt = photo.capturedAt;
        photoFailureReason = null;
        persistenceError = null;
        if (_closed) return;
        if (!configuration.ocrEnabled) {
          await services.evidenceStore.save(_evidence(id: id, weight: null));
          if (_closed) return;
          _update(
            CaptureStage.manualEntry,
            'Foto salva. Informe o peso manualmente.',
          );
          return;
        }
        _update(
          CaptureStage.ocrProcessing,
          'Analisando visor... ${frame + 1}/${consensus.maximumFrames}',
        );
        ocr = await services.ocr.recognize(processed.ocrInput);
        ocr = ocr.copyWith(
          diagnostics: {...ocr.diagnostics, ...processed.dimensions},
        );
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
        if (ocr.success && ocr.consensus) {
          failureReason = null;
          _update(
            CaptureStage.ocrSuccess,
            'Leitura identificada. Confirme o peso para prosseguir.',
          );
          return;
        }
        if (frame + 1 == consensus.maximumFrames ||
            [
              'OCR_ENGINE_INDISPONIVEL',
              'OCR_TIMEOUT',
              'OCR_FORA_DA_FAIXA',
              'OCR_FAIXA_INVALIDA',
            ].contains(ocr.error)) {
          failureReason ??= 'OCR_SEM_CONSENSO';
          _fallback(
            failureReason!,
            '${ocrFailureMessage(failureReason)} Informe o peso manual. A foto foi preservada. Código: $failureReason.',
          );
          return;
        }
        _update(
          CaptureStage.ocrProcessing,
          'Leitura não confiável. Tentando novamente...',
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
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

  Future<void> _captureLive() async {
    final reader = liveReader!;
    final accepted = reader.ready ? reader.photo : null;
    final acceptedResult = reader.result;
    _update(CaptureStage.capturing, 'Salvando foto do indicador...');
    manualWeight = null;
    failureReason = null;
    persistenceError = null;
    try {
      await reader.stop();
      if (_closed) return;
      final photo = accepted ?? await camera.capture();
      if (_closed) return;
      final capture = accepted != null
          ? await services.processor.process(photo, region)
          : services.processor is EvidenceOnlyImageProcessor
          ? await (services.processor as EvidenceOnlyImageProcessor)
                .processEvidence(photo)
          : await services.processor.process(photo, region);
      if (_closed) return;
      final id = newId(photo.capturedAt);
      imagePath = await services.evidenceStore.savePhoto(id, capture.evidence);
      capturedImage = capture.evidence;
      attemptId = id;
      capturedAt = photo.capturedAt;
      photoFailureReason = null;
      ocr = accepted == null
          ? const WeightOcrResult(error: 'OCR_SEM_LEITURA')
          : acceptedResult;
      stableReadings = ocr.consensusReadings;
      failureReason = accepted == null ? 'OCR_SEM_CONSENSO' : null;
      if (_closed) return;
      await services.evidenceStore.save(_evidence(id: id, weight: null));
      if (_closed) return;
      if (accepted != null) {
        _update(
          CaptureStage.ocrSuccess,
          'Leitura identificada. Confirme o peso para prosseguir.',
        );
      } else {
        _fallback(
          failureReason!,
          'Leitura não confiável. Foto salva. Informe o peso manualmente.',
        );
      }
    } catch (error) {
      if (_closed) return;
      photoFailureReason = error is CaptureFailure
          ? error.code
          : 'ERRO_CAPTURA_OU_EVIDENCIA';
      _fallback(photoFailureReason!, 'Não foi possível salvar a foto.');
    }
  }

  void resumeCamera() {
    if (!cameraActive || busy || _closed) return;
    capturedImage = null;
    manualWeight = null;
    ocr = const WeightOcrResult();
    stableReadings = 0;
    if (liveEnabled) {
      liveReader!.consensus = WeightTemporalConsensus(
        requiredReadings: configuration.requiredReadings,
      );
      liveReader!.photo = null;
      liveReader!.result = const WeightOcrResult();
    }
    _update(
      CaptureStage.cameraReady,
      liveEnabled
          ? 'Aponte o visor para a região marcada. Aguarde a indicação verde.'
          : 'Câmera ativa. Enquadre o visor e capture uma nova foto.',
    );
    liveReader?.start();
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
    final stopped = liveReader?.stop();
    cameraActive = false;
    try {
      await camera.stop();
      await stopped;
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
