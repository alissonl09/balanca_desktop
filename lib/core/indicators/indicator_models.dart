import 'package:flutter/foundation.dart';

enum IndicatorConnectionType {
  tcp('TCP/IP'),
  serial('Serial RS232');

  const IndicatorConnectionType(this.label);
  final String label;
}

enum IndicatorConnectionStatus { disconnected, connecting, connected, error }

class SerialCapabilities {
  const SerialCapabilities({
    this.baudRates = const [],
    this.dataBits = const [],
    this.parities = const [],
    this.flowControls = const [],
    this.interfacesByChannel = const {},
  });
  final List<int> baudRates, dataBits;
  final List<String> parities, flowControls;

  /// Canais do terminal, não enumeração das portas COM do Windows.
  final Map<String, List<String>> interfacesByChannel;
}

class TcpCapabilities {
  const TcpCapabilities({this.dhcp = false, this.primaryPortReference});
  final bool dhcp;

  /// Referência documental; nunca força a porta da instalação.
  final int? primaryPortReference;
}

class IndicatorModel {
  IndicatorModel({
    required this.code,
    required this.manufacturer,
    required this.model,
    this.description = '',
    this.active = true,
    this.serial,
    this.tcp,
    this.protocols = const [],
    this.notes = '',
  });
  final String code;
  String manufacturer, model, description, notes;
  bool active;
  SerialCapabilities? serial;
  TcpCapabilities? tcp;
  List<String> protocols;
  String get label => '$manufacturer $model';
  List<IndicatorConnectionType> get connectionTypes => [
    if (tcp != null) IndicatorConnectionType.tcp,
    if (serial != null) IndicatorConnectionType.serial,
  ];
}

/// Instalação física em memória. Valores desconhecidos continuam nulos.
class IndicatorInstallation {
  IndicatorInstallation({
    required this.id,
    this.name = '',
    this.modelCode,
    this.active = true,
  });
  final String id;
  String name;
  String? modelCode,
      protocol,
      host,
      mask,
      gateway,
      windowsPort,
      channel,
      physicalInterface,
      parity,
      flowControl;
  bool active, dhcp = false;
  IndicatorConnectionType? connectionType;
  int? tcpPort, baudRate, dataBits;
  int timeoutMs = 1000;

  void selectModel(IndicatorModel model) {
    modelCode = model.code;
    // Uma troca de modelo não herda parâmetros de outro equipamento.
    connectionType = null;
    protocol = null;
    baudRate = null;
    dataBits = null;
    parity = null;
    flowControl = null;
    channel = null;
    physicalInterface = null;
    host = null;
    tcpPort = null;
    mask = null;
    gateway = null;
    dhcp = false;
    windowsPort = null;
  }

  List<String> validate(IndicatorModel model) {
    final errors = <String>[];
    if (name.trim().isEmpty) errors.add('Informe o nome do indicador.');
    if (!model.active) errors.add('O modelo está inativo.');
    if (!model.connectionTypes.contains(connectionType)) {
      errors.add('Selecione uma comunicação suportada pelo modelo.');
    }
    if (!model.protocols.contains(protocol)) {
      errors.add('Selecione um protocolo documentado.');
    }
    if (timeoutMs <= 0) errors.add('Timeout deve ser positivo.');
    if (connectionType == IndicatorConnectionType.tcp) {
      if ((host ?? '').trim().isEmpty && !dhcp) {
        errors.add('Informe IP/Host ou DHCP.');
      }
      if (tcpPort == null || tcpPort! < 1 || tcpPort! > 65535) {
        errors.add('Porta TCP inválida.');
      }
      if (dhcp && model.tcp?.dhcp != true) {
        errors.add('DHCP não suportado pelo modelo.');
      }
    }
    if (connectionType == IndicatorConnectionType.serial) {
      final serial = model.serial;
      if ((windowsPort ?? '').trim().isEmpty) {
        errors.add('Informe a porta COM da estação.');
      }
      if (serial == null ||
          !serial.baudRates.contains(baudRate) ||
          !serial.dataBits.contains(dataBits) ||
          !serial.parities.contains(parity) ||
          !serial.flowControls.contains(flowControl)) {
        errors.add('Revise os parâmetros Serial do modelo.');
      }
      if (serial != null &&
          serial.interfacesByChannel.isNotEmpty &&
          !(serial.interfacesByChannel[channel] ?? []).contains(
            physicalInterface,
          )) {
        errors.add('Interface física não permitida nesse canal.');
      }
    }
    return errors;
  }
}

class IndicatorConfiguration extends ChangeNotifier {
  final models = initialIndicatorModels();
  final installations = <IndicatorInstallation>[];
  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  IndicatorModel? model(String? code) =>
      models.where((m) => m.code == code).firstOrNull;
  void addModel(IndicatorModel value) {
    if (value.code.trim().isEmpty || models.any((m) => m.code == value.code)) {
      throw ArgumentError('Código de modelo vazio ou duplicado.');
    }
    update(() => models.add(value));
  }
}

List<IndicatorModel> initialIndicatorModels() => [
  IndicatorModel(
    code: 'IND570',
    manufacturer: 'Mettler Toledo',
    model: 'IND570',
    description: 'Terminal de pesagem',
    serial: const SerialCapabilities(
      baudRates: [
        300,
        600,
        1200,
        2400,
        4800,
        9600,
        19200,
        38400,
        57600,
        115200,
      ],
      dataBits: [7, 8],
      parities: ['None', 'Odd', 'Even'],
      flowControls: ['None', 'XON/XOFF'],
      interfacesByChannel: {
        'COM1': ['RS-232', 'RS-422', 'RS-485'],
        'COM2': ['RS-232'],
        'COM3': ['RS-232', 'RS-422', 'RS-485'],
        'COM4': ['RS-232'],
      },
    ),
    tcp: const TcpCapabilities(dhcp: true, primaryPortReference: 1701),
    protocols: [
      'MT Continuous / Continuous Output',
      'Continuous Template',
      'Demand Output',
    ],
    notes:
        'COM4 depende da instalação. Stop Bits não parametrizado sem confirmação. '
        '1701 é referência primária; porta secundária pode ser configurada no terminal. '
        'Sempre conferir a configuração física da unidade.',
  ),
  IndicatorModel(
    code: 'IND560',
    manufacturer: 'Mettler Toledo',
    model: 'IND560',
    notes: 'PLC Manual insuficiente. Aguardar Terminal User Guide/manual técnico; capacidades não confirmadas.',
  ),
  IndicatorModel(
    code: 'G10K',
    manufacturer: 'Gênova',
    model: 'G10K',
    notes: 'Capacidades aguardam documentação técnica.',
  ),
  IndicatorModel(
    code: '9700',
    manufacturer: 'Tolflux',
    model: '9700',
    notes: 'Capacidades aguardam documentação técnica.',
  ),
];
