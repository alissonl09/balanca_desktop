import 'package:balanca_desktop/core/indicators/indicator_driver.dart';
import 'package:balanca_desktop/core/indicators/indicator_models.dart';
import 'package:balanca_desktop/core/offline/offline_models.dart';
import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/features/configuracoes/configuracoes_page.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';
import 'package:balanca_desktop/features/pesagem/operation_lookup.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_page.dart';
import 'package:balanca_desktop/features/ticket/ticket_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/serial_indicator_fake.dart';

Finder keyed(String key) => find.byKey(ValueKey(key));
final confirmation = keyed('weighing-confirmation');
Finder inside(String text) =>
    find.descendant(of: confirmation, matching: find.text(text));

void viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void setIndicator(SettingsState settings, IndicatorInstallation item) {
  settings.indicators.update(() {
    settings.indicators.installations.add(item);
    settings.indicators.operationalId = item.id;
    settings.indicators.mode = IndicatorMode.real;
  });
}

Future<void> flushSerialCallbacks(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

Future<void> closeSerial(WidgetTester tester, SettingsState settings) async {
  var closed = false;
  final closing = settings.serialIndicator.close().then((_) => closed = true);
  await flushSerialCallbacks(tester);
  expect(closed, isTrue);
  await closing;
}

void main() {
  testWidgets(
    'F12 mostra peso real, congela captura e recusa confirmação após falha',
    (tester) async {
      viewport(tester);
      final bus = FakeSerialBus();
      final settings = SettingsState(serialTransportFactory: bus.create)
        ..manualWeighingEnabled = false;
      addTearDown(settings.dispose);
      setIndicator(settings, serialInstallation(timeout: 10000, retry: 10000));
      await settings.saveIndicatorSettings(catalog: false);
      final ticket = TicketSession();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: PesagemPage(
              settings: settings,
              ticketSession: ticket,
              lookupService: const DemoOperationLookupService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final manual = keyed('pesagem-action-manual');
      Future<void> f12() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.f12);
        await tester.pumpAndSettle();
      }

      String? weight() => tester.widget<Text>(keyed('peso-atual')).data;
      Color? stabilityColor() =>
          (tester.widget<Container>(keyed('weight-stability-dot')).decoration
                  as BoxDecoration)
              .color;

      expect(weight(), '—');
      expect(stabilityColor(), const Color(0xffe14b4b));
      await f12();
      expect(confirmation, findsNothing);
      settings.indicatorState.simulate(
        const IndicatorReading(
          status: IndicatorConnectionStatus.connected,
          weight: 99999,
          stable: true,
        ),
      );
      await f12();
      expect(confirmation, findsNothing);
      bus.current.send(toledoFrame(weight: '     0'));
      await tester.pump();
      expect(weight(), '0,0');
      expect(stabilityColor(), const Color(0xff42ca75));
      expect(tester.widget<TextButton>(manual).onPressed, isNull);
      bus.current.send(toledoFrame(b: 0x38));
      await f12();
      expect(find.text('Peso instável'), findsOneWidget);
      expect(stabilityColor(), const Color(0xffe14b4b));
      expect(confirmation, findsNothing);
      expect(find.text('Aguarde o peso estabilizar.'), findsOneWidget);
      expect(tester.widget<TextButton>(manual).onPressed, isNull);
      bus.current.send(toledoFrame(b: 0x31));
      await f12();
      expect(confirmation, findsNothing);
      expect(find.textContaining('Capture em peso bruto'), findsOneWidget);

      bus.current.send(toledoFrame());
      await tester.pump();
      expect(weight(), '5700,9');
      expect(find.text('Peso estável'), findsOneWidget);
      expect(stabilityColor(), const Color(0xff42ca75));
      final firstReadAt = settings.indicatorState.reading.readAt;
      await f12();
      expect(inside('5700 Kg'), findsOneWidget);
      expect(inside('PESO BRUTO • IND570 · COM12'), findsOneWidget);
      bus.current.send(toledoFrame(weight: ' 98105'));
      await tester.pumpAndSettle();
      expect(inside('5700 Kg'), findsOneWidget);
      expect(inside('9810 Kg'), findsNothing);
      await tester.tap(inside('Salvar Pesagem'));
      await tester.pumpAndSettle();
      expect(ticket.confirmed?.currentWeight, 5700);
      expect(ticket.confirmed?.capturedAt, firstReadAt);
      expect(ticket.confirmed?.indicatorSource, 'IND570 · COM12');
      expect(ticket.phase, WeighingPhase.aberta);
      expect(ticket.manualReadings, isEmpty);

      // Segunda captura tem o peso do novo frame, mas falha se a sessão cair.
      await tester.tap(keyed('pesagem-action-pesar'));
      await tester.pumpAndSettle();
      expect(inside('9810 Kg'), findsNWidgets(2));
      expect(inside('4110 Kg'), findsOneWidget);
      expect(ticket.current?.summary.netWeight, isNull);
      bus.current.fail('Conversor removido');
      await tester.pumpAndSettle();
      await tester.tap(inside('Salvar Pesagem'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cancele e faça uma nova captura.'),
        findsOneWidget,
      );
      expect(ticket.confirmed?.currentWeight, 5700);
      expect(ticket.phase, WeighingPhase.aberta);
      expect(ticket.current?.summary.netWeight, isNull);
      await tester.tap(inside('Cancelar'));
      await tester.pumpAndSettle();
      expect(weight(), '—');
      expect(tester.widget<TextButton>(manual).onPressed, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(keyed('manual-justification'), findsOneWidget);
      await closeSerial(tester, settings);
    },
  );

  testWidgets(
    'configuração preserva COM ausente, testa e aplica o perfil ComTool',
    (tester) async {
      viewport(tester);
      final bus = FakeSerialBus();
      var ports = <String>['COM11', 'COM12'];
      final settings = SettingsState(
        serialTransportFactory: bus.create,
        serialPortList: () async => ports,
      );
      addTearDown(settings.dispose);
      final item = serialInstallation(port: 'COM37');
      setIndicator(settings, item);
      final ticket = TicketSession();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConfiguracoesPage(
                compact: false,
                settings: settings,
                ticketSession: ticket,
              ),
            ),
          ),
        ),
      );
      Future<void> click(String key) async {
        await tester.ensureVisible(keyed(key));
        await tester.tap(keyed(key));
        await tester.pumpAndSettle();
      }

      await click('settings-tab-indicators');
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        keyed('indicator-com'),
      );
      expect(dropdown.initialValue, 'COM37');
      expect(find.text('COM37 (indisponível)'), findsOneWidget);
      ports = ['COM12', 'COM37'];
      await click('refresh-indicator-ports');
      expect(find.text('COM37 (indisponível)'), findsNothing);
      expect(find.text('COM37'), findsOneWidget);
      expect(item.windowsPort, 'COM37');
      await click('indicator-serial-advanced');
      await click('indicator-toledo-weight-scale');
      await tester.tap(find.text('Captura ComTool (kg inteiros)').last);
      await tester.pumpAndSettle();
      await click('indicator-serial-advanced');

      final button = keyed('test-indicator-connection');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await flushSerialCallbacks(tester);
      expect(bus.current.parameters!.comPort, 'COM37');
      expect(bus.current.parameters!.baudRate, 4800);
      expect(bus.current.parameters!.checksum, isTrue);
      expect(bus.current.stream.hasListener, isTrue);
      bus.current.send('\x02)0     00    00\r8'.codeUnits);
      for (
        var i = 0;
        i < 5 && find.text('Testando...').evaluate().isNotEmpty;
        i++
      ) {
        await flushSerialCallbacks(tester);
      }
      expect(bus.current.released, isTrue);
      expect(find.text('Testando...'), findsNothing);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Bytes recebidos: 18', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Último peso válido: 0 kg', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('ASCII: <STX>', findRichText: true),
        findsOneWidget,
      );
      expect(ticket.confirmed, isNull);
      expect(ticket.phase, WeighingPhase.nova);
      expect(settings.serialIndicator.realMode, isFalse);
      expect(bus.openPorts, isEmpty);

      await click('save-settings');
      await flushSerialCallbacks(tester);
      expect(settings.serialIndicator.realMode, isTrue);
      bus.current.send('\x02)0     30    00\r5'.codeUnits);
      expect(settings.indicatorState.reading.weight, 30);
      expect(settings.serialIndicator.capture().reading.wholeKg, 30);
      expect(ticket.confirmed, isNull);
      await closeSerial(tester, settings);
    },
  );
}
