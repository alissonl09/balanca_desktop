import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../manual_weighing_policy.dart';
import '../weighing_preview.dart';
import 'camera_service.dart';
import 'capture_controller.dart';
import 'capture_models.dart';
import 'manual_capture_services.dart';
import 'weight_ocr_service.dart';
import 'image_processor.dart';
import 'ocr_diagnostics_store.dart';
import 'weight_recognition_validation.dart';
import 'roi_editor.dart';
import 'seven_segment_preprocessor.dart';
import 'tesseract_runtime.dart';

Future<ManualWeighingEvidence?> showManualCapture(
  BuildContext context, {
  required ManualAuthorization authorization,
  required ManualCaptureServices services,
  required String plate,
}) {
  final controller = ManualCaptureController(
    authorization: authorization,
    services: services,
    plate: plate,
  );
  return showDialog<ManualWeighingEvidence>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ManualCaptureDialog(controller: controller),
  );
}

class ManualCaptureDialog extends StatefulWidget {
  const ManualCaptureDialog({super.key, required this.controller});
  final ManualCaptureController controller;
  @override
  State<ManualCaptureDialog> createState() => _ManualCaptureDialogState();
}

class _ManualCaptureDialogState extends State<ManualCaptureDialog> {
  final _manual = TextEditingController();
  ManualCaptureController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(_refresh);
    c.initialize();
  }

  void _refresh() {
    if (!mounted) return;
    final recognized = c.recognizedText;
    if (recognized.isNotEmpty && _manual.text != recognized) {
      _manual.text = recognized;
    } else if (recognized.isEmpty &&
        !c.manualAllowed &&
        _manual.text.isNotEmpty) {
      _manual.clear();
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_refresh);
    c.dispose();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !c.busy || c.stage == CaptureStage.cameraInitializing,
    child: AlertDialog(
      key: const ValueKey('manual-weight-dialog'),
      scrollable: true,
      title: const Text('Pesagem Manual — Captura do Peso'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CameraEvidencePreview(
              camera: c.camera,
              active: c.cameraActive,
              status: c.message,
              region: c.region,
              recognized: c.previewRecognized,
              capturedImage: c.capturedImage,
            ),
            const SizedBox(height: 12),
            if (c.busy) const LinearProgressIndicator(),
            Text(c.message),
            if (c.liveEnabled && c.stage == CaptureStage.cameraReady)
              Row(
                children: [
                  Icon(
                    c.previewRecognized
                        ? Icons.check_circle
                        : Icons.center_focus_weak,
                    key: const ValueKey('live-ocr-indicator'),
                    color: c.previewRecognized ? Colors.green : Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.previewRecognized
                          ? 'Número identificado. Capture o peso para confirmar.'
                          : 'Buscando leitura estável. Enquadre o visor na região marcada.',
                    ),
                  ),
                ],
              ),
            if (c.liveEnabled &&
                c.stage == CaptureStage.cameraReady &&
                [
                  'OCR_ENGINE_INDISPONIVEL',
                  'OCR_MODELO_INDISPONIVEL',
                  'OCR_TIMEOUT',
                ].contains(c.liveReader?.result.error))
              Text(
                '${ocrFailureMessage(c.liveReader?.result.error)} Você pode capturar a foto e digitar o peso.',
              ),
            if (c.manualAllowed && c.ocr.weight != null)
              Text(
                'Leitura OCR descartada: ${formatWeight(c.ocr.weight!)} kg • '
                'Confiança: ${(c.ocr.confidence * 100).toStringAsFixed(1)}%',
              ),
            if (c.manualAllowed && c.failureReason == 'OCR_FORA_DA_FAIXA')
              Text(
                'Faixa OCR configurada: ${formatWeight(c.configuration.minimumWeight)} '
                'a ${formatWeight(c.configuration.maximumWeight)} kg.',
              ),
            if (kDebugMode && c.configuration.diagnostics)
              ExpansionTile(
                title: const Text('Diagnóstico OCR'),
                children: [
                  if (c.diagnosticCapture?.original != null) ...[
                    const Text('Original corrigida, sem timestamp'),
                    Image.memory(c.diagnosticCapture!.original!, height: 150),
                    const Text('ROI sem timestamp'),
                    Image.memory(c.diagnosticCapture!.ocrInput, height: 120),
                  ],
                  for (final attempt in c.ocr.attempts) ...[
                    Text(attempt.toJson().toString()),
                    Image.memory(attempt.image, height: 100),
                  ],
                  SelectableText(
                    'Texto: ${c.ocr.rawText}\nConfiança: ${c.ocr.confidence}\n'
                    'Peso: ${c.ocr.weight}\nFalha: ${c.ocr.error ?? c.failureReason}',
                  ),
                ],
              ),
            if (c.stage == CaptureStage.ocrSuccess) ...[
              Text(
                'Peso identificado: ${c.ocr.normalizedText.isEmpty ? formatWeight(c.ocr.weight!) : c.ocr.normalizedText} kg',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Confiança: ${(c.ocr.finalConfidence * 100).toStringAsFixed(1)}%',
              ),
              Text(
                'Modelo: ${c.ocr.model.isEmpty ? 'OCR' : c.ocr.model} • '
                '${c.stableReadings}/${c.configuration.requiredReadings} leituras estáveis',
              ),
            ],
            if (c.imagePath != null)
              const Text('Foto do indicador salva com data e hora.'),
            if (c.manualAllowed && c.imagePath == null)
              const Text(
                'Sem evidência fotográfica. O motivo técnico será registrado.',
              ),
            OutlinedButton.icon(
              onPressed: c.cameraActive && !c.busy
                  ? () {
                      _manual.clear();
                      if (c.capturedImage != null) {
                        c.resumeCamera();
                      } else {
                        c.capture();
                      }
                    }
                  : null,
              icon: Icon(
                c.capturedImage != null
                    ? Icons.videocam_outlined
                    : Icons.camera_alt_outlined,
              ),
              label: Text(
                c.capturedImage != null
                    ? 'Voltar para a câmera'
                    : c.liveEnabled && !c.previewRecognized
                    ? 'Capturar foto e digitar peso'
                    : (c.configuration.ocrEnabled
                          ? 'Capturar peso'
                          : 'Capturar foto'),
              ),
            ),
            TextField(
              key: const ValueKey('manual-weight'),
              controller: _manual,
              enabled: c.manualAllowed,
              onChanged: c.setManualWeight,
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (oldValue, newValue) =>
                      RegExp(r'^\d{0,9}([,.]\d{0,3})?$').hasMatch(newValue.text)
                      ? newValue
                      : oldValue,
                ),
              ],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Peso manual',
                suffixText: 'kg',
                helperText: c.previewRecognized
                    ? 'Preenchido pelo OCR. Edição bloqueada.'
                    : c.configuration.ocrEnabled
                    ? 'Digite após capturar a foto quando a leitura não for confiável.'
                    : 'Capture a foto para liberar a digitação.',
              ),
            ),
            if (c.persistenceError != null)
              Text(
                c.persistenceError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: c.stage == CaptureStage.saving
              ? null
              : () async {
                  await c.close();
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: c.canConfirm
              ? () async {
                  final evidence = await c.confirm();
                  if (context.mounted && evidence != null) {
                    Navigator.pop(context, evidence);
                  }
                }
              : null,
          child: const Text('Prosseguir'),
        ),
      ],
    ),
  );
}

/// The clock is also burned into the saved image by CaptureImageProcessor.
class CameraEvidencePreview extends StatefulWidget {
  const CameraEvidencePreview({
    super.key,
    required this.camera,
    required this.active,
    required this.status,
    this.region = const DisplayRegion(),
    this.onRegionChanged,
    this.recognized = false,
    this.capturedImage,
  });
  final WeighingCameraService camera;
  final bool active;
  final String status;
  final DisplayRegion region;
  final bool recognized;
  final Uint8List? capturedImage;
  final ValueChanged<DisplayRegion>? onRegionChanged;
  @override
  State<CameraEvidencePreview> createState() => _CameraEvidencePreviewState();
}

class _CameraEvidencePreviewState extends State<CameraEvidencePreview> {
  Timer? _timer;
  DateTime _now = DateTime.now();
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: widget.active && widget.camera is WeighingCameraGeometry
        ? (widget.camera as WeighingCameraGeometry).previewAspectRatio
        : 16 / 9,
    child: ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.capturedImage != null)
            Image.memory(
              widget.capturedImage!,
              key: const ValueKey('captured-weight-image'),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, error, stack) => const Center(
                child: Text(
                  'Não foi possível exibir a foto capturada.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            )
          else if (widget.active)
            widget.camera.preview()
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  widget.status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          if (widget.capturedImage == null &&
              widget.active &&
              widget.onRegionChanged != null)
            Positioned.fill(
              child: DisplayRegionEditor(
                region: widget.region,
                onChanged: widget.onRegionChanged!,
              ),
            ),
          if (widget.capturedImage == null && widget.active)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DisplayRegionPainter(
                    widget.region,
                    widget.recognized,
                  ),
                ),
              ),
            ),
          if (widget.capturedImage == null)
            Positioned(
              left: 8,
              bottom: 8,
              child: ColoredBox(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    localTimestamp(_now),
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _DisplayRegionPainter extends CustomPainter {
  const _DisplayRegionPainter(this.region, this.recognized);
  final DisplayRegion region;
  final bool recognized;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * region.left,
        size.height * region.top,
        size.width * region.width,
        size.height * region.height,
      ),
      Paint()
        ..color = recognized ? Colors.green : Colors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_DisplayRegionPainter oldDelegate) =>
      oldDelegate.region != region || oldDelegate.recognized != recognized;
}

/// Diagnostic owns a separate camera instance and has no weighing dependencies.
class CameraDiagnosticDialog extends StatefulWidget {
  const CameraDiagnosticDialog({
    super.key,
    required this.camera,
    required this.cameraId,
    this.region = const DisplayRegion(),
    this.ocr,
    this.processor,
    this.configuration = const WebcamConfiguration(),
    this.diagnosticsStore,
  });
  final DisplayRegion region;
  final WeighingCameraService camera;
  final String cameraId;
  final WeightOcrService? ocr;
  final CaptureImageProcessor? processor;
  final WebcamConfiguration configuration;
  final OcrDiagnosticsStore? diagnosticsStore;
  @override
  State<CameraDiagnosticDialog> createState() => _CameraDiagnosticDialogState();
}

class _CameraDiagnosticDialogState extends State<CameraDiagnosticDialog> {
  bool _active = false;
  String _status = 'Inicializando câmera';
  bool _analyzing = false;
  WeightOcrResult? _result;
  String? _diagnosticPath;
  late DisplayRegion _region = widget.region;
  ProcessedCapture? _capture;
  Map<String, Uint8List> _stages = {};
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await widget.camera.start(widget.cameraId);
      if (mounted) {
        setState(() {
          _active = true;
          _status = 'Câmera ativa — aponte somente para o visor do indicador.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Erro ao abrir câmera. Verifique conexão, permissão e uso por outro programa.',
        );
      }
    }
  }

  Future<void> _testReading() async {
    if (_analyzing || widget.ocr == null || widget.processor == null) return;
    setState(() {
      _analyzing = true;
      _result = null;
      _diagnosticPath = null;
    });
    try {
      final photo = await widget.camera.capture();
      if (!mounted) return;
      final capture = await widget.processor!.process(photo, _region);
      _capture = capture;
      if (capture.roiWidth > 0) {
        try {
          _stages = await Isolate.run(
            () => prepareSevenSegmentVariants(capture.ocrInput),
          );
        } on FormatException {
          _stages = {};
        }
      }
      if (!mounted) return;
      var result = await widget.ocr!.recognize(capture.ocrInput);
      result = result.copyWith(
        diagnostics: {...result.diagnostics, ...capture.dimensions},
      );
      result = WeightRecognitionRules(
        minimum: widget.configuration.minimumWeight,
        maximum: widget.configuration.maximumWeight,
        expectedDecimalPlaces: widget.configuration.expectedDecimalPlaces,
      ).validate(result);
      if (!mounted) return;
      if (kDebugMode && widget.configuration.diagnostics) {
        try {
          _diagnosticPath = await widget.diagnosticsStore?.save(
            capture,
            result,
            _region,
          );
        } catch (_) {
          _diagnosticPath = 'Não foi possível salvar o diagnóstico opcional.';
        }
      }
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => _result = const WeightOcrResult(error: 'ERRO_TESTE_OCR'),
        );
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  void dispose() {
    widget.camera.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Testar câmera'),
    content: SizedBox(
      width: 900,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CameraEvidencePreview(
            camera: widget.camera,
            active: _active,
            status: _status,
            region: _region,
            onRegionChanged: _analyzing
                ? null
                : (region) => setState(() {
                    _region = region;
                    _capture = null;
                    _result = null;
                    _stages = {};
                  }),
          ),
          const Text(
            'Arraste o retângulo para mover. Arraste o canto amarelo para aumentar ou diminuir. Inclua todos os dígitos, sinal e ponto.',
          ),
          Text(
            'Inclinação do visor: ${_region.deskewDegrees.toStringAsFixed(1)}°',
          ),
          Slider(
            value: _region.deskewDegrees,
            min: -6,
            max: 6,
            divisions: 24,
            label: '${_region.deskewDegrees.toStringAsFixed(1)}°',
            onChanged: _analyzing
                ? null
                : (degrees) => setState(() {
                    _region = DisplayRegion(
                      left: _region.left,
                      top: _region.top,
                      width: _region.width,
                      height: _region.height,
                      deskewDegrees: degrees,
                    );
                    _capture = null;
                    _result = null;
                    _stages = {};
                  }),
          ),
          Text(_status),
          if (_analyzing) ...[
            const LinearProgressIndicator(),
            const Text('Analisando visor...'),
          ],
          if (_result != null)
            SelectableText(
              '${_result!.success ? 'Leitura' : 'Leitura não confiável'}: ${_result!.recognitionKey} kg\nTexto OCR: ${_result!.rawText}\n'
              'Confiança OCR: ${(_result!.confidence * 100).toStringAsFixed(1)}%\n'
              'Confiança do quadro: ${(_result!.candidateConfidence * 100).toStringAsFixed(1)}%\n'
              'Frame: ${_capture?.frameWidth}x${_capture?.frameHeight} • ROI: ${_capture?.roiWidth}x${_capture?.roiHeight}\n'
              'ROI após correção de inclinação: ${_capture?.ocrWidth}x${_capture?.ocrHeight}\n'
              'Altura média dos dígitos: ${_result!.diagnostics['digitHeightPixels']} px\n'
              'Decimal visual: ${_result!.decimalDetected} • posição: ${_result!.decimalPosition ?? '-'}\n'
              'Nitidez (gradiente): ${_result!.diagnostics['sharpness']} • contraste: ${_result!.diagnostics['contrast']}\n'
              'Modelo: ${_result!.model}\nPSM: ${_result!.psm}\nPipeline: ${_result!.strategy}\n'
              'Tempo: ${_result!.elapsedMs} ms\nFalha: ${_result!.error ?? '-'}\n'
              'Diagnóstico de um quadro, sem confirmação temporal e sem registrar pesagem.',
            ),
          if ((_result?.diagnostics['sharpness'] as num? ?? 10) < 2)
            const Text(
              'Baixa nitidez na ROI: verifique foco, reflexos e iluminação.',
            ),
          if (_capture != null)
            OcrDiagnosticImages(
              capture: _capture!,
              stages: _stages,
              result: _result,
            ),
          if (_diagnosticPath != null)
            SelectableText('Diagnóstico local: $_diagnosticPath'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _active && !_analyzing
            ? () => Navigator.pop(context, _region)
            : null,
        child: const Text('Salvar ROI'),
      ),
      if (widget.ocr != null)
        OutlinedButton(
          onPressed: _active && !_analyzing ? _testReading : null,
          child: const Text('Testar leitura'),
        ),
      TextButton(
        onPressed: () async {
          await widget.camera.stop();
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Fechar'),
      ),
    ],
  );
}

class OcrDiagnosticImages extends StatelessWidget {
  const OcrDiagnosticImages({
    super.key,
    required this.capture,
    this.stages = const {},
    this.result,
  });
  final ProcessedCapture capture;
  final Map<String, Uint8List> stages;
  final WeightOcrResult? result;
  @override
  Widget build(BuildContext context) {
    final images = <String, Uint8List>{
      if (capture.original != null) 'Frame original': capture.original!,
      'ROI para OCR': capture.ocrInput,
      if (stages['gray_contrast_2x'] != null)
        'Grayscale / contraste': stages['gray_contrast_2x']!,
      if (stages['otsu_2x'] != null) 'Threshold Otsu': stages['otsu_2x']!,
      if (result != null && result!.attempts.any((a) => a.image.isNotEmpty))
        'Entrada Tesseract (${result!.strategy})':
            result!.attempts
                .where(
                  (a) => a.image.isNotEmpty && a.strategy == result!.strategy,
                )
                .firstOrNull
                ?.image ??
            result!.attempts.firstWhere((a) => a.image.isNotEmpty).image,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in images.entries)
          SizedBox(
            width: 260,
            child: Column(
              children: [
                Text(entry.key),
                Image.memory(
                  entry.value,
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (_, error, stack) =>
                      const Text('Imagem indisponível'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
