import 'dart:async';

import 'package:balanca_desktop/core/indicators/indicator_driver.dart';
import 'package:balanca_desktop/core/indicators/indicator_models.dart';

// Derivado das tabelas D-3–D-6 (IND560) e A-6–A-9 (IND570).
List<int> toledoFrame({
  int a = 0x2b,
  int b = 0x30,
  int c = 0x20,
  String weight = ' 57009',
  String tare = '     0',
  int? check,
}) => [2, a, b, c, ...weight.codeUnits, ...tare.codeUnits, 13, ?check];

IndicatorInstallation serialInstallation({
  String port = 'COM12',
  int timeout = 2000,
  int retry = 3000,
  bool checksum = false,
}) =>
    IndicatorInstallation(
        id: 'balanca-01',
        name: 'Balança 01',
        modelCode: 'IND570',
      )
      ..connectionType = IndicatorConnectionType.serial
      ..windowsPort = port
      ..baudRate = 4800
      ..dataBits = 7
      ..parity = 'Even'
      ..stopBits = 2
      ..flowControl = 'None'
      ..protocol = toledoContinuousProtocol
      ..checksum = checksum
      ..timeoutMs = timeout
      ..reconnectIntervalMs = retry;

class FakeSerialBus {
  final attempts = <FakeSerialTransport>[];
  final openPorts = <String>{};
  final errors = <String, String>{};
  final events = <String>[];
  Completer<void>? allowOpening;

  IndicatorTransport create() {
    final transport = FakeSerialTransport(this);
    attempts.add(transport);
    return transport;
  }

  FakeSerialTransport get current => attempts.last;
}

class FakeSerialTransport implements IndicatorTransport {
  FakeSerialTransport(this.bus);
  final FakeSerialBus bus;
  final stream = StreamController<List<int>>.broadcast(sync: true);
  IndicatorInstallation? parameters;
  bool _open = false;
  bool released = false;

  @override
  Stream<List<int>> get bytes => stream.stream;

  @override
  Future<void> connect(IndicatorInstallation installation) async {
    parameters = installation;
    await bus.allowOpening?.future;
    final port = installation.comPort;
    bus.events.add('open $port');
    final error = bus.errors[port];
    if (error != null) throw StateError(error);
    if (!bus.openPorts.add(port)) throw StateError('Porta aberta duas vezes.');
    _open = true;
  }

  @override
  Future<void> disconnect() async {
    if (_open) {
      bus.openPorts.remove(parameters!.comPort);
      bus.events.add('close ${parameters!.comPort}');
      _open = false;
    }
    released = true;
    unawaited(stream.close());
  }

  void send(List<int> bytes) => stream.add(bytes);
  void fail(String reason) => stream.addError(StateError(reason));
}
