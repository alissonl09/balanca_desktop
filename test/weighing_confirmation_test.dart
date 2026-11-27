import 'dart:async';

import 'package:balanca_desktop/core/permissions/permission_models.dart';
import 'package:balanca_desktop/core/indicators/indicator_models.dart';
import 'package:balanca_desktop/core/offline/offline_models.dart';
import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/core/widgets/visual_components.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';
import 'package:balanca_desktop/features/pesagem/operation_lookup.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_page.dart';
import 'package:balanca_desktop/features/pesagem/weighing_dialogs.dart';
import 'package:balanca_desktop/features/pesagem/weighing_preview.dart';
import 'package:balanca_desktop/features/ticket/printer_service.dart';
import 'package:balanca_desktop/features/ticket/ticket_print_renderer.dart';
import 'package:balanca_desktop/features/ticket/ticket_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/serial_indicator_fake.dart';

final confirmation = find.byKey(const ValueKey('weighing-confirmation'));
final plateField = find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is VisualField && widget.label == 'Placa',
  ),
  matching: find.byType(TextField),
);
Finder dialogButton(String text) =>
    find.descendant(of: confirmation, matching: find.text(text));

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> openConfirmation(
  WidgetTester tester,
  bool manual, {
  String manualWeight = '12345',
}) async {
  await tap(
    tester,
    find.byKey(ValueKey('pesagem-action-${manual ? 'manual' : 'pesar'}')),
  );
  if (manual) {
    await tester.enterText(
      find.byKey(const ValueKey('manual-user')),
      'balanca',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-password')),
      'Cxp123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-justification')),
      'Indicador indisponível',
    );
    await tap(tester, find.text('Liberar'));
    await tester.enterText(
      find.byKey(const ValueKey('manual-weight')),
      manualWeight,
    );
    await tap(tester, find.text('Prosseguir'));
  }
  expect(confirmation, findsOneWidget);
}

class RecordingPrinter implements PrintJobAdapter {
  final jobs = <(PrintTarget, PrintDocument)>[];
  PrintResult result = const PrintResult(PrintStatus.accepted);

  @override
  Future<List<String>> queues() async => ['Cupom'];

  @override
  Future<PrinterQueueInfo> inspect(String queue) async =>
      const PrinterQueueInfo([PrinterPaper(100, 'Bobina', 580, 2000)]);

  @override
  Future<PrintResult> printJob(
    PrintTarget target,
    PrintDocument document,
    Duration timeout,
  ) async {
    jobs.add((target, document));
    return result;
  }
}

void main() {
  for (final manual in [false, true]) {
    for (final (opening, closing) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      testWidgets(
        'Impressão automática ${manual ? "manual" : "serial"}: abertura=$opening, fechamento=$closing',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1600, 1000);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final adapter = RecordingPrinter();
          final printer = PrinterService(adapter);
          final bus = FakeSerialBus();
          addTearDown(printer.dispose);
          final printing = PrintSettings()
            ..emitEntry = opening
            ..emitExit = closing
            ..ticket.enabled = true
            ..ticket.queue = 'Cupom'
            ..ticket.paper = const PrinterPaper(100, 'Bobina', 580, 2000);
          final settings = SettingsState(
            printerService: printer,
            serialTransportFactory: bus.create,
            printStations: {'homologacao/4': printing.toJson()},
          );
          addTearDown(settings.dispose);
          if (!manual) {
            final installation = serialInstallation(
              timeout: 10000,
              retry: 10000,
            );
            settings.indicators.update(() {
              settings.indicators.installations.add(installation);
              settings.indicators.operationalId = installation.id;
              settings.indicators.mode = IndicatorMode.real;
            });
            await settings.saveIndicatorSettings(catalog: false);
          }
          final session = TicketSession(ticketNumber: '000123');
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(),
              home: Scaffold(
                body: PesagemPage(
                  settings: settings,
                  ticketSession: session,
                  lookupService: const DemoOperationLookupService(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(plateField, 'ABC1D23');
          Future<void> capture({required bool second}) async {
            if (!manual) {
              bus.current.send(
                toledoFrame(weight: second ? ' 30000' : ' 57900'),
              );
              await tester.pump();
            }
            await openConfirmation(
              tester,
              manual,
              manualWeight: second ? '3000' : '5790',
            );
          }

          await capture(second: false);
          await tap(tester, dialogButton('Cancelar'));
          expect(adapter.jobs, isEmpty);
          expect(session.phase, WeighingPhase.nova);
          await capture(second: false);
          if (opening && closing) {
            final permission = manual
                ? AppPermission.useManual
                : AppPermission.weigh;
            settings.permissions.setGrant(1, permission, false);
            await tap(tester, dialogButton('Salvar Pesagem'));
            expect(
              find.byKey(const ValueKey('weighing-confirmation-error')),
              findsOneWidget,
            );
            expect(adapter.jobs, isEmpty);
            expect(session.phase, WeighingPhase.nova);
            settings.permissions.setGrant(1, permission, true);
          }
          await tap(tester, dialogButton('Salvar Pesagem'));
          expect(session.phase, WeighingPhase.aberta);
          expect(adapter.jobs, hasLength(opening ? 1 : 0));
          expect(session.printableTicket?.secondWeight, isNull);

          await capture(second: true);
          await tap(tester, dialogButton('Salvar Pesagem'));
          expect(session.phase, WeighingPhase.fechada);
          expect(
            adapter.jobs,
            hasLength((opening ? 1 : 0) + (closing ? 1 : 0)),
          );
          expect(adapter.jobs.map((job) => job.$2.ticket?.secondWeight), [
            if (opening) null,
            if (closing) 3000,
          ]);
          final beforeF5 = adapter.jobs.length;
          await tap(
            tester,
            find.byKey(const ValueKey('pesagem-action-imprimir')),
          );
          expect(adapter.jobs, hasLength(beforeF5 + 1));
          expect(
            adapter.jobs.last.$2.ticket?.ticketNumber,
            session.printableTicket?.ticketNumber,
          );

          if (!manual) {
            final close = settings.serialIndicator.close();
            await tester.pump();
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
            await tester.pump();
            await close;
          }
        },
      );
    }
  }

  testWidgets('A4 de contingência revalida a opção antes de enviar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = RecordingPrinter()
      ..result = const PrintResult(PrintStatus.queueMissing);
    final printer = PrinterService(adapter);
    addTearDown(printer.dispose);
    final printing = PrintSettings()
      ..ticket.enabled = true
      ..ticket.queue = 'Cupom'
      ..ticket.paper = const PrinterPaper(100, 'Bobina', 580, 2000)
      ..a4.enabled = true
      ..a4.queue = 'Impressora A4';
    final settings = SettingsState(
      printerService: printer,
      printStations: {'homologacao/4': printing.toJson()},
    );
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: PesagemPage(
            settings: settings,
            ticketSession: TicketSession(),
            lookupService: const DemoOperationLookupService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(plateField, 'ABC1D23');
    await openConfirmation(tester, true);
    await tap(tester, dialogButton('Salvar Pesagem'));
    expect(adapter.jobs, hasLength(1));
    final fallback = find.text('Imprimir em A4');
    expect(fallback, findsOneWidget);
    settings.printing.emitEntry = false;
    await tap(tester, fallback);
    expect(adapter.jobs, hasLength(1));
  });

  for (final autoPrint in [false, true]) {
    testWidgets(
      'Fechamento manual confirma o líquido e respeita emissão automática ${autoPrint ? 'ativa' : 'inativa'}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final adapter = RecordingPrinter();
        final printer = PrinterService(adapter);
        addTearDown(printer.dispose);
        final printing = PrintSettings()
          ..emitEntry = autoPrint
          ..emitExit = autoPrint
          ..ticket.enabled = true
          ..ticket.queue = 'Cupom'
          ..ticket.paper = const PrinterPaper(100, 'Bobina', 580, 2000)
          ..ticket.copies = 3;
        final settings = SettingsState(
          printerService: printer,
          printStations: {'homologacao/4': printing.toJson()},
        );
        addTearDown(settings.dispose);
        if (!autoPrint) {
          // Um rascunho que ativa a impressão não supera a opção salva.
          settings.printing.emitExit = true;
        } else {
          // Desativar na tela interrompe a impressão antes mesmo de salvar.
          settings.printing.emitEntry = false;
        }
        final session = TicketSession(ticketNumber: '000123');
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: PesagemPage(
                settings: settings,
                ticketSession: session,
                lookupService: const DemoOperationLookupService(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(plateField, 'ABC1D23');
        await openConfirmation(tester, true, manualWeight: '17000,1');
        await tap(tester, dialogButton('Salvar Pesagem'));
        expect(session.phase, WeighingPhase.aberta);
        expect(adapter.jobs, isEmpty);

        await tester.enterText(plateField, 'DEF4G56');
        await tap(tester, find.byKey(const ValueKey('pesagem-action-manual')));
        expect(
          find.byKey(const ValueKey('manual-authentication')),
          findsNothing,
        );
        expect(session.phase, WeighingPhase.aberta);
        expect(adapter.jobs, isEmpty);
        await tester.enterText(plateField, 'ABC1D23');

        await openConfirmation(tester, true, manualWeight: '12345,6');
        expect(dialogButton('4654,5 Kg'), findsOneWidget);
        expect(session.current?.summary.netWeight, isNull);
        await tap(tester, dialogButton('Cancelar'));
        expect(session.phase, WeighingPhase.aberta);
        expect(session.manualReadings, hasLength(1));
        expect(session.current?.summary.netWeight, isNull);
        expect(adapter.jobs, isEmpty);

        await openConfirmation(tester, true, manualWeight: '12345,1');
        expect(dialogButton('4655 Kg'), findsOneWidget);
        expect(adapter.jobs, isEmpty);
        await tap(tester, dialogButton('Salvar Pesagem'));
        expect(session.phase, WeighingPhase.fechada);
        expect(session.manualReadings, hasLength(2));
        expect(session.current?.summary.netWeight, 4655);
        final net = tester.widget<Text>(
          find.byKey(const ValueKey('summary-value-Peso Líquido')),
        );
        expect(net.textSpan?.toPlainText(), '4655 Kg');
        expect(adapter.jobs, hasLength(autoPrint ? 1 : 0));
        if (!autoPrint) {
          await tap(
            tester,
            find.byKey(const ValueKey('pesagem-action-imprimir')),
          );
        }
        final (target, document) = adapter.jobs.single;
        expect(target.copies, 3);
        expect(target.format, PrinterFormat.ticket);
        expect(document.ticket, same(session.printableTicket));
        expect(document.ticket?.ticketNumber, '000123');
        expect(document.ticket?.tractorPlate, 'ABC1D23');
        expect(document.ticket?.netWeight, 4655);
      },
    );
  }

  for (final manual in [false, true]) {
    final flow = manual ? 'manual' : 'normal';
    for (final outcome in ['cancel', 'save', 'error']) {
      testWidgets('$flow: modal bloqueante e $outcome', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = SettingsState();
        addTearDown(settings.dispose);
        final session = TicketSession();
        var backgroundClicks = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  TextButton(
                    key: const ValueKey('background-action'),
                    onPressed: () => backgroundClicks++,
                    child: const Text('Menu principal'),
                  ),
                ],
              ),
              body: PesagemPage(
                settings: settings,
                ticketSession: session,
                lookupService: const DemoOperationLookupService(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await openConfirmation(tester, manual);

        final route = ModalRoute.of(tester.element(confirmation))!;
        final navigator = Navigator.of(tester.element(confirmation));
        await tester.tapAt(const Offset(2, 500));
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('background-action'))),
        );
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('pesagem-action-nova'))),
        );
        await tester.pumpAndSettle();
        expect(backgroundClicks, 0);
        expect(confirmation, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(confirmation, findsOneWidget);
        await navigator.maybePop();
        await tester.pumpAndSettle();
        expect(confirmation, findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(confirmation, findsOneWidget);
        for (var i = 0; i < 30; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            ModalRoute.of(FocusManager.instance.primaryFocus!.context!),
            same(route),
          );
        }
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(
          ModalRoute.of(FocusManager.instance.primaryFocus!.context!),
          same(route),
        );
        FocusManager.instance.primaryFocus!.unfocus();
        await tester.pumpAndSettle();
        expect(confirmation, findsOneWidget);
        expect(session.confirmed, isNull);

        if (outcome == 'cancel') {
          await tap(tester, dialogButton('Cancelar'));
          expect(confirmation, findsNothing);
          expect(session.confirmed, isNull);
          expect(session.manualReadings, isEmpty);
        } else {
          final permission = manual
              ? AppPermission.useManual
              : AppPermission.weigh;
          if (outcome == 'error') {
            settings.permissions.setGrant(1, permission, false);
            await tester.pumpAndSettle();
            await tap(tester, dialogButton('Salvar Pesagem'));
            expect(confirmation, findsOneWidget);
            expect(
              find.byKey(const ValueKey('weighing-confirmation-error')),
              findsOneWidget,
            );
            expect(session.confirmed, isNull);
            expect(session.manualReadings, isEmpty);
            settings.permissions.setGrant(1, permission, true);
            await tester.pumpAndSettle();
          }
          await tap(tester, dialogButton('Salvar Pesagem'));
          expect(confirmation, findsNothing);
          expect(session.confirmed, isNotNull);
          expect(session.confirmed!.isManual, manual);
          expect(session.manualReadings, hasLength(manual ? 1 : 0));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'salvamento pendente bloqueia fechamento; falha permite tentar novamente',
    (tester) async {
      var pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showWeighingConfirmation(
                  context,
                  WeighingPreview(
                    plate: '',
                    trailer: '',
                    operation: {},
                    currentWeight: 0,
                    summary: const WeighingSummary(),
                  ),
                  onSave: () => pending.future,
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('Abrir'));
      await tap(tester, dialogButton('Salvar Pesagem'));
      expect(confirmation, findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
            .onPressed,
        isNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(confirmation, findsOneWidget);
      pending.completeError(StateError('Falha ao salvar'));
      await tester.pumpAndSettle();
      expect(confirmation, findsOneWidget);
      expect(
        find.byKey(const ValueKey('weighing-confirmation-error')),
        findsOneWidget,
      );
      pending = Completer<void>();
      await tap(tester, dialogButton('Salvar Pesagem'));
      expect(confirmation, findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(confirmation, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
