import 'package:flutter/foundation.dart';

import 'toledo_continuous.dart';

enum IndicatorConnectionType {
  tcp('TCP/IP'),
  serial('Serial RS232');

  const IndicatorConnectionType(this.label);
  final String label;
}

enum IndicatorConnectionStatus {
  disabled('Desativado'),
  disconnected('Indicador desconectado'),
  connecting('Conectando'),
  awaitingData('Aguardando dados'),
  connected('Comunicando'),
  noCommunication('Sem comunicação'),
  error('Erro');

  const IndicatorConnectionStatus(this.label);
  final String label;
}

enum IndicatorMode {
  simulated('Simulado'),
  real('Real');

  const IndicatorMode(this.label);
  final String label;
}

const toledoContinuousProtocol = 'MT Continuous / Continuous Output';
const toledoSerialModels = {'IND560', 'IND570'};

class SerialCapabilities {
  const SerialCapabilities({
    this.baudRates = const [],
    this.dataBits = const [],
    this.parities = const [],
    this.flowControls = const [],
    this.stopBits = const [],
    this.interfacesByChannel = const {},
  });
  final List<int> baudRates, dataBits;
  final List<String> parities, flowControls;
  final List<int> stopBits;

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

  Map<String, Object?> toJson() => {
    'code': code,
    'manufacturer': manufacturer,
    'model': model,
    'description': description,
    'active': active,
    'notes': notes,
    'protocols': protocols,
    if (serial case final value?)
      'serial': {
        'baudRates': value.baudRates,
        'dataBits': value.dataBits,
        'parities': value.parities,
        'flowControls': value.flowControls,
        'stopBits': value.stopBits,
        'interfacesByChannel': value.interfacesByChannel,
      },
    if (tcp case final value?)
      'tcp': {
        'dhcp': value.dhcp,
        'primaryPortReference': value.primaryPortReference,
      },
  };

  factory IndicatorModel.fromJson(Map<String, dynamic> json) {
    final serial = json['serial'] as Map<String, dynamic>?;
    final tcp = json['tcp'] as Map<String, dynamic>?;
    return IndicatorModel(
      code: json['code'] as String,
      manufacturer: json['manufacturer'] as String,
      model: json['model'] as String,
      description: json['description'] as String,
      active: json['active'] as bool,
      notes: json['notes'] as String,
      protocols: List<String>.from(json['protocols'] as List),
      serial: serial == null
          ? null
          : SerialCapabilities(
              baudRates: List<int>.from(serial['baudRates'] as List),
              dataBits: List<int>.from(serial['dataBits'] as List),
              parities: List<String>.from(serial['parities'] as List),
              flowControls: List<String>.from(serial['flowControls'] as List),
              stopBits: List<int>.from(serial['stopBits'] as List),
              interfacesByChannel:
                  (serial['interfacesByChannel'] as Map<String, dynamic>).map(
                    (key, value) =>
                        MapEntry(key, List<String>.from(value as List)),
                  ),
            ),
      tcp: tcp == null
          ? null
          : TcpCapabilities(
              dhcp: tcp['dhcp'] as bool,
              primaryPortReference: tcp['primaryPortReference'] as int?,
            ),
    );
  }
}

/// Parâmetros da instalação física. Valores desconhecidos continuam nulos.
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
  bool active, dhcp = false, checksum = false;
  ToledoWeightScale toledoWeightScale = ToledoWeightScale.standard;
  IndicatorConnectionType? connectionType;
  int? tcpPort, baudRate, dataBits;
  int? stopBits;
  int timeoutMs = 2000, reconnectIntervalMs = 3000;

  String get comPort => (windowsPort ?? '').trim().toUpperCase();

  /// A identidade da conexão exclui os campos apenas descritivos.
  Object get serialParameters => (
    modelCode,
    protocol,
    comPort,
    baudRate,
    dataBits,
    parity,
    stopBits,
    flowControl,
    checksum,
    toledoWeightScale,
    timeoutMs,
    reconnectIntervalMs,
  );

  String? get serialProtocolError =>
      toledoSerialModels.contains(modelCode) &&
          protocol == toledoContinuousProtocol
      ? null
      : 'A leitura serial requer IND560 ou IND570 com saída MT Continuous padrão.';

  void selectModel(IndicatorModel model) {
    if (modelCode == model.code) return;
    modelCode = model.code;
    // Uma troca de modelo não herda parâmetros de outro equipamento.
    connectionType = null;
    protocol = null;
    baudRate = null;
    dataBits = null;
    parity = null;
    flowControl = null;
    stopBits = null;
    channel = null;
    physicalInterface = null;
    host = null;
    tcpPort = null;
    mask = null;
    gateway = null;
    dhcp = false;
    checksum = false;
    toledoWeightScale = ToledoWeightScale.standard;
    windowsPort = null;
    if (toledoSerialModels.contains(model.code) && model.serial != null) {
      final serial = model.serial!;
      baudRate = serial.baudRates.contains(4800) ? 4800 : null;
      dataBits = serial.dataBits.contains(7) ? 7 : null;
      parity = serial.parities.contains('Even') ? 'Even' : null;
      stopBits = serial.stopBits.contains(2) ? 2 : null;
      flowControl = serial.flowControls.contains('None') ? 'None' : null;
      checksum = true;
    }
  }

  void selectConnectionType(
    IndicatorConnectionType type,
    IndicatorModel model,
  ) {
    connectionType = type;
    if (type == IndicatorConnectionType.serial &&
        toledoSerialModels.contains(model.code) &&
        model.protocols.contains(toledoContinuousProtocol)) {
      protocol ??= toledoContinuousProtocol;
    }
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
    if (reconnectIntervalMs <= 0) {
      errors.add('Intervalo de reconexão deve ser positivo.');
    }
    if (connectionType == IndicatorConnectionType.tcp) {
      if (!isValidIpv4(host ?? '')) {
        errors.add('Informe um endereço IPv4 válido.');
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
      if (toledoWeightScale == ToledoWeightScale.comToolIntegerKg &&
          protocol == toledoContinuousProtocol &&
          !checksum) {
        errors.add('O perfil ComTool requer checksum ativo.');
      }
      if (reconnectIntervalMs > 0 && reconnectIntervalMs < 250) {
        errors.add('Reconexão serial requer pelo menos 250 ms.');
      }
      if (!RegExp(r'^COM[1-9][0-9]*$').hasMatch(comPort)) {
        errors.add('Informe a porta COM da estação.');
      }
      if (serial == null ||
          !serial.baudRates.contains(baudRate) ||
          !serial.dataBits.contains(dataBits) ||
          !serial.parities.contains(parity) ||
          !serial.flowControls.contains(flowControl) ||
          !serial.stopBits.contains(stopBits)) {
        errors.add('Revise os parâmetros Serial do modelo.');
      }
      if ((channel != null || physicalInterface != null) &&
          serial != null &&
          serial.interfacesByChannel.isNotEmpty &&
          !(serial.interfacesByChannel[channel] ?? []).contains(
            physicalInterface,
          )) {
        errors.add('Interface física não permitida nesse canal.');
      }
    }
    return errors;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'modelCode': modelCode,
    'active': active,
    'connectionType': connectionType?.name,
    'protocol': protocol,
    'host': host,
    'mask': mask,
    'gateway': gateway,
    'dhcp': dhcp,
    'tcpPort': tcpPort,
    'timeoutMs': timeoutMs,
    'reconnectIntervalMs': reconnectIntervalMs,
    'windowsPort': windowsPort,
    'baudRate': baudRate,
    'dataBits': dataBits,
    'parity': parity,
    'stopBits': stopBits,
    'flowControl': flowControl,
    'checksum': checksum,
    'toledoWeightScale': toledoWeightScale.name,
    'channel': channel,
    'physicalInterface': physicalInterface,
  };

  static IndicatorInstallation fromJson(Map<String, Object?> json) {
    final item = IndicatorInstallation(
      id: json['id']! as String,
      name: json['name'] as String? ?? '',
      modelCode: json['modelCode'] as String?,
      active: json['active'] as bool? ?? true,
    );
    item.connectionType = IndicatorConnectionType.values
        .where((e) => e.name == json['connectionType'])
        .firstOrNull;
    item.protocol = json['protocol'] as String?;
    item.host = json['host'] as String?;
    item.mask = json['mask'] as String?;
    item.gateway = json['gateway'] as String?;
    item.dhcp = json['dhcp'] as bool? ?? false;
    item.tcpPort = json['tcpPort'] as int?;
    item.timeoutMs = json['timeoutMs'] as int? ?? 2000;
    item.reconnectIntervalMs = json['reconnectIntervalMs'] as int? ?? 3000;
    item.windowsPort = json['windowsPort'] as String?;
    item.baudRate = json['baudRate'] as int?;
    item.dataBits = json['dataBits'] as int?;
    item.parity = json['parity'] as String?;
    item.stopBits = json['stopBits'] as int?;
    item.flowControl = json['flowControl'] as String?;
    item.checksum = json['checksum'] as bool? ?? false;
    if (json['toledoWeightScale'] case final String scale) {
      item.toledoWeightScale = ToledoWeightScale.values.byName(scale);
    }
    item.channel = json['channel'] as String?;
    item.physicalInterface = json['physicalInterface'] as String?;
    return item;
  }
}

bool isValidIpv4(String value) {
  final parts = value.trim().split('.');
  return parts.length == 4 &&
      parts.every((part) {
        final n = int.tryParse(part);
        return n != null && n >= 0 && n <= 255 && part == n.toString();
      });
}

class IndicatorConfiguration extends ChangeNotifier {
  final models = initialIndicatorModels();
  final installations = <IndicatorInstallation>[];
  IndicatorMode mode = IndicatorMode.simulated;
  String? operationalId;
  IndicatorInstallation? get operational =>
      installations.where((item) => item.id == operationalId).firstOrNull;

  void restoreStation(Map<String, dynamic>? json) {
    final modeName = json?['mode'];
    final savedMode = IndicatorMode.values
        .where((mode) => mode.name == modeName)
        .firstOrNull;
    if (modeName != null && savedMode == null) {
      throw const FormatException('Modo de pesagem da estação inválido.');
    }
    final rows = (json?['installations'] as List?) ?? [];
    final loaded = rows
        .map(
          (row) => IndicatorInstallation.fromJson(row as Map<String, dynamic>),
        )
        .toList();
    update(() {
      mode = savedMode ?? IndicatorMode.simulated;
      operationalId = json?['operationalId'] as String?;
      installations
        ..clear()
        ..addAll(loaded);
    });
  }

  Map<String, dynamic> stationJson() => {
    'mode': mode.name,
    'operationalId': operationalId,
    'installations': [for (final item in installations) item.toJson()],
  };
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
      stopBits: [1, 2],
      interfacesByChannel: {
        'COM1': ['RS-232', 'RS-422', 'RS-485'],
        'COM2': ['RS-232'],
        'COM3': ['RS-232', 'RS-422', 'RS-485'],
        'COM4': ['RS-232'],
      },
    ),
    tcp: const TcpCapabilities(dhcp: true, primaryPortReference: 1701),
    protocols: [
      toledoContinuousProtocol,
      'Continuous Template',
      'Demand Output',
    ],
    notes:
        'COM4 depende da instalação. Stop Bits devem seguir a configuração local. '
        '1701 é referência primária; porta secundária pode ser configurada no terminal. '
        'Sempre conferir a configuração física da unidade.',
  ),
  IndicatorModel(
    code: 'IND560',
    manufacturer: 'Mettler Toledo',
    model: 'IND560',
    notes: 'COM2/COM3 dependem da placa opcional. Confira o canal e a interface física do terminal.',
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
      stopBits: [1, 2],
      interfacesByChannel: {
        'COM1': ['RS-232', 'RS-422', 'RS-485'],
        'COM2': ['RS-232'],
        'COM3': ['RS-232', 'RS-422', 'RS-485'],
      },
    ),
    protocols: [
      toledoContinuousProtocol,
      'Continuous Template',
      'Demand Output',
    ],
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
