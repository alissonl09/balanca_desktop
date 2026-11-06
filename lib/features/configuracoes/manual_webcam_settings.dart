import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../pesagem/manual_capture/camera_service.dart';
import '../pesagem/manual_capture/capture_dialog.dart';
import '../pesagem/manual_capture/capture_models.dart';
import '../pesagem/manual_capture/manual_capture_services.dart';
import 'settings_widgets.dart';

class ManualWebcamSettings extends StatefulWidget {
  const ManualWebcamSettings({
    super.key,
    required this.services,
    this.manualWeighingEnabled = true,
  });
  final ManualCaptureServices services;
  final bool manualWeighingEnabled;
  @override
  State<ManualWebcamSettings> createState() => _ManualWebcamSettingsState();
}

class _ManualWebcamSettingsState extends State<ManualWebcamSettings> {
  List<WeighingCamera> _cameras = [];
  late WebcamConfiguration _config = widget.services.configuration;
  bool _loading = true, _saving = false;
  String? _error;
  late final WeighingCameraService _enumerator = widget.services
      .cameraFactory();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = widget.services.configurationError;
    });
    try {
      final cameras = await _enumerator.listCameras();
      if (mounted) setState(() => _cameras = cameras);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível listar as webcams. Verifique as permissões do Windows.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(WebcamConfiguration next) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.services.configure(next);
      if (mounted) setState(() => _config = next);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível salvar a configuração local da webcam.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _enumerator.stop();
    super.dispose();
  }

  Future<void> _testCamera() async {
    final camera = widget.services.cameraFactory();
    final region = await showDialog<DisplayRegion>(
      context: context,
      builder: (_) => CameraDiagnosticDialog(
        camera: camera,
        cameraId: _config.cameraId!,
        region: _config.region,
        ocr: _config.ocrEnabled
            ? widget.services.liveOcr ?? widget.services.ocr
            : null,
        processor: widget.services.processor,
        configuration: _config,
        diagnosticsStore: widget.services.diagnosticsStore,
      ),
    );
    if (region != null && mounted) {
      await _save(_config.copyWith(region: region));
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _cameras.any((c) => c.id == _config.cameraId);
    return SettingsSection(
      title: 'Webcam da Pesagem Manual',
      description: 'Configuração salva somente nesta estação. Aponte a webcam para o visor do indicador.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.manualWeighingEnabled) ...[
            DropdownButtonFormField<bool>(
              key: ValueKey('manual-weight-ocr-${_config.ocrEnabled}'),
              initialValue: _config.ocrEnabled,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Leitura do peso na pesagem manual',
              ),
              items: const [
                DropdownMenuItem(
                  value: true,
                  child: Text('Ler a imagem por OCR'),
                ),
                DropdownMenuItem(
                  value: false,
                  child: Text('Não ler a imagem: foto e digitação do peso'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        _save(_config.copyWith(ocrEnabled: value));
                      }
                    },
            ),
            const Text(
              'Salvo nesta estação. Sem OCR, a foto é registrada e o campo de peso é liberado imediatamente.',
            ),
          ],
          SwitchListTile(
            title: const Text('Webcam habilitada'),
            value: _config.enabled,
            onChanged: _saving
                ? null
                : (v) => _save(
                    _config.copyWith(
                      enabled: v,
                      cameraId: _config.cameraId,
                      cameraName: _config.cameraName,
                      mirrorHorizontally: _config.mirrorHorizontally,
                    ),
                  ),
          ),
          if (_loading)
            const LinearProgressIndicator()
          else if (_cameras.isEmpty)
            const Text('Nenhuma webcam encontrada.')
          else
            DropdownButtonFormField<String>(
              key: ValueKey('manual-webcam-${_config.cameraId}'),
              initialValue: found ? _config.cameraId : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Webcam para Pesagem Manual',
              ),
              items: _cameras
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (id) {
                      final camera = _cameras.firstWhere((c) => c.id == id);
                      _save(
                        _config.copyWith(
                          enabled: _config.enabled,
                          cameraId: camera.id,
                          cameraName: camera.name,
                          mirrorHorizontally: _config.mirrorHorizontally,
                        ),
                      );
                    },
            ),
          SwitchListTile(
            title: const Text('Inverter horizontalmente'),
            subtitle: const Text(
              'Ative somente se o driver entregar o visor invertido. '
              'Aplica ao preview, OCR e foto salva.',
            ),
            value: _config.mirrorHorizontally,
            onChanged: _saving
                ? null
                : (value) => _save(
                    _config.copyWith(
                      enabled: _config.enabled,
                      cameraId: _config.cameraId,
                      cameraName: _config.cameraName,
                      mirrorHorizontally: value,
                    ),
                  ),
          ),
          if (_config.ocrEnabled)
            ExpansionTile(
              title: const Text('Ajustar ROI e validação OCR'),
              children: [
                const Text(
                  'ROI: enquadre somente o peso principal, sem tara, capacidade ou ícones.',
                ),
                for (final field in ['X', 'Y', 'Largura', 'Altura'])
                  TextFormField(
                    key: ValueKey('roi-$field-${_config.region.toJson()}'),
                    initialValue: switch (field) {
                      'X' => _config.region.left.toString(),
                      'Y' => _config.region.top.toString(),
                      'Largura' => _config.region.width.toString(),
                      _ => _config.region.height.toString(),
                    },
                    decoration: InputDecoration(
                      labelText: 'ROI $field (0 a 1)',
                    ),
                    onFieldSubmitted: _saving
                        ? null
                        : (text) {
                            final v = double.tryParse(
                              text.replaceAll(',', '.'),
                            );
                            if (v == null) return;
                            final r = _config.region;
                            final next = DisplayRegion(
                              deskewDegrees: r.deskewDegrees,
                              left: field == 'X' ? v : r.left,
                              top: field == 'Y' ? v : r.top,
                              width: field == 'Largura' ? v : r.width,
                              height: field == 'Altura' ? v : r.height,
                            );
                            if (next.valid) {
                              _save(_config.copyWith(region: next));
                            } else {
                              setState(
                                () => _error = 'ROI deve ficar dentro da imagem. Reduza largura/altura antes de mover.',
                              );
                            }
                          },
                  ),
                for (final minimum in [true, false])
                  TextFormField(
                    key: ValueKey(
                      'range-$minimum-${_config.minimumWeight}-${_config.maximumWeight}',
                    ),
                    initialValue:
                        (minimum
                                ? _config.minimumWeight
                                : _config.maximumWeight)
                            .toString(),
                    decoration: InputDecoration(
                      labelText: minimum
                          ? 'Peso mínimo OCR (kg)'
                          : 'Peso máximo OCR (kg)',
                    ),
                    onFieldSubmitted: _saving
                        ? null
                        : (text) {
                            final v = double.tryParse(
                              text.replaceAll(',', '.'),
                            );
                            if (v == null ||
                                !v.isFinite ||
                                v < 0 ||
                                (minimum
                                    ? v > _config.maximumWeight
                                    : v < _config.minimumWeight)) {
                              setState(
                                () => _error = 'Faixa de peso inválida.',
                              );
                              return;
                            }
                            _save(
                              _config.copyWith(
                                minimumWeight: minimum ? v : null,
                                maximumWeight: minimum ? null : v,
                              ),
                            );
                          },
                  ),
                const Text(
                  'Pressione Enter em cada campo para salvar nesta estação.',
                ),
                DropdownButtonFormField<int>(
                  key: ValueKey('ocr-consensus-${_config.requiredReadings}'),
                  initialValue: _config.requiredReadings,
                  decoration: const InputDecoration(
                    labelText:
                        'Leituras concordantes para confirmar OCR (mínimo 80%)',
                  ),
                  items: [
                    for (final n in [2, 3, 4, 5])
                      DropdownMenuItem(value: n, child: Text('$n leituras')),
                  ],
                  onChanged: _saving
                      ? null
                      : (n) {
                          if (n != null) {
                            _save(_config.copyWith(requiredReadings: n));
                          }
                        },
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'ocr-decimals-${_config.expectedDecimalPlaces}',
                  ),
                  initialValue:
                      _config.expectedDecimalPlaces?.toString() ?? 'auto',
                  decoration: const InputDecoration(
                    labelText: 'Casas decimais esperadas (somente validação)',
                  ),
                  items: [
                    for (final value in ['auto', '0', '1', '2'])
                      DropdownMenuItem(
                        value: value,
                        child: Text(value == 'auto' ? 'Automático' : value),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => _save(
                          _config.copyWith(
                            expectedDecimalPlaces: int.tryParse(value ?? ''),
                            automaticDecimals: value == 'auto',
                          ),
                        ),
                ),
                if (kDebugMode)
                  SwitchListTile(
                    title: const Text('Diagnóstico OCR'),
                    subtitle: const Text(
                      'Mostra imagens e resultados na captura de Pesagem Manual, somente em debug.',
                    ),
                    value: _config.diagnostics,
                    onChanged: _saving
                        ? null
                        : (v) => _save(_config.copyWith(diagnostics: v)),
                  ),
              ],
            ),
          if (!found && _config.cameraId != null)
            Text(
              'Webcam configurada indisponível: ${_config.cameraName ?? _config.cameraId}',
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: _loading ? null : _load,
                child: const Text('Atualizar webcams'),
              ),
              OutlinedButton(
                onPressed: found && !_saving ? _testCamera : null,
                child: const Text('Testar câmera'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
