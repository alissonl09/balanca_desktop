import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/indicators/indicator_models.dart';
import 'package:balanca_desktop/core/indicators/indicator_driver.dart';
import 'package:balanca_desktop/core/permissions/permission_models.dart';
import 'package:balanca_desktop/features/access_control/access_control_state.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_weighing_policy.dart';
import 'package:balanca_desktop/features/pesagem/weighing_preview.dart';
import 'package:balanca_desktop/features/relatorios/report_catalog.dart';
import 'package:balanca_desktop/features/ticket/ticket_session.dart';

void main() {
  IndicatorModel ind570() => initialIndicatorModels().first;
  test(
    'IND570 suporta TCP e Serial; modelos sem evidência não herdam capacidades',
    () {
      final models = initialIndicatorModels();
      expect(
        ind570().connectionTypes,
        containsAll(IndicatorConnectionType.values),
      );
      for (final model in models.skip(1)) {
        expect(model.connectionTypes, isEmpty);
        expect(model.protocols, isEmpty);
      }
    },
  );
  test('IND570 baud rates documentados', () {
    expect(ind570().serial!.baudRates, [
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
    ]);
  });
  test('IND570 Data Bits 7/8', () => expect(ind570().serial!.dataBits, [7, 8]));
  test(
    'IND570 paridades None/Odd/Even',
    () => expect(ind570().serial!.parities, ['None', 'Odd', 'Even']),
  );
  test(
    'IND570 Flow Control None/XON-XOFF',
    () => expect(ind570().serial!.flowControls, ['None', 'XON/XOFF']),
  );
  test('IND570 interfaces por canal e protocolos de saída', () {
    expect(ind570().serial!.interfacesByChannel['COM1'], [
      'RS-232',
      'RS-422',
      'RS-485',
    ]);
    expect(ind570().serial!.interfacesByChannel['COM2'], ['RS-232']);
    expect(ind570().serial!.interfacesByChannel['COM3'], [
      'RS-232',
      'RS-422',
      'RS-485',
    ]);
    expect(ind570().serial!.interfacesByChannel['COM4'], ['RS-232']);
    expect(ind570().protocols, [
      'MT Continuous / Continuous Output',
      'Continuous Template',
      'Demand Output',
    ]);
  });
  test('catálogo admite modelo Serial distinto e rejeita código duplicado', () {
    final config = IndicatorConfiguration();
    addTearDown(config.dispose);
    final custom = IndicatorModel(
      code: 'LOCAL',
      manufacturer: 'Teste',
      model: 'Serial',
      serial: const SerialCapabilities(
        baudRates: [2400],
        dataBits: [8],
        parities: ['Even'],
        flowControls: ['None'],
      ),
    );
    config.addModel(custom);
    expect(custom.connectionTypes, [IndicatorConnectionType.serial]);
    expect(custom.serial!.baudRates, [2400]);
    expect(() => config.addModel(custom), throwsArgumentError);
  });
  test(
    'troca de modelo limpa parâmetros incompatíveis e não preenche valores',
    () {
      final item = IndicatorInstallation(id: '1')
        ..baudRate = 4800
        ..parity = 'Even'
        ..dataBits = 7
        ..tcpPort = 1701
        ..protocol = 'MT Continuous / Continuous Output';
      item.selectModel(initialIndicatorModels()[1]);
      expect(item.modelCode, 'IND560');
      expect(item.baudRate, isNull);
      expect(item.parity, isNull);
      expect(item.connectionType, isNull);
      expect(item.protocol, isNull);
      expect(item.tcpPort, isNull);
    },
  );
  test(
    'TCP aceita porta física diferente de 1701 e valida faixa e timeout',
    () {
      final item = IndicatorInstallation(id: '1', name: 'Balança')
        ..selectModel(ind570())
        ..connectionType = IndicatorConnectionType.tcp
        ..host = '192.0.2.5'
        ..tcpPort = 1702
        ..protocol = 'MT Continuous / Continuous Output';
      expect(item.validate(ind570()), isEmpty);
      item.tcpPort = 70000;
      item.timeoutMs = 0;
      expect(
        item.validate(ind570()),
        containsAll(['Porta TCP inválida.', 'Timeout deve ser positivo.']),
      );
    },
  );
  test('Serial rejeita parâmetros não permitidos e RS-485 no canal COM2', () {
    final item = IndicatorInstallation(id: '1', name: 'Serial')
      ..selectModel(ind570())
      ..connectionType = IndicatorConnectionType.serial
      ..windowsPort = 'COM9'
      ..channel = 'COM2'
      ..physicalInterface = 'RS-485'
      ..baudRate = 12345
      ..dataBits = 9
      ..parity = 'Space'
      ..flowControl = 'RTS/CTS'
      ..protocol = 'Demand Output';
    expect(
      item.validate(ind570()),
      contains('Revise os parâmetros Serial do modelo.'),
    );
    expect(
      item.validate(ind570()),
      contains('Interface física não permitida nesse canal.'),
    );
    item
      ..baudRate = 4800
      ..dataBits = 7
      ..parity = 'Even'
      ..flowControl = 'None'
      ..physicalInterface = 'RS-232';
    expect(item.validate(ind570()), isEmpty);
  });
  test('leitura normalizada não depende de transporte ou fabricante', () {
    final state = MemoryIndicatorState();
    addTearDown(state.dispose);
    expect(state.reading.connected, isFalse);
    expect(state.reading.weight, isNull);
    state.simulate(
      IndicatorReading(
        weight: 18500,
        stable: true,
        status: IndicatorConnectionStatus.connected,
        readAt: DateTime(2026),
      ),
    );
    expect(state.reading.connected, isTrue);
    expect(state.reading.stable, isTrue);
    expect(state.reading.weight, 18500);
  });
  test('perfis padrão 0–4 e Master/Administrador com todos os recursos', () {
    final p = PermissionState();
    addTearDown(p.dispose);
    expect(p.profiles.map((p) => p.code), [0, 1, 2, 3, 4]);
    for (final grant in AppPermission.values) {
      expect(p.profile(0).allows(grant), isTrue);
      expect(p.profile(1).allows(grant), isTrue);
    }
  });
  test('Supervisor defaults operacionais e Líder sem manual/cancelamento', () {
    final p = PermissionState();
    addTearDown(p.dispose);
    expect(
      p.profile(2).grants,
      containsAll([
        AppPermission.weigh,
        AppPermission.authorizeManual,
        AppPermission.cancelTicket,
        AppPermission.releaseDivergence,
        AppPermission.reprintTicket,
        AppPermission.editOpen,
      ]),
    );
    expect(p.profile(3).grants, {
      AppPermission.weigh,
      AppPermission.releaseDivergence,
      AppPermission.reprintTicket,
    });
    expect(p.profile(3).allows(AppPermission.authorizeManual), isFalse);
    expect(p.profile(3).allows(AppPermission.cancelTicket), isFalse);
  });
  test('Operador tem somente operação e reimpressão inicialmente', () {
    final p = PermissionState();
    addTearDown(p.dispose);
    expect(p.profile(4).grants, {
      AppPermission.weigh,
      AppPermission.reprintTicket,
    });
  });
  test('matriz permite parametrizar defaults e Master permanece total', () {
    final p = PermissionState();
    addTearDown(p.dispose);
    p.setGrant(4, AppPermission.useManual, true);
    expect(p.profile(4).allows(AppPermission.useManual), isTrue);
    p.setGrant(0, AppPermission.weigh, false);
    expect(p.profile(0).allows(AppPermission.weigh), isTrue);
  });
  test(
    'pesquisa mock por nome/matrícula e atribuição de perfil autorizada',
    () {
      final p = PermissionState();
      addTearDown(p.dispose);
      expect(p.search('12345').single.name, 'CARLOS ALMEIDA');
      expect(p.search('carlos').single.registration, '12345');
      p.assign('carlos', 2);
      expect(p.userAllows('carlos', AppPermission.authorizeManual), isTrue);
      p.currentUserId = 'carlos';
      p.assign('alisson', 4);
      expect(p.users.firstWhere((u) => u.id == 'alisson').profileCode, 1);
    },
  );
  for (final enabled in [true, false]) {
    test('Pesagem manual habilitada=$enabled com indicador conectado', () {
      final p = PermissionState();
      addTearDown(p.dispose);
      expect(
        ManualWeighingPolicy.available(
          enabled: enabled,
          reading: const IndicatorReading(
            status: IndicatorConnectionStatus.connected,
          ),
          permissions: p,
        ),
        enabled,
      );
    });
  }
  test('perda de comunicação libera contingência sem contornar perfil', () {
    final p = PermissionState();
    addTearDown(p.dispose);
    expect(
      ManualWeighingPolicy.available(
        enabled: false,
        reading: const IndicatorReading(),
        permissions: p,
      ),
      isTrue,
    );
    p.currentUserId = 'carlos';
    expect(
      ManualWeighingPolicy.available(
        enabled: false,
        reading: const IndicatorReading(),
        permissions: p,
      ),
      isFalse,
    );
  });
  test(
    'justificativa obrigatória e auditoria separada para duas leituras manuais',
    () {
      for (final reason in ['', '  ']) {
        expect(
          () => ManualAuthorization(user: 'balanca', justification: reason),
          throwsArgumentError,
        );
      }
      final session = TicketSession();
      for (final reason in ['Falha inicial', 'Falha na saída']) {
        session.recordManualReading(
          WeighingPreview(
            plate: 'ABC1D23',
            trailer: '',
            operation: {},
            currentWeight: 18500,
            summary: const WeighingSummary(),
            manualOperator: 'balanca',
            manualJustification: reason,
            capturedAt: DateTime(2026, 1, reason == 'Falha inicial' ? 1 : 2),
          ),
        );
      }
      expect(session.manualReadings.map((r) => r.justification), [
        'Falha inicial',
        'Falha na saída',
      ]);
    },
  );
  test('Relatório de Pesagens único e filtros das variações anteriores', () {
    expect(reportCatalog.length, 9);
    final weighing = reportCatalog.where((r) => r.id == 'pesagens').single;
    expect(weighing.title, 'Relatório de Pesagens');
    expect(
      weighing.filters,
      containsAll([
        ReportFilter.startDate,
        ReportFilter.endDate,
        ReportFilter.plate,
        ReportFilter.trailer,
        ReportFilter.driver,
        ReportFilter.carrier,
        ReportFilter.party,
        ReportFilter.product,
        ReportFilter.unit,
        ReportFilter.operation,
        ReportFilter.documentType,
        ReportFilter.status,
        ReportFilter.manual,
        ReportFilter.divergence,
        ReportFilter.operatorName,
      ]),
    );
  });
  test('Relatório de Tickets separado identifica ticket e pesagem independentemente', () {
    final report = reportCatalog.singleWhere((r) => r.id == 'tickets');
    expect(
      report.filters,
      containsAll([
        ReportFilter.ticketNumber,
        ReportFilter.weighingNumber,
        ReportFilter.plate,
        ReportFilter.startDate,
        ReportFilter.endDate,
        ReportFilter.ticketType,
        ReportFilter.document,
        ReportFilter.issuer,
        ReportFilter.status,
      ]),
    );
  });
  test(
    'cancela fechada vermelho, aberta verde, Entrada/Saída independentes',
    () {
      final a = AccessControlState();
      addTearDown(a.dispose);
      expect(a.light(GateSide.entry), TrafficLightState.red);
      a.simulateGate(GateSide.entry, GateState.open);
      expect(a.light(GateSide.entry), TrafficLightState.green);
      expect(a.gate(GateSide.exit), GateState.closed);
      expect(a.light(GateSide.exit), TrafficLightState.red);
      a.simulateGate(GateSide.entry, GateState.error);
      expect(a.light(GateSide.entry), TrafficLightState.red);
    },
  );
  test('display usa texto configurável e rejeita mensagem em branco', () {
    final settings = SettingsState();
    addTearDown(settings.dispose);
    expect(settings.displayMessage, 'COOXUPÉ');
    settings.setDisplayMessage('BALANÇA 01');
    expect(settings.displayMessage, 'BALANÇA 01');
    settings.setDisplayMessage('   ');
    expect(settings.displayMessage, 'COOXUPÉ');
    settings.setDisplayMessage('A' * 60);
    expect(
      settings.displayMessage.length,
      SettingsState.maxDisplayMessageLength,
    );
  });

  test('inversão troca IDs e preserva estados por equipamento', () {
    final settings = SettingsState();
    addTearDown(settings.dispose);
    expect(settings.assignBarrier(GateSide.entry, 'entrada-01'), isTrue);
    expect(settings.assignBarrier(GateSide.exit, 'saida-01'), isTrue);
    settings.accessControl.simulateGate(GateSide.entry, GateState.open);
    expect(settings.swapBarriers(), isFalse);
    expect(settings.entryBarrierId, 'entrada-01');
    settings.barriers = true;
    expect(settings.swapBarriers(), isTrue);
    expect(settings.entryBarrierId, 'saida-01');
    expect(settings.exitBarrierId, 'entrada-01');
    expect(settings.accessControl.gate(GateSide.entry), GateState.closed);
    expect(settings.accessControl.gate(GateSide.exit), GateState.open);
  });
}
