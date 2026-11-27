import 'package:flutter/material.dart';

import 'dart:io';
import 'dart:async';

import '../../core/indicators/indicator_models.dart';
import '../../core/indicators/serial_indicator_service.dart';
import '../../core/indicators/toledo_continuous.dart';
import '../pesagem/weighing_preview.dart' show formatIndicatorWeight;
import 'settings_widgets.dart';

/// Formulários de catálogo e instalação separados, sem transporte ou parser.
class IndicatorSettings extends StatefulWidget {
  const IndicatorSettings({
    super.key,
    required this.configuration,
    required this.models,
    required this.serialIndicator,
    this.loadFailed = false,
  });
  final IndicatorConfiguration configuration;
  final bool models;
  final SerialIndicatorService serialIndicator;
  final bool loadFailed;
  @override
  State<IndicatorSettings> createState() => _IndicatorSettingsState();
}

class _IndicatorSettingsState extends State<IndicatorSettings> {
  String? _selected;
  bool _testing = false;
  String? _testResult;
  List<String> _ports = [];
  String? _portError;
  bool _refreshingPorts = false;
  IndicatorConfiguration get config => widget.configuration;
  void change(VoidCallback callback) => config.update(callback);

  @override
  void initState() {
    super.initState();
    if (!widget.models && config.installations.isNotEmpty) {
      _selected = config.operationalId ?? config.installations.first.id;
      unawaited(_refreshPorts());
    }
  }

  Future<void> _refreshPorts() async {
    if (_refreshingPorts) return;
    setState(() {
      _refreshingPorts = true;
      _portError = null;
    });
    try {
      final ports = await widget.serialIndicator.availablePorts();
      if (mounted) setState(() => _ports = ports);
    } catch (_) {
      if (mounted) {
        setState(() => _portError = 'Não foi possível listar as portas COM.');
      }
    } finally {
      if (mounted) setState(() => _refreshingPorts = false);
    }
  }

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
          description: 'Selecione o modo e salve para aplicar nesta estação.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.loadFailed)
                const Text('Falha ao carregar a configuração dos indicadores.'),
              SettingsFields(
                children: [
                  _choice<IndicatorMode>(
                    'indicator-mode',
                    'Modo de pesagem',
                    config.mode,
                    {for (final mode in IndicatorMode.values) mode: mode.label},
                    (mode) => config.mode = mode,
                  ),
                  _choice<String>(
                    'indicator-operational',
                    'Indicador operacional',
                    config.operationalId,
                    {
                      for (final item in config.installations)
                        item.id:
                            '${item.name.isEmpty ? item.id : item.name}'
                            '${item.active ? '' : ' (inativo)'}',
                    },
                    (id) => config.operationalId = id,
                  ),
                ],
              ),
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
                  onTap: _testing
                      ? null
                      : () => setState(() {
                          _selected = item.id;
                          _testResult = null;
                        }),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('add-indicator'),
                  onPressed: _testing
                      ? null
                      : () {
                          final item = IndicatorInstallation(
                            id: 'local-${config.installations.length + 1}',
                          );
                          change(() {
                            config.installations.add(item);
                            config.operationalId ??= item.id;
                          });
                          setState(() {
                            _selected = item.id;
                            _testResult = null;
                          });
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
                (v) {
                  item.selectConnectionType(v, model!);
                  _testResult = null;
                  if (v == IndicatorConnectionType.serial) {
                    unawaited(_refreshPorts());
                  }
                },
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
                key: ValueKey(item.connectionType),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _choice<String>(
                            'indicator-com',
                            'Porta COM da estação',
                            item.comPort,
                            {
                              for (final port in _ports) port: port,
                              if (item.comPort.isNotEmpty &&
                                  !_ports.contains(item.comPort))
                                item.comPort:
                                    _refreshingPorts || _portError != null
                                    ? item.comPort
                                    : '${item.comPort} (indisponível)',
                            },
                            (port) => item.windowsPort = port,
                          ),
                          TextButton.icon(
                            key: const ValueKey('refresh-indicator-ports'),
                            onPressed: _refreshingPorts ? null : _refreshPorts,
                            icon: const Icon(Icons.refresh),
                            label: Text(
                              _refreshingPorts
                                  ? 'Listando portas…'
                                  : 'Atualizar portas COM',
                            ),
                          ),
                          if (_portError case final message?) Text(message),
                        ],
                      ),
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
                      _choice<int>(
                        'indicator-stop-bits',
                        'Stop Bits',
                        item.stopBits,
                        {for (final v in serial.stopBits) v: '$v'},
                        (v) => item.stopBits = v,
                      ),
                      _choice<String>(
                        'indicator-flow',
                        'Flow Control',
                        item.flowControl,
                        {for (final v in serial.flowControls) v: v},
                        (v) => item.flowControl = v,
                      ),
                    ],
                    if (item.connectionType == IndicatorConnectionType.tcp)
                      ..._protocolFields(item, model),
                  ],
                ),
              ),
              if (item.connectionType == IndicatorConnectionType.serial &&
                  serial != null)
                _advancedSerial(item, model!, serial),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Diagnóstico do indicador',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                _testResult ?? 'O teste recebe dados do indicador. Feche o ComTool ou a Portaria se estiverem usando a COM.',
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

  List<Widget> _protocolFields(
    IndicatorInstallation item,
    IndicatorModel? model,
  ) => [
    _number(
      'indicator-timeout',
      'Timeout (ms)',
      item.timeoutMs,
      (v) => item.timeoutMs = v ?? 0,
    ),
    _number(
      'indicator-reconnect',
      'Intervalo de reconexão (ms)',
      item.reconnectIntervalMs,
      (v) => item.reconnectIntervalMs = v ?? 0,
    ),
    _choice<String>(
      'indicator-protocol',
      'Protocolo / Tipo de saída',
      item.protocol,
      {for (final p in model?.protocols ?? <String>[]) p: p},
      (v) => item.protocol = v,
    ),
  ];

  Widget _advancedSerial(
    IndicatorInstallation item,
    IndicatorModel model,
    SerialCapabilities serial,
  ) => ExpansionTile(
    key: const ValueKey('indicator-serial-advanced'),
    title: const Text('Configuração serial avançada'),
    tilePadding: EdgeInsets.zero,
    children: [
      SettingsFields(
        children: [
          ..._protocolFields(item, model),
          if (serial.interfacesByChannel.isNotEmpty) ...[
            _choice<String>(
              'indicator-channel',
              'Canal do indicador',
              item.channel,
              {for (final c in serial.interfacesByChannel.keys) c: c},
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
                    in serial.interfacesByChannel[item.channel] ?? <String>[])
                  i: i,
              },
              (v) => item.physicalInterface = v,
            ),
          ],
          if (item.protocol == toledoContinuousProtocol) ...[
            _choice<ToledoWeightScale>(
              'indicator-toledo-weight-scale',
              'Escala do peso',
              item.toledoWeightScale,
              {
                for (final scale in ToledoWeightScale.values)
                  scale: scale.label,
              },
              (scale) {
                item.toledoWeightScale = scale;
                if (scale == ToledoWeightScale.comToolIntegerKg) {
                  item.checksum = true;
                }
              },
            ),
            if (item.toledoWeightScale == ToledoWeightScale.standard)
              SettingsToggle(
                label: 'Checksum do MT Continuous',
                value: item.checksum,
                onChanged: (value) => change(() => item.checksum = value),
              ),
          ],
        ],
      ),
    ],
  );

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
        final protocolError = item.serialProtocolError;
        if (protocolError != null) {
          result = protocolError;
        } else {
          final parameters =
              '${item.comPort} · ${item.baudRate} baud · '
              '${item.dataBits} bits · paridade ${item.parity} · '
              '${item.stopBits} stop bits · fluxo ${item.flowControl}\n'
              '${item.protocol} · checksum ${item.checksum ? 'ativo' : 'inativo'} · '
              '${item.toledoWeightScale.label} · '
              'timeout ${item.timeoutMs} ms · reconexão ${item.reconnectIntervalMs} ms';
          final data = await widget.serialIndicator.testConnection(item);
          result = data == null
              ? '$parameters\nTeste cancelado ou já em andamento.'
              : _serialResult(parameters, data);
        }
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

  String _serialResult(String parameters, SerialDiagnostics data) {
    final reading = data.reading;
    return [
      parameters,
      '${reading.status.label} · porta ${data.portOpen ? 'aberta' : 'fechada'}',
      ?reading.error,
      'Bytes recebidos: ${data.bytesReceived} · Frames válidos: ${data.validFrames} · '
          'Inválidos: ${data.invalidFrames}',
      'Último frame válido: ${data.lastValidAt?.toLocal().toIso8601String() ?? '—'}',
      if (data.lastValidReading case final valid?)
        'Último peso válido: ${formatIndicatorWeight(valid.weight!, valid.decimalPlaces!)} ${valid.unit} · '
            '${valid.gross! ? 'bruto' : 'líquido'} · ${valid.stable! ? 'estável' : 'instável'}',
      if (data.lastInvalid case final error?) 'Último frame rejeitado: $error',
      'Diagnóstico: ${data.observedAt.toLocal().toIso8601String()}',
      if (data.sample.isNotEmpty) ...[
        'HEX: ${data.hex}',
        'ASCII: ${data.ascii}',
      ],
    ].join('\n');
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
