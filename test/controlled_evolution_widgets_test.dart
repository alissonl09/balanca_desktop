import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/core/widgets/visual_components.dart';
import 'package:balanca_desktop/core/indicators/indicator_models.dart';
import 'package:balanca_desktop/core/indicators/indicator_driver.dart';
import 'package:balanca_desktop/core/permissions/permission_models.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';
import 'package:balanca_desktop/features/configuracoes/configuracoes_page.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_page.dart';
import 'package:balanca_desktop/features/pesagem/weighing_preview.dart';
import 'package:balanca_desktop/features/access_control/access_control_state.dart';
import 'package:balanca_desktop/features/access_control/access_control_panel.dart';
import 'package:balanca_desktop/features/ticket/ticket_session.dart';

Finder keyed(String key) => find.byKey(ValueKey(key));
Iterable<T?> options<T>(WidgetTester tester, String key) => tester
    .widget<DropdownButton<T>>(
      find.descendant(of: keyed(key), matching: find.byType(DropdownButton<T>)),
    )
    .items!
    .map((i) => i.value);
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> select(WidgetTester tester, String key, String label) async {
  await tap(tester, keyed(key));
  await tester.ensureVisible(find.text(label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester,
  SettingsState settings, {
  bool configuration = false,
  Size size = const Size(1366, 900),
  TicketSession? session,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: TickerMode(
          enabled: configuration || !settings.informationDisplay,
          child: configuration
              ? SingleChildScrollView(
                  child: ConfiguracoesPage(
                    compact: true,
                    settings: settings,
                    ticketSession: session ?? TicketSession(),
                  ),
                )
              : PesagemPage(settings: settings, ticketSession: session),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void windowsTest(String name, WidgetTesterCallback callback) => testWidgets(
  name,
  callback,
  variant: TargetPlatformVariant.only(TargetPlatform.windows),
);

void main() {
  setUpAll(() async {
    if (Platform.isWindows) {
      final loader = FontLoader('Arial');
      for (final file in ['arial.ttf', 'arialbd.ttf']) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/$file',
              ).readAsBytesSync(),
            ),
          ),
        );
      }
      await loader.load();
    }
  });
  windowsTest(
    'instalação IND570 seleciona TCP ou Serial e mostra parâmetros do modelo',
    (tester) async {
      final settings = SettingsState();
      addTearDown(settings.dispose);
      await mount(tester, settings, configuration: true);
      await tap(tester, keyed('settings-tab-indicators'));
      await tap(tester, keyed('add-indicator'));
      await select(tester, 'indicator-model', 'Mettler Toledo IND570');
      expect(
        options<IndicatorConnectionType>(tester, 'indicator-connection'),
        containsAll(IndicatorConnectionType.values),
      );
      await select(tester, 'indicator-connection', 'TCP/IP');
      expect(keyed('indicator-host'), findsOneWidget);
      expect(keyed('indicator-mask'), findsOneWidget);
      expect(keyed('indicator-gateway'), findsOneWidget);
      expect(keyed('indicator-protocol'), findsOneWidget);
      expect(settings.indicators.installations.single.tcpPort, isNull);
      await tester.enterText(keyed('indicator-name'), 'Balança de teste');
      await tester.enterText(keyed('indicator-host'), '192.0.2.5');
      await tester.enterText(keyed('indicator-tcp-port'), '1702');
      await select(
        tester,
        'indicator-protocol',
        'MT Continuous / Continuous Output',
      );
      await tap(tester, keyed('save-settings'));
      expect(
        find.textContaining('Configurações mantidas somente nesta sessão.'),
        findsOneWidget,
      );
      expect(settings.indicators.installations.single.tcpPort, 1702);
      await select(tester, 'indicator-connection', 'Serial RS232');
      expect(keyed('indicator-host'), findsNothing);
      expect(keyed('indicator-com'), findsOneWidget);
      expect(options<int>(tester, 'indicator-baud'), [
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
      expect(options<int>(tester, 'indicator-data-bits'), [7, 8]);
      expect(options<String>(tester, 'indicator-parity'), [
        'None',
        'Odd',
        'Even',
      ]);
      expect(options<String>(tester, 'indicator-flow'), ['None', 'XON/XOFF']);
      await select(tester, 'indicator-channel', 'COM2');
      expect(options<String>(tester, 'indicator-interface-COM2'), ['RS-232']);
      expect(find.text('Stop Bits'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Testar comunicação'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  windowsTest(
    'troca de modelo altera opções e IND560 não recebe regras do IND570',
    (tester) async {
      final settings = SettingsState();
      addTearDown(settings.dispose);
      settings.indicators.addModel(
        IndicatorModel(
          code: 'SERIAL',
          manufacturer: 'Teste',
          model: 'Somente Serial',
          serial: const SerialCapabilities(
            baudRates: [2400],
            dataBits: [8],
            parities: ['Even'],
            flowControls: ['None'],
          ),
          protocols: ['Saída específica'],
        ),
      );
      await mount(tester, settings, configuration: true);
      await tap(tester, keyed('settings-tab-indicators'));
      await tap(tester, keyed('add-indicator'));
      await select(tester, 'indicator-model', 'Teste Somente Serial');
      expect(options<IndicatorConnectionType>(tester, 'indicator-connection'), [
        IndicatorConnectionType.serial,
      ]);
      await select(tester, 'indicator-connection', 'Serial RS232');
      expect(options<int>(tester, 'indicator-baud'), [2400]);
      expect(options<String>(tester, 'indicator-protocol'), [
        'Saída específica',
      ]);
      await select(tester, 'indicator-model', 'Mettler Toledo IND560');
      expect(
        tester
            .widget<DropdownButtonFormField<IndicatorConnectionType>>(
              keyed('indicator-connection'),
            )
            .onChanged,
        isNull,
      );
      expect(keyed('indicator-baud'), findsNothing);
      expect(keyed('indicator-host'), findsNothing);
      expect(
        find.textContaining('Capacidades não confirmadas.'),
        findsOneWidget,
      );
    },
  );

  windowsTest(
    'cadastro de novo modelo e edição preservam catálogo de instalações',
    (tester) async {
      final settings = SettingsState();
      addTearDown(settings.dispose);
      await mount(tester, settings, configuration: true);
      await tap(tester, keyed('settings-tab-models'));
      await tap(tester, keyed('add-indicator-model'));
      for (final entry in {
        'code': 'NOVO',
        'manufacturer': 'Fabricante local',
        'model': 'Modelo futuro',
        'description': 'Descrição',
        'notes': 'Aguardando manual',
      }.entries) {
        await tester.enterText(keyed('model-${entry.key}'), entry.value);
      }
      await tap(tester, find.text('Salvar modelo'));
      expect(settings.indicators.model('NOVO')!.notes, 'Aguardando manual');
      expect(settings.indicators.model('NOVO')!.connectionTypes, isEmpty);
      await tap(tester, keyed('edit-model-NOVO'));
      await tester.enterText(keyed('model-description'), 'Descrição revisada');
      await tap(tester, find.text('Salvar modelo'));
      expect(
        settings.indicators.model('NOVO')!.description,
        'Descrição revisada',
      );
      expect(settings.indicators.installations, isEmpty);
    },
  );

  windowsTest(
    'Configurações Gerais altera Pesagem manual e define cancelas por equipamento',
    (tester) async {
      final settings = SettingsState()
        ..integratedSgv = true
        ..barriers = true;
      addTearDown(settings.dispose);
      await mount(tester, settings, configuration: true);
      await tap(tester, keyed('manual-weighing-enabled'));
      expect(settings.manualWeighingEnabled, isFalse);
      await tap(tester, keyed('settings-tab-vehicles'));
      expect(find.text('Inverter posição Entrada/Saída'), findsNothing);
      await select(tester, 'entry-barrier', 'Cancela Entrada 01 (simulada)');
      await select(tester, 'exit-barrier', 'Cancela Saída 01 (simulada)');
      expect(settings.entryBarrierId, 'entrada-01');
      expect(settings.exitBarrierId, 'saida-01');
      expect(settings.accessControl.gate(GateSide.entry), GateState.closed);
    },
  );

  windowsTest('perfis possuem matriz e usuário mock recebe perfil por LOV', (
    tester,
  ) async {
    final settings = SettingsState();
    addTearDown(settings.dispose);
    await mount(tester, settings, configuration: true);
    await tap(tester, keyed('settings-tab-permissions'));
    await select(tester, 'permission-profile', '4 — Operador');
    expect(
      tester.widget<CheckboxListTile>(keyed('grant-authorizeManual')).value,
      isFalse,
    );
    await tap(tester, keyed('grant-useManual'));
    expect(
      settings.permissions.profile(4).allows(AppPermission.useManual),
      isTrue,
    );
    await tester.enterText(keyed('permission-user-search'), '12345');
    await tap(tester, keyed('directory-user-carlos'));
    expect(find.textContaining('Nome: CARLOS ALMEIDA'), findsOneWidget);
    await select(tester, 'user-profile-carlos-4', '2 — Supervisor de Balança');
    expect(
      settings.permissions.userAllows('carlos', AppPermission.authorizeManual),
      isTrue,
    );
  });

  windowsTest('mesma cancela não pode ocupar Entrada e Saída', (tester) async {
    final settings = SettingsState()
      ..integratedSgv = true
      ..barriers = true;
    addTearDown(settings.dispose);
    await mount(tester, settings, configuration: true);
    await tap(tester, keyed('settings-tab-vehicles'));
    await select(tester, 'entry-barrier', 'Cancela Entrada 01 (simulada)');
    final exit = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: keyed('exit-barrier'),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(
      exit.items!.singleWhere((item) => item.value == 'entrada-01').enabled,
      isFalse,
    );
    expect(settings.assignBarrier(GateSide.exit, 'entrada-01'), isFalse);
    expect(settings.exitBarrierId, isNull);
    await select(tester, 'exit-barrier', 'Cancela Saída 01 (simulada)');
    expect(settings.gateAssignmentsValid, isTrue);
  });

  windowsTest('inversão fica desabilitada sem Cancelas', (tester) async {
    final settings = SettingsState()..integratedSgv = true;
    addTearDown(settings.dispose);
    await mount(tester, settings, configuration: true);
    await tap(tester, keyed('settings-tab-vehicles'));
    final reverse = keyed('reverse-gate-sides');
    expect(tester.widget<IconButton>(reverse).onPressed, isNull);
    expect(settings.swapBarriers(), isFalse);
    await tap(tester, keyed('barriers-enabled'));
    expect(tester.widget<IconButton>(reverse).onPressed, isNotNull);
  });

  windowsTest('ícone troca equipamentos sem mover os conjuntos visuais', (
    tester,
  ) async {
    final settings = SettingsState()
      ..integratedSgv = true
      ..barriers = true
      ..trafficLight = true;
    addTearDown(settings.dispose);
    expect(settings.assignBarrier(GateSide.entry, 'entrada-01'), isTrue);
    expect(settings.assignBarrier(GateSide.exit, 'saida-01'), isTrue);
    settings.accessControl.simulateGate(GateSide.entry, GateState.open);
    await mount(tester, settings, configuration: true);
    await tap(tester, keyed('settings-tab-vehicles'));
    final reverse = keyed('reverse-gate-sides');
    expect(reverse, findsOneWidget);
    expect(
      tester.widget<IconButton>(reverse).tooltip,
      'Inverter posição de Entrada e Saída',
    );
    expect(find.text('Inverter posição Entrada/Saída'), findsNothing);
    await tap(tester, reverse);
    expect(settings.entryBarrierId, 'saida-01');
    expect(settings.exitBarrierId, 'entrada-01');
    final entrySelection = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: keyed('entry-barrier'),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    final exitSelection = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: keyed('exit-barrier'),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(entrySelection.value, 'saida-01');
    expect(exitSelection.value, 'entrada-01');

    await mount(tester, settings);
    expect(
      tester.getTopLeft(keyed('lane-entry')).dx,
      lessThan(tester.getTopLeft(keyed('lane-exit')).dx),
    );
    expect(find.text('Cancela Saída 01'), findsOneWidget);
    expect(find.text('Cancela Entrada 01'), findsOneWidget);
    final entryLight = tester.getRect(keyed('traffic-light-entry'));
    final entryGate = tester.getRect(keyed('gate-entry'));
    final exitLight = tester.getRect(keyed('traffic-light-exit'));
    final exitGate = tester.getRect(keyed('gate-exit'));
    expect(entryLight.right, lessThanOrEqualTo(entryGate.left));
    expect(exitLight.left, greaterThanOrEqualTo(exitGate.right));
    expect((entryGate.left - entryLight.right).abs(), lessThanOrEqualTo(5));
    expect((exitLight.left - exitGate.right).abs(), lessThanOrEqualTo(5));
    final exitMirror = tester.widget<Transform>(
      find.descendant(of: keyed('gate-exit'), matching: find.byType(Transform)),
    );
    expect(exitMirror.transform.entry(0, 0), -1);
    expect(settings.accessControl.gate(GateSide.entry), GateState.closed);
    expect(settings.accessControl.gate(GateSide.exit), GateState.open);
    expect(find.textContaining('Entrada · FECHADA'), findsOneWidget);
    expect(find.textContaining('Saída · ABERTA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  windowsTest(
    'Pesagem mostra IDs selecionados e simula cada equipamento sem trocar papéis',
    (tester) async {
      final settings = SettingsState()
        ..integratedSgv = true
        ..barriers = true
        ..trafficLight = true;
      addTearDown(settings.dispose);
      expect(settings.assignBarrier(GateSide.entry, 'apoio-01'), isTrue);
      expect(settings.assignBarrier(GateSide.exit, 'balanca-01'), isTrue);
      await mount(tester, settings);
      expect(find.text('Cancela Pátio'), findsOneWidget);
      expect(find.text('Cancela Balança'), findsOneWidget);
      expect(settings.accessControl.equipmentId(GateSide.entry), 'apoio-01');
      expect(settings.accessControl.equipmentId(GateSide.exit), 'balanca-01');
      final entryTransform = tester.widget<Transform>(
        find
            .descendant(
              of: keyed('gate-entry'),
              matching: find.byType(Transform),
            )
            .first,
      );
      final exitTransform = tester.widget<Transform>(
        find
            .descendant(
              of: keyed('gate-exit'),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(entryTransform.transform.entry(0, 0), 1);
      expect(exitTransform.transform.entry(0, 0), -1);
      await tap(tester, keyed('access-simulation'));
      await tap(tester, keyed('simulate-entry-open'));
      expect(
        settings.accessControl.gateForEquipment('apoio-01'),
        GateState.open,
      );
      expect(
        settings.accessControl.gateForEquipment('balanca-01'),
        GateState.closed,
      );
      expect(
        settings.accessControl.light(GateSide.entry),
        TrafficLightState.green,
      );
      expect(
        settings.accessControl.light(GateSide.exit),
        TrafficLightState.red,
      );
      await tap(tester, keyed('simulate-exit-open'));
      await tap(tester, keyed('simulate-entry-closed'));
      expect(
        settings.accessControl.gateForEquipment('apoio-01'),
        GateState.closed,
      );
      expect(
        settings.accessControl.gateForEquipment('balanca-01'),
        GateState.open,
      );
      expect(
        settings.accessControl.light(GateSide.entry),
        TrafficLightState.red,
      );
      expect(
        settings.accessControl.light(GateSide.exit),
        TrafficLightState.green,
      );
    },
  );

  windowsTest('F11 respeita configuração normal, contingência e perfil', (
    tester,
  ) async {
    final settings = SettingsState()..manualWeighingEnabled = false;
    addTearDown(settings.dispose);
    settings.indicatorState.simulate(
      const IndicatorReading(
        weight: 0,
        status: IndicatorConnectionStatus.connected,
      ),
    );
    await mount(tester, settings);
    expect(
      tester.widget<TextButton>(keyed('pesagem-action-manual')).onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(keyed('manual-authentication'), findsNothing);
    settings.manualWeighingEnabled = true;
    settings.update(() {});
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextButton>(keyed('pesagem-action-manual')).onPressed,
      isNotNull,
    );
    settings.manualWeighingEnabled = false;
    settings.update(() {});
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextButton>(keyed('pesagem-action-manual')).onPressed,
      isNull,
    );
    settings.indicatorState.simulate(const IndicatorReading());
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextButton>(keyed('pesagem-action-manual')).onPressed,
      isNotNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(keyed('manual-authentication'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    settings.permissions.assign('alisson', 4);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextButton>(keyed('pesagem-action-manual')).onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(keyed('manual-authentication'), findsNothing);
  });

  windowsTest(
    'Peso Manual exige justificativa por leitura e perfil do autorizador',
    (tester) async {
      final settings = SettingsState();
      addTearDown(settings.dispose);
      final session = TicketSession();
      await mount(tester, settings, session: session);
      for (final reason in ['Falha na entrada', 'Falha na saída']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await tester.pumpAndSettle();
        await tester.enterText(keyed('manual-user'), 'balanca');
        await tester.enterText(keyed('manual-password'), 'Cxp123');
        expect(
          tester
              .widget<TextField>(keyed('manual-justification'))
              .controller!
              .text,
          isEmpty,
        );
        for (final empty in ['', '   ']) {
          await tester.enterText(keyed('manual-justification'), empty);
          await tap(tester, find.text('Liberar'));
          expect(
            find.text('Informe a justificativa desta leitura manual.'),
            findsOneWidget,
          );
          expect(keyed('manual-weight'), findsNothing);
        }
        settings.permissions.setGrant(2, AppPermission.authorizeManual, false);
        await tester.enterText(keyed('manual-justification'), reason);
        await tap(tester, find.text('Liberar'));
        expect(
          find.text('Usuário sem permissão para autorizar Peso Manual.'),
          findsOneWidget,
        );
        settings.permissions.setGrant(2, AppPermission.authorizeManual, true);
        await tap(tester, find.text('Liberar'));
        await tester.enterText(
          keyed('manual-weight'),
          reason == 'Falha na entrada' ? '18500' : '8000',
        );
        await tap(tester, find.text('Prosseguir'));
        expect(find.text('Justificativa: $reason'), findsOneWidget);
        await tap(
          tester,
          find.descendant(
            of: keyed('weighing-confirmation'),
            matching: find.text('Salvar Pesagem'),
          ),
        );
      }
      expect(session.manualReadings.map((r) => r.justification), [
        'Falha na entrada',
        'Falha na saída',
      ]);
      expect(session.current!.summary.first, 18500);
      expect(session.current!.summary.second, 8000);
      expect(session.confirmed!.manualJustification, 'Falha na saída');
    },
  );

  windowsTest(
    'Destino não aparece na Pesagem e continua no domínio integrado',
    (tester) async {
      final settings = SettingsState();
      addTearDown(settings.dispose);
      final session = TicketSession()
        ..current = WeighingPreview(
          plate: '',
          trailer: '',
          operation: {'Destino': 'DADO PRESERVADO'},
          currentWeight: 0,
          summary: const WeighingSummary(),
        );
      await mount(tester, settings, session: session);
      expect(find.text('Destino'), findsNothing);
      final plate = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is VisualField && w.label == 'Placa',
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(plate, 'ABC1D23');
      await tap(tester, find.byTooltip('Consultar placa'));
      expect(session.current!.operation['Destino'], 'DADO PRESERVADO');
      expect(find.text('Destino'), findsNothing);
    },
  );

  for (final entry in [
    (sgv: false, gates: true, lights: true, display: true),
    (sgv: true, gates: false, lights: false, display: true),
    (sgv: true, gates: true, lights: true, display: false),
    (sgv: true, gates: false, lights: true, display: false),
    (sgv: true, gates: false, lights: false, display: false),
  ]) {
    windowsTest('visibilidade dinâmica SGV/componentes $entry', (tester) async {
      final settings = SettingsState()
        ..integratedSgv = entry.sgv
        ..barriers = entry.gates
        ..trafficLight = entry.lights
        ..informationDisplay = entry.display;
      addTearDown(settings.dispose);
      await mount(tester, settings);
      expect(
        keyed('queue-tab-yard'),
        entry.sgv ? findsOneWidget : findsNothing,
      );
      expect(
        keyed('queue-tab-operation'),
        entry.sgv ? findsOneWidget : findsNothing,
      );
      expect(
        keyed('access-control'),
        entry.sgv ? findsOneWidget : findsNothing,
      );
      expect(
        keyed('gate-entry'),
        entry.sgv && entry.gates ? findsOneWidget : findsNothing,
      );
      expect(
        keyed('traffic-light-entry'),
        entry.sgv && entry.lights ? findsOneWidget : findsNothing,
      );
      expect(
        keyed('information-display'),
        entry.sgv && entry.display ? findsOneWidget : findsNothing,
      );
    });
  }

  windowsTest('mensagem do display é editável e aparece na Pesagem', (
    tester,
  ) async {
    final settings = SettingsState()
      ..integratedSgv = true
      ..informationDisplay = true;
    addTearDown(settings.dispose);
    await mount(tester, settings, configuration: true);
    await tap(tester, keyed('settings-tab-vehicles'));
    final input = keyed('display-message');
    expect(tester.widget<TextFormField>(input).initialValue, 'COOXUPÉ');
    await tester.enterText(input, '   ');
    await tester.pump();
    expect(settings.displayMessage, 'COOXUPÉ');
    expect(find.text('Informe uma mensagem para o display.'), findsOneWidget);
    await tester.enterText(input, 'BALANÇA 01');
    await tester.pump();
    expect(settings.displayMessage, 'BALANÇA 01');
    expect(keyed('simulation-display-message'), findsNothing);
    await tap(tester, keyed('save-settings'));
    await mount(tester, settings);
    expect(find.text('BALANCA 01'), findsOneWidget);
    expect(find.text('AGUARDE'), findsNothing);
  });

  windowsTest(
    'Ações ficam sob os pesos e Controle de acesso permanece lateral',
    (tester) async {
      final settings = SettingsState()
        ..integratedSgv = true
        ..barriers = true
        ..trafficLight = true
        ..informationDisplay = true;
      addTearDown(settings.dispose);
      await mount(tester, settings, size: const Size(1280, 680));

      final mainCard = keyed('pesagem-main-card');
      final sidePanel = keyed('pesagem-side-panel');
      final accessCard = keyed('access-control-card');
      final actionBar = keyed('pesagem-action-bar');
      expect(
        find.ancestor(of: accessCard, matching: sidePanel),
        findsOneWidget,
      );
      expect(find.ancestor(of: accessCard, matching: mainCard), findsNothing);
      expect(find.ancestor(of: actionBar, matching: mainCard), findsOneWidget);
      expect(find.ancestor(of: actionBar, matching: sidePanel), findsNothing);
      expect(
        tester.getTopLeft(actionBar).dy,
        greaterThan(tester.getTopLeft(keyed('weight-panels')).dy),
      );
      expect(
        tester.getTopLeft(keyed('lane-entry')).dx,
        lessThan(tester.getTopLeft(keyed('lane-exit')).dx),
      );

      for (final side in ['entry', 'exit']) {
        final lamps = find.descendant(
          of: keyed('traffic-light-$side'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.margin == const EdgeInsets.symmetric(vertical: 2),
          ),
        );
        expect(lamps, findsNWidgets(2));
        expect(
          tester.getTopLeft(lamps.first).dy,
          lessThan(tester.getTopLeft(lamps.last).dy),
        );
      }
      final displayText = tester.widget<Text>(
        find.descendant(
          of: keyed('information-display'),
          matching: find.text('COOXUPE'),
        ),
      );
      expect(displayText.style!.color, const Color(0xffff3026));
      final weightText = tester.widget<Text>(keyed('peso-atual'));
      expect(displayText.style!.fontFamily, weightText.style!.fontFamily);
      expect(displayText.style!.height, weightText.style!.height);
      expect(displayText.style!.letterSpacing, weightText.style!.letterSpacing);
      expect(displayText.style!.fontWeight, FontWeight.w700);
      expect(displayText.style!.shadows, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  windowsTest('simulação abre Entrada e preserva semáforos por papel', (
    tester,
  ) async {
    final settings = SettingsState()
      ..integratedSgv = true
      ..barriers = true
      ..trafficLight = true
      ..informationDisplay = true;
    addTearDown(settings.dispose);
    await mount(tester, settings);
    expect(find.text('Simular Entrada Abrir'), findsNothing);
    final before = tester.getTopLeft(keyed('lane-entry')).dx;
    expect(before, lessThan(tester.getTopLeft(keyed('lane-exit')).dx));
    await tap(tester, keyed('access-simulation'));
    expect(keyed('simulation-display-message'), findsNothing);
    expect(keyed('simulation-display-default'), findsNothing);
    expect(find.text('Mensagem do display'), findsNothing);
    await tap(tester, keyed('simulate-entry-open'));
    await tap(tester, find.text('Fechar'));
    expect(settings.accessControl.gate(GateSide.entry), GateState.open);
    expect(settings.accessControl.gate(GateSide.exit), GateState.closed);
    expect(
      tester
          .widget<TrafficLightVisual>(
            find.byWidgetPredicate(
              (w) => w is TrafficLightVisual && w.side == GateSide.entry,
            ),
          )
          .state,
      TrafficLightState.green,
    );
    expect(
      tester
          .widget<TrafficLightVisual>(
            find.byWidgetPredicate(
              (w) => w is TrafficLightVisual && w.side == GateSide.exit,
            ),
          )
          .state,
      TrafficLightState.red,
    );
    expect(find.text('COOXUPE'), findsOneWidget);
    expect(find.text('AGUARDE'), findsNothing);
    expect(find.text('AVANCE'), findsNothing);
    expect(find.text('PARE'), findsNothing);
    expect(find.text('PESAGEM CONCLUÍDA'), findsNothing);
    expect(find.text('Inverter posição Entrada/Saída'), findsNothing);
    expect(
      tester.getTopLeft(keyed('lane-entry')).dx,
      lessThan(tester.getTopLeft(keyed('lane-exit')).dx),
    );
    expect(settings.accessControl.gate(GateSide.entry), GateState.open);
  });

  for (final size in [
    const Size(1920, 1080),
    const Size(1366, 768),
    const Size(1280, 680),
    const Size(600, 800),
  ]) {
    windowsTest('animação e layout com SGV não geram overflow em $size', (
      tester,
    ) async {
      final settings = SettingsState()
        ..integratedSgv = true
        ..barriers = true
        ..trafficLight = true
        ..informationDisplay = true;
      addTearDown(settings.dispose);
      await mount(tester, settings, size: size);
      settings.accessControl.simulateGate(GateSide.entry, GateState.open);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      final gate = tester.getRect(keyed('gate-entry'));
      final lane = tester.getRect(keyed('lane-entry'));
      expect(gate.top, greaterThanOrEqualTo(lane.top));
      expect(gate.bottom, lessThan(lane.bottom));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  windowsTest('configurações novas responsivas em janela estreita', (
    tester,
  ) async {
    final settings = SettingsState();
    addTearDown(settings.dispose);
    await mount(
      tester,
      settings,
      configuration: true,
      size: const Size(600, 700),
    );
    for (final tab in ['models', 'indicators', 'permissions']) {
      await tap(tester, keyed('settings-tab-$tab'));
      expect(tester.takeException(), isNull);
    }
  });
}
