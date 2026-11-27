import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/indicators/indicator_driver.dart';
import 'package:balanca_desktop/core/indicators/indicator_models.dart';
import 'package:balanca_desktop/core/indicators/indicator_settings_store.dart';
import 'package:balanca_desktop/core/indicators/toledo_continuous.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';

import 'support/serial_indicator_fake.dart';

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

  test('configuração legada conserva escala, checksum e parâmetros dos dois transportes', () {
    final model = initialIndicatorModels().first;
    final saved = serialInstallation(port: 'COM37', timeout: 3500, retry: 4500)
      ..baudRate = 9600
      ..stopBits = 1
      ..channel = 'COM2'
      ..physicalInterface = 'RS-232'
      ..host = '192.168.1.10'
      ..tcpPort = 5001;
    final oldJson = saved.toJson()..remove('toledoWeightScale');
    final restored = IndicatorInstallation.fromJson(oldJson);
    expect(restored.toledoWeightScale, ToledoWeightScale.standard);
    restored.selectModel(model);
    restored.selectConnectionType(IndicatorConnectionType.tcp, model);
    restored.selectConnectionType(IndicatorConnectionType.serial, model);
    expect(restored.toJson(), saved.toJson());
  });

  test(
    'persiste instalações por estação, modo, checksum, COM ausente e catálogo',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'indicadores_teste_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = LocalIndicatorSettingsStore(
        directory: () async => directory,
      );
      final bus = FakeSerialBus();
      final settings = SettingsState(
        indicatorStore: store,
        serialTransportFactory: bus.create,
      );
      addTearDown(settings.dispose);
      settings.update(() => settings.unitCode = 19);
      final item = serialInstallation(port: 'COM37', checksum: true)
        ..active = false
        ..toledoWeightScale = ToledoWeightScale.comToolIntegerKg;
      settings.indicators.update(() {
        settings.indicators.mode = IndicatorMode.real;
        settings.indicators.installations.add(item);
        settings.indicators.operationalId = item.id;
      });
      await settings.saveIndicatorSettings(catalog: false);
      expect(
        settings.indicatorState.reading.status,
        IndicatorConnectionStatus.disabled,
      );
      settings.indicators.addModel(
        IndicatorModel(
          code: 'LOCAL',
          manufacturer: 'Local',
          model: 'TCP',
          tcp: const TcpCapabilities(dhcp: true),
        ),
      );
      await settings.saveIndicatorSettings(catalog: true);
      settings.update(() => settings.unitCode = 20);
      expect(settings.indicators.mode, IndicatorMode.simulated);
      expect(settings.indicators.installations, isEmpty);
      final second = serialInstallation(port: 'COM18')..active = false;
      settings.indicators.update(
        () => settings.indicators.installations.add(second),
      );
      await settings.saveIndicatorSettings(catalog: false);
      settings.update(() => settings.unitCode = 19);
      expect(settings.indicators.operational!.checksum, isTrue);
      expect(settings.indicators.operational!.windowsPort, 'COM37');

      final loaded = await store.load();
      final restored = SettingsState(
        indicatorSettings: loaded,
        serialTransportFactory: bus.create,
      );
      addTearDown(restored.dispose);
      expect(restored.unitCode, 20);
      expect(restored.indicators.installations.single.windowsPort, 'COM18');
      expect(restored.indicators.model('LOCAL')?.tcp?.dhcp, isTrue);
      restored.update(() => restored.unitCode = 19);
      expect(restored.serialIndicator.realMode, isTrue);
      expect(restored.indicators.operational!.toJson(), item.toJson());
      expect(bus.attempts, isEmpty);
    },
  );
}
