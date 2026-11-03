import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/indicators/indicator_driver.dart';
import 'package:balanca_desktop/core/indicators/indicator_models.dart';

void main() {
  test('IPv4 e porta TCP são validadas sem default universal', () {
    expect(isValidIpv4('192.168.0.100'), isTrue);
    expect(isValidIpv4('256.168.0.100'), isFalse);
    final model = initialIndicatorModels().first;
    final item = IndicatorInstallation(id: 'x', name: 'Balança')
      ..selectModel(model)
      ..connectionType = IndicatorConnectionType.tcp
      ..host = '192.168.0.100'
      ..tcpPort = 1701
      ..protocol = model.protocols.first;
    expect(item.validate(model), isEmpty);
    item.tcpPort = 65536;
    expect(item.validate(model), contains('Porta TCP inválida.'));
  });

  test(
    'zero válido mantém status conectado; campos serial e TCP são serializados',
    () {
      const zero = IndicatorReading(
        weight: 0,
        status: IndicatorConnectionStatus.connected,
      );
      expect(zero.connected, isTrue);
      expect(zero.weight, 0);
      final original = IndicatorInstallation(id: 'serial', name: 'Balança')
        ..connectionType = IndicatorConnectionType.serial
        ..windowsPort = 'COM1'
        ..baudRate = 4800
        ..dataBits = 7
        ..parity = 'Even'
        ..stopBits = 2
        ..flowControl = 'None'
        ..protocol = 'Custom'
        ..reconnectIntervalMs = 3000;
      final copy = IndicatorInstallation.fromJson(original.toJson());
      expect(copy.toJson(), original.toJson());
      copy.connectionType = IndicatorConnectionType.tcp;
      copy.host = '192.168.1.10';
      copy.tcpPort = 5001;
      expect(IndicatorInstallation.fromJson(copy.toJson()).tcpPort, 5001);
    },
  );
}
