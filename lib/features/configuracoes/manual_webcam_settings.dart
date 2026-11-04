import 'package:flutter/material.dart';

import '../pesagem/manual_capture/camera_service.dart';
import '../pesagem/manual_capture/capture_dialog.dart';
import '../pesagem/manual_capture/capture_models.dart';
import '../pesagem/manual_capture/manual_capture_services.dart';
import 'settings_widgets.dart';

class ManualWebcamSettings extends StatefulWidget {
  const ManualWebcamSettings({super.key, required this.services});
  final ManualCaptureServices services;
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
    await showDialog<void>(
      context: context,
      builder: (_) =>
          CameraDiagnosticDialog(camera: camera, cameraId: _config.cameraId!),
    );
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
          SwitchListTile(
            title: const Text('Webcam habilitada'),
            value: _config.enabled,
            onChanged: _saving
                ? null
                : (v) => _save(
                    WebcamConfiguration(
                      enabled: v,
                      cameraId: _config.cameraId,
                      cameraName: _config.cameraName,
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
                        WebcamConfiguration(
                          enabled: _config.enabled,
                          cameraId: camera.id,
                          cameraName: camera.name,
                        ),
                      );
                    },
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
