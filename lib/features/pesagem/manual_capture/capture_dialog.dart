import 'dart:async';

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
import 'weight_dataset_store.dart';
import 'captured_image_analysis.dart';
import 'roi_editor.dart';
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
                'Peso identificado: ${formatWeight(c.finalWeight!)} kg',
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
                    ? 'Capturar novamente'
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
          child: Text(
            c.stage == CaptureStage.ocrSuccess ? 'Confirmar' : 'Prosseguir',
          ),
        ),
      ],
    ),
  );
}

/// The clock is also burned into the saved image by CaptureImageProcessor.
/// Describe the actual recognition state rather than implying detection from
/// the yellow ROI alone. This never enables acceptance or changes OCR rules.
String liveWeightStatus(
  WeightOcrResult result, {
  required bool calibrated,
  required bool ready,
}) {
  if (ready) return 'Número identificado. Capture o peso para confirmar.';
  if (result.error == 'OCR_DIGITS_PENDING_CONSENSUS') {
    return 'Dígitos encontrados. Aguardando consenso '
        '(${result.diagnostics['temporalVotes'] ?? 0}/5 frames concordantes).';
  }
  if (result.success) {
    final votes = result.diagnostics['temporalVotes'] ?? result.consensusCount;
    return 'Leitura encontrada. Aguardando confirmação entre frames '
        '($votes/${result.requiredReadings} leituras concordantes).';
  }
  if (!calibrated) {
    return 'Região do visor ainda não calibrada. Em Configurações → '
        'Testar câmera, marque somente os dígitos do peso e salve a ROI. '
        'O reconhecimento geométrico está desativado até salvar a calibração.';
  }
  if (result.error == null) return 'Analisando os dígitos do visor…';
  return '${ocrFailureMessage(result.error)} '
      'Você pode capturar a foto e digitar o peso.';
}

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
  Future<void> _captureDataset() async {
    if (_analyzing) return;
    setState(() => _analyzing = true);
    try {
      final photo = await widget.camera.capture();
      final path = await const WeightDatasetStore().save(
        photo,
        _region,
        widget.configuration.displayProfile,
      );
      if (mounted) setState(() => _status = 'Amostra salva localmente: $path');
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Falha ao capturar amostra: $error');
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

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
      final analysis = await analyzeCapturedImage(
        photo,
        configuration: widget.configuration.copyWith(region: _region),
        processor: widget.processor!,
        recognition: widget.ocr!,
      );
      if (!mounted) return;
      _capture = analysis.capture;
      _result = analysis.result;
      _stages = {
        for (final attempt in _result!.attempts)
          if (attempt.image.isNotEmpty) attempt.strategy: attempt.image,
      };
      if (kDebugMode && widget.configuration.diagnostics) {
        try {
          _diagnosticPath = await widget.diagnosticsStore?.save(
            _capture!,
            _result!,
            _region,
          );
        } catch (_) {
          _diagnosticPath = 'Não foi possível salvar o diagnóstico opcional.';
        }
      }
      if (mounted) {
        setState(
          () => _status =
              'Imagem de teste analisada. Nenhuma pesagem registrada.',
        );
      }
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
            capturedImage: _capture?.evidence,
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
                      calibrated: true,
                      corners: _region.corners,
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
          SwitchListTile(
            title: const Text('Corrigir perspectiva (quatro cantos)'),
            subtitle: const Text(
              'Arraste os cantos ciano: 1 superior esquerdo, 2 superior direito, 3 inferior direito, 4 inferior esquerdo.',
            ),
            value: _region.corners.isNotEmpty,
            onChanged: _analyzing
                ? null
                : (enabled) => setState(() {
                    _region = DisplayRegion(
                      calibrated: true,
                      left: _region.left,
                      top: _region.top,
                      width: _region.width,
                      height: _region.height,
                      deskewDegrees: _region.deskewDegrees,
                      corners: enabled
                          ? const [
                              DisplayPoint(.02, .02),
                              DisplayPoint(.98, .02),
                              DisplayPoint(.98, .98),
                              DisplayPoint(.02, .98),
                            ]
                          : const [],
                    );
                    _result = null;
                    _capture = null;
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
              'Status: ${_result!.success ? 'leitura válida' : 'leitura inválida'}\nSequência OCR: ${_result!.recognitionKey}\nTexto OCR: ${_result!.rawText}\n'
              'Método: ${_result!.strategy} | Peso: ${_result!.weight?.truncate()} kg\n'
              'Pipelines concordantes: ${_result!.diagnostics['pipelineSupport'] ?? 0}\n'
              'Confiança: ${(_result!.confidence * 100).toStringAsFixed(1)}%\n'
              'Confiança do quadro: ${(_result!.candidateConfidence * 100).toStringAsFixed(1)}%\n'
              'Frame: ${_capture?.frameWidth}x${_capture?.frameHeight} • ROI: ${_capture?.roiWidth}x${_capture?.roiHeight}\n'
              'ROI após correção de inclinação: ${_capture?.ocrWidth}x${_capture?.ocrHeight}\n'
              'Altura média dos dígitos: ${_result!.diagnostics['digitHeightPixels']} px\n'
              'Decimal visual: ${_result!.decimalDetected} • posição: ${_result!.decimalPosition ?? '-'}\n'
              'Nitidez (gradiente): ${_result!.diagnostics['sharpness']} • contraste: ${_result!.diagnostics['contrast']}\n'
              'Modelo: ${_result!.model}\nPSM: ${_result!.psm}\nPipeline: ${_result!.strategy}\n'
              'Tempo: ${_result!.elapsedMs} ms\nFalha: ${_result!.error ?? '-'}\n'
              'OCR bruto: ${_result!.rawDigits}\n'
              'Casas decimais: ${widget.configuration.decimalPlaces ?? "não configuradas"}\n'
              'Valor interpretado: ${_result!.diagnostics['interpretedValue'] ?? "-"}\n'
              'Peso final: ${_result!.diagnostics['finalWeight'] ?? "não liberado"} kg\n'
              'OCR confidence: ${(_result!.ocrConfidence * 100).toStringAsFixed(1)}%\n'
              'Confiança final: ${(_result!.finalConfidence * 100).toStringAsFixed(1)}%\n'
              'Falha do reconhecimento principal: ${_result!.diagnostics['primaryFailure'] ?? '-'}\n'
              'Uma foto analisada; consenso entre pipelines, sem registrar pesagem.',
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
      if (kDebugMode || widget.configuration.diagnostics)
        OutlinedButton(
          onPressed: _active && !_analyzing ? _captureDataset : null,
          child: const Text('Capturar amostra para dataset'),
        ),
      TextButton(
        onPressed: _active && !_analyzing
            ? () => Navigator.pop(context, _region.copyWith(calibrated: true))
            : null,
        child: const Text('Salvar ROI'),
      ),
      if (widget.ocr != null)
        OutlinedButton(
          onPressed: _active && !_analyzing ? _testReading : null,
          child: const Text('Capturar imagem de teste'),
        ),
      TextButton(
        onPressed: _analyzing
            ? null
            : () async {
                await widget.camera.stop();
                if (context.mounted) Navigator.pop(context);
              },
        child: const Text('Fechar'),
      ),
    ],
  );
}

OcrAttempt? selectedDiagnosticAttempt(WeightOcrResult result) => result.attempts
    .where(
      (a) =>
          a.image.isNotEmpty &&
          (a.strategy == result.strategy ||
              result.strategy.endsWith(': ${a.strategy}')),
    )
    .lastOrNull;

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
    final selected = result == null ? null : selectedDiagnosticAttempt(result!);
    final images = <String, Uint8List>{
      if (capture.original != null) 'Frame original': capture.original!,
      if (capture.rawRoi != null) 'ROI original': capture.rawRoi!,
      'ROI corrigida': capture.ocrInput,
      if (result != null)
        for (final attempt in result!.attempts)
          if (attempt.image.isNotEmpty) attempt.strategy: attempt.image,
      if (stages['gray_contrast_2x'] != null)
        'Grayscale / contraste': stages['gray_contrast_2x']!,
      if (stages['otsu_2x'] != null) 'Threshold Otsu': stages['otsu_2x']!,
      if (selected != null)
        'Imagem de diagnostico (${result!.strategy})': selected.image,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result != null && result!.attempts.isNotEmpty) ...[
          const Text(
            'Resultados por tentativa (imagem legível não garante reconhecimento)',
          ),
          for (final attempt in result!.attempts)
            SelectableText(
              '${attempt.strategy} • modelo: ${attempt.result.model} • PSM: ${attempt.result.psm}\n'
              'Texto retornado: ${attempt.result.rawText.isEmpty ? "(vazio)" : attempt.result.rawText}\n'
              'Confiança retornada: ${(attempt.result.confidence * 100).toStringAsFixed(1)}% • '
              'Falha: ${attempt.result.error ?? "nenhuma"}',
            ),
          const SizedBox(height: 12),
        ],
        Wrap(
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
        ),
      ],
    );
  }
}
