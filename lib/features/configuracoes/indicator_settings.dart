import 'package:flutter/material.dart';

import 'dart:io';
import 'dart:async';

import '../../core/indicators/indicator_models.dart';
import 'settings_widgets.dart';

/// Formulários de catálogo e instalação separados, sem transporte ou parser.
class IndicatorSettings extends StatefulWidget {
  const IndicatorSettings({
    super.key,
    required this.configuration,
    required this.models,
  });
  final IndicatorConfiguration configuration;
  final bool models;
  @override
  State<IndicatorSettings> createState() => _IndicatorSettingsState();
}

class _IndicatorSettingsState extends State<IndicatorSettings> {
  String? _selected;
  bool _testing = false;
  String? _testResult;
  IndicatorConfiguration get config => widget.configuration;
  void change(VoidCallback callback) => config.update(callback);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: config,
    builder: (context, _) => widget.models ? _models() : _installations(),
  );

  Widget _models() => SettingsSection(
    title: 'Modelos de Indicadores',
    description:
        'Capacidades por modelo. Cadastre o modelo antes da instalação física.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final model in config.models)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${model.code} — ${model.label}'),
            subtitle: Text(
              '${model.active ? 'Ativo' : 'Inativo'} · '
              '${model.connectionTypes.map((t) => t.label).join(' / ')}\n${model.notes}',
            ),
            trailing: IconButton(
              key: ValueKey('edit-model-${model.code}'),
              tooltip: 'Editar modelo',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editModel(model),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('add-indicator-model'),
            onPressed: () => _editModel(null),
            icon: const Icon(Icons.add),
            label: const Text('Novo modelo'),
          ),
        ),
      ],
    ),
  );

  Future<void> _editModel(IndicatorModel? model) async {
    final result = await showDialog<IndicatorModel>(
      context: context,
      builder: (_) => _ModelDialog(
        model: model,
        existingCodes: config.models.map((m) => m.code).toSet(),
      ),
    );
    if (!mounted || result == null) return;
    if (model == null) {
      config.addModel(result);
    } else {
      change(() => config.models[config.models.indexOf(model)] = result);
    }
  }

  Widget _installations() {
    final installation = config.installations
        .where((i) => i.id == _selected)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Indicadores de Peso',
          description: 'Configuração da instalação física · rascunho local.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in config.installations)
                ListTile(
                  title: Text(
                    item.name.isEmpty ? 'Instalação sem nome' : item.name,
                  ),
                  subtitle: Text(
                    '${config.model(item.modelCode)?.label ?? 'Modelo não selecionado'} · ${item.connectionType?.label ?? 'Sem comunicação'}',
                  ),
                  selected: item.id == _selected,
                  leading: Icon(
                    item.id == _selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  onTap: () => setState(() => _selected = item.id),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('add-indicator'),
                  onPressed: () {
                    final item = IndicatorInstallation(
                      id: 'local-${config.installations.length + 1}',
                    );
                    change(() => config.installations.add(item));
                    setState(() => _selected = item.id);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Novo indicador'),
                ),
              ),
            ],
          ),
        ),
        if (installation != null) ...[
          const SizedBox(height: 16),
          KeyedSubtree(
            key: ValueKey('${installation.id}-${installation.modelCode}'),
            child: _installation(installation),
          ),
        ],
      ],
    );
  }

  Widget _installation(IndicatorInstallation item) {
    final model = config.model(item.modelCode);
    final serial = model?.serial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Identificação',
          child: SettingsFields(
            children: [
              _text(
                'indicator-name',
                'Nome do indicador',
                item.name,
                (v) => item.name = v,
              ),
              _choice<String>('indicator-model', 'Modelo', item.modelCode, {
                for (final m in config.models.where(
                  (m) => m.active || m.code == item.modelCode,
                ))
                  m.code: m.label,
              }, (v) => item.selectModel(config.model(v)!)),
              SettingsToggle(
                label: 'Indicador ativo',
                value: item.active,
                onChanged: (v) => change(() => item.active = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Comunicação',
          description: model?.notes,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _choice<IndicatorConnectionType>(
                'indicator-connection',
                'Tipo de comunicação',
                item.connectionType,
                {
                  for (final t
                      in model?.connectionTypes ?? <IndicatorConnectionType>[])
                    t: t.label,
                },
                (v) => item.connectionType = v,
              ),
              if (model != null && model.connectionTypes.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Capacidades não confirmadas. Aguardar documentação técnica antes de configurar comunicação.',
                  ),
                ),
              const SizedBox(height: 16),
              KeyedSubtree(
                key: ValueKey('${item.connectionType}'),
                child: SettingsFields(
                  children: [
                    if (item.connectionType == IndicatorConnectionType.tcp) ...[
                      _text(
                        'indicator-host',
                        'Endereço IP / Host',
                        item.host ?? '',
                        (v) => item.host = v,
                      ),
                      _number(
                        'indicator-tcp-port',
                        'Porta TCP',
                        item.tcpPort,
                        (v) => item.tcpPort = v,
                        helper: model?.tcp?.primaryPortReference == null
                            ? null
                            : 'Sugestão documental ${model?.tcp?.primaryPortReference}. A porta da instalação prevalece.',
                      ),
                      if (model?.tcp?.dhcp == true)
                        SettingsToggle(
                          label: 'DHCP',
                          value: item.dhcp,
                          onChanged: (v) => change(() => item.dhcp = v),
                        ),
                      _text(
                        'indicator-mask',
                        'Máscara',
                        item.mask ?? '',
                        (v) => item.mask = v,
                      ),
                      _text(
                        'indicator-gateway',
                        'Gateway',
                        item.gateway ?? '',
                        (v) => item.gateway = v,
                      ),
                    ],
                    if (item.connectionType == IndicatorConnectionType.serial &&
                        serial != null) ...[
                      _text(
                        'indicator-com',
                        'Porta COM da estação',
                        item.windowsPort ?? '',
                        (v) => item.windowsPort = v,
                      ),
                      if (serial.interfacesByChannel.isNotEmpty) ...[
                        _choice<String>(
                          'indicator-channel',
                          'Canal do indicador (conforme instalação)',
                          item.channel,
                          {
                            for (final c in serial.interfacesByChannel.keys)
                              c: c,
                          },
                          (v) {
                            item.channel = v;
                            item.physicalInterface = null;
                          },
                        ),
                        _choice<String>(
                          'indicator-interface-${item.channel}',
                          'Interface física',
                          item.physicalInterface,
                          {
                            for (final i
                                in serial.interfacesByChannel[item.channel] ??
                                    <String>[])
                              i: i,
                          },
                          (v) => item.physicalInterface = v,
                        ),
                      ],
                      _choice<int>(
                        'indicator-baud',
                        'Baud Rate',
                        item.baudRate,
                        {for (final v in serial.baudRates) v: '$v'},
                        (v) => item.baudRate = v,
                      ),
                      _choice<int>(
                        'indicator-data-bits',
                        'Data Bits',
                        item.dataBits,
                        {for (final v in serial.dataBits) v: '$v'},
                        (v) => item.dataBits = v,
                      ),
                      _choice<String>(
                        'indicator-parity',
                        'Paridade',
                        item.parity,
                        {for (final v in serial.parities) v: v},
                        (v) => item.parity = v,
                      ),
                      _choice<String>(
                        'indicator-flow',
                        'Flow Control',
                        item.flowControl,
                        {for (final v in serial.flowControls) v: v},
                        (v) => item.flowControl = v,
                      ),
                    ],
                    if (item.connectionType != null) ...[
                      _number(
                        'indicator-timeout',
                        'Timeout (ms)',
                        item.timeoutMs,
                        (v) => item.timeoutMs = v ?? 0,
                      ),
                      if (item.connectionType == IndicatorConnectionType.tcp)
                        _number(
                          'indicator-reconnect',
                          'Intervalo de reconexão (ms)',
                          item.reconnectIntervalMs,
                          (v) => item.reconnectIntervalMs = v ?? 0,
                        ),
                      if (item.connectionType ==
                              IndicatorConnectionType.serial &&
                          serial != null)
                        _choice<int>(
                          'indicator-stop-bits',
                          'Stop Bits',
                          item.stopBits,
                          {for (final v in serial.stopBits) v: '$v'},
                          (v) => item.stopBits = v,
                        ),
                      _choice<String>(
                        'indicator-protocol',
                        'Protocolo / Tipo de saída',
                        item.protocol,
                        {for (final p in model?.protocols ?? <String>[]) p: p},
                        (v) => item.protocol = v,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Diagnóstico do indicador',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _testResult ??
                    'Teste abre uma conexão temporária e não inicia pesagem.',
              ),
              OutlinedButton.icon(
                key: const ValueKey('test-indicator-connection'),
                onPressed: _testing ? null : () => _testConnection(item, model),
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check),
                label: Text(_testing ? 'Testando...' : 'Testar conexão'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _testConnection(
    IndicatorInstallation item,
    IndicatorModel? model,
  ) async {
    final errors = model == null
        ? ['Selecione um modelo.']
        : item.validate(model);
    if (errors.isNotEmpty) {
      setState(() => _testResult = errors.first);
      return;
    }
    setState(() {
      _testing = true;
      _testResult = 'Conectando...';
    });
    String result;
    try {
      if (item.connectionType == IndicatorConnectionType.tcp) {
        final socket = await Socket.connect(
          item.host!,
          item.tcpPort!,
          timeout: Duration(milliseconds: item.timeoutMs),
        );
        await socket.close();
        result = 'Conectado. Comunicação estabelecida; nenhum dado foi interpretado.';
      } else {
        result = 'Porta indisponível: transporte Serial Windows ainda não configurado.';
      }
    } on SocketException {
      result = 'Host inacessível ou porta indisponível.';
    } on TimeoutException {
      result = 'Timeout ao conectar.';
    } catch (_) {
      result = 'Erro de configuração ou transporte.';
    }
    if (mounted) {
      setState(() {
        _testing = false;
        _testResult = result;
      });
    }
  }

  Widget _text(
    String key,
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) => TextFormField(
    key: ValueKey(key),
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    onChanged: onChanged,
  );
  Widget _number(
    String key,
    String label,
    int? value,
    ValueChanged<int?> onChanged, {
    String? helper,
  }) => TextFormField(
    key: ValueKey(key),
    initialValue: value?.toString() ?? '',
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, helperText: helper),
    validator: (v) =>
        int.tryParse(v ?? '') == null ? 'Informe um número inteiro.' : null,
    onChanged: (v) => onChanged(int.tryParse(v)),
  );
  Widget _choice<T>(
    String key,
    String label,
    T? value,
    Map<T, String> options,
    ValueChanged<T> onChanged,
  ) => DropdownButtonFormField<T>(
    key: ValueKey(key),
    initialValue: options.containsKey(value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final entry in options.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(entry.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: options.isEmpty
        ? null
        : (v) {
            if (v != null) change(() => onChanged(v));
          },
  );
}

class _ModelDialog extends StatefulWidget {
  const _ModelDialog({this.model, required this.existingCodes});
  final IndicatorModel? model;
  final Set<String> existingCodes;
  @override
  State<_ModelDialog> createState() => _ModelDialogState();
}

class _ModelDialogState extends State<_ModelDialog> {
  final _form = GlobalKey<FormState>();
  late final _values = <String, String>{
    'code': widget.model?.code ?? '',
    'manufacturer': widget.model?.manufacturer ?? '',
    'model': widget.model?.model ?? '',
    'description': widget.model?.description ?? '',
    'notes': widget.model?.notes ?? '',
    'protocols': widget.model?.protocols.join(';') ?? '',
    'baud': widget.model?.serial?.baudRates.join(',') ?? '',
    'bits': widget.model?.serial?.dataBits.join(',') ?? '',
    'parity': widget.model?.serial?.parities.join(',') ?? '',
    'flow': widget.model?.serial?.flowControls.join(',') ?? '',
    'channels':
        widget.model?.serial?.interfacesByChannel.entries
            .map((e) => '${e.key}:${e.value.join('|')}')
            .join(';') ??
        '',
  };
  late bool _active = widget.model?.active ?? true;
  late bool _serial = widget.model?.serial != null,
      _tcp = widget.model?.tcp != null;
  late bool _dhcp = widget.model?.tcp?.dhcp ?? false;
  List<String> parts(String key, [String separator = ',']) => _values[key]!
      .split(separator)
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  void _save() {
    if (!_form.currentState!.validate()) return;
    final channels = <String, List<String>>{};
    for (final part in parts('channels', ';')) {
      final entry = part.split(':');
      channels[entry.first.trim()] = entry.last
          .split('|')
          .map((s) => s.trim())
          .toList();
    }
    Navigator.pop(
      context,
      IndicatorModel(
        code: _values['code']!.trim(),
        manufacturer: _values['manufacturer']!.trim(),
        model: _values['model']!.trim(),
        description: _values['description']!,
        notes: _values['notes']!,
        active: _active,
        protocols: parts('protocols', ';'),
        serial: !_serial
            ? null
            : SerialCapabilities(
                baudRates: parts('baud').map(int.parse).toList(),
                dataBits: parts('bits').map(int.parse).toList(),
                parities: parts('parity'),
                flowControls: parts('flow'),
                interfacesByChannel: channels,
              ),
        tcp: !_tcp
            ? null
            : TcpCapabilities(
                dhcp: _dhcp,
                primaryPortReference: widget.model?.tcp?.primaryPortReference,
              ),
      ),
    );
  }

  Widget field(
    String key,
    String label, {
    bool required = false,
    bool numbers = false,
  }) => TextFormField(
    key: ValueKey('model-$key'),
    initialValue: _values[key],
    readOnly: key == 'code' && widget.model != null,
    decoration: InputDecoration(labelText: label),
    onChanged: (v) => _values[key] = v,
    validator: (v) {
      if (required && (v ?? '').trim().isEmpty) return 'Campo obrigatório.';
      if (key == 'code' &&
          widget.model == null &&
          widget.existingCodes.contains(v?.trim())) {
        return 'Código já cadastrado.';
      }
      if (numbers &&
          parts(key).any((p) => int.tryParse(p) == null || int.parse(p) <= 0)) {
        return 'Use números positivos separados por vírgula.';
      }
      if (key == 'channels' &&
          parts(key, ';').any(
            (p) =>
                p.split(':').length != 2 ||
                p.split(':').any((s) => s.trim().isEmpty),
          )) {
        return 'Use canal:interface|interface;canal:interface.';
      }
      return null;
    },
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.model == null
          ? 'Novo modelo de indicador'
          : 'Editar modelo de indicador',
    ),
    content: SizedBox(
      width: 640,
      height: (MediaQuery.sizeOf(context).height - 240)
          .clamp(140, 600)
          .toDouble(),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsFields(
                children: [
                  field('code', 'Código', required: true),
                  field('manufacturer', 'Fabricante', required: true),
                  field('model', 'Modelo', required: true),
                  field('description', 'Descrição'),
                ],
              ),
              SettingsToggle(
                label: 'Modelo ativo',
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SettingsToggle(
                label: 'Suporta Serial',
                value: _serial,
                onChanged: (v) => setState(() => _serial = v),
              ),
              if (_serial)
                SettingsFields(
                  children: [
                    field(
                      'baud',
                      'Baud rates permitidos (vírgula)',
                      required: true,
                      numbers: true,
                    ),
                    field(
                      'bits',
                      'Data Bits permitidos (vírgula)',
                      required: true,
                      numbers: true,
                    ),
                    field(
                      'parity',
                      'Paridades permitidas (vírgula)',
                      required: true,
                    ),
                    field(
                      'flow',
                      'Flow Control permitido (vírgula)',
                      required: true,
                    ),
                    field(
                      'channels',
                      'Canais e interfaces (COM1:RS-232|RS-485;COM2:RS-232)',
                    ),
                  ],
                ),
              SettingsToggle(
                label: 'Suporta TCP/IP',
                value: _tcp,
                onChanged: (v) => setState(() => _tcp = v),
              ),
              if (_tcp)
                SettingsToggle(
                  label: 'Modelo permite DHCP',
                  value: _dhcp,
                  onChanged: (v) => setState(() => _dhcp = v),
                ),
              field(
                'protocols',
                'Protocolos/saídas (separar por ponto e vírgula)',
              ),
              const SizedBox(height: 16),
              field('notes', 'Observação'),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      ElevatedButton(onPressed: _save, child: const Text('Salvar modelo')),
    ],
  );
}
