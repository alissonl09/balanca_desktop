import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:balanca_desktop/app/balanca_app.dart';
import 'package:balanca_desktop/core/indicators/indicator_models.dart';
import 'package:balanca_desktop/core/offline/offline_models.dart';
import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/features/configuracoes/configuracoes_page.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';
import 'package:balanca_desktop/features/pesagem/operation_lookup.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_page.dart';
import 'package:balanca_desktop/features/ticket/printer_service.dart';
import 'package:balanca_desktop/features/ticket/ticket_paper.dart';
import 'package:balanca_desktop/features/ticket/ticket_pesagem.dart';
import 'package:balanca_desktop/features/ticket/ticket_print_renderer.dart';
import 'package:balanca_desktop/features/ticket/ticket_session.dart';
import 'package:balanca_desktop/features/ticket/windows_printer_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/serial_indicator_fake.dart';

const roll = PrinterPaper(100, 'Bobina 58', 580, 2000);
const a4 = PrinterPaper(9, 'A4', 2100, 2970);
const rollArea = PrintableArea(52, 195, 203);
const a4Area = PrintableArea(200, 287, 300);

class FakePrinterAdapter implements RasterPrinterAdapter {
  List<String> installed = ['Bobina USB', r'\\rede\A4'];
  final jobs = <(PrintTarget, String, List<PrintPage>)>[];
  final preparations = <PrintTarget>[];
  Completer<PrintResult>? pending;

  @override
  Future<List<String>> queues() async => List.of(installed);

  @override
  Future<PrinterQueueInfo> inspect(String queue) async =>
      PrinterQueueInfo(queue == 'Bobina USB' ? [roll] : [a4]);

  @override
  Future<PrintableArea> prepare(PrintTarget target) async {
    preparations.add(target);
    final papers = (await inspect(target.queue)).papers;
    if (target.format == PrinterFormat.ticket
        ? !papers.any((paper) => target.paper?.matches(paper) == true)
        : !papers.any((paper) => paper.isA4)) {
      throw const PrinterException(PrintResult(PrintStatus.unsupportedPaper));
    }
    return target.format == PrinterFormat.ticket ? rollArea : a4Area;
  }

  @override
  Future<PrintResult> send(
    PrintTarget target,
    PrintableArea area,
    String title,
    List<PrintPage> pages,
  ) async {
    jobs.add((target, title, pages));
    return pending == null
        ? const PrintResult(PrintStatus.accepted, jobId: 22)
        : pending!.future;
  }
}

PrintSettings configured(FakePrinterAdapter adapter) => PrintSettings()
  ..ticket.enabled = true
  ..ticket.queue = adapter.installed.first
  ..ticket.paper = roll
  ..ticket.copies = 2
  ..a4.enabled = true
  ..a4.queue = adapter.installed.last
  ..a4.copies = 3;

PrintDocument printTest() => PrintDocument.test(
  station: 'Estação A',
  queue: 'Bobina USB',
  paper: roll.label,
  time: DateTime(2026, 11, 25, 15),
  logo: TicketLogoKind.standard,
);

Finder keyed<T>(T value) => find.byKey(ValueKey<T>(value));

void viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1366, 850);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 300 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!Platform.isWindows) return;
    final fonts = FontLoader('Arial');
    for (final font in ['arial.ttf', 'arialbd.ttf']) {
      final file = File(
        '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/$font',
      );
      fonts.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await fonts.load();
  });

  test(
    'Restaurar a impressão local conserva destinos distintos por estação',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'balanca-impressao-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final store = LocalPrintSettingsStore(directory: () async => folder);
      final state = SettingsState(printStore: store);
      addTearDown(state.dispose);
      state.printing.a4
        ..enabled = true
        ..queue = r'\\rede\A4'
        ..copies = 4;
      state.printing
        ..preferred = PrinterFormat.a4
        ..emitExit = false
        ..emitEntry = false
        ..logo = TicketLogo.demonstration
        ..companyName = 'Cooperativa - unidade de teste'
        ..header = 'Cabeçalho'
        ..footer = 'Rodapé';
      expect(state.savedPrinting.a4.queue, isNull);
      await state.savePrintSettings();
      state.update(() => state.unitCode = 7);
      expect(state.printing.a4.enabled, isFalse);
      state.printing.ticket
        ..enabled = true
        ..queue = 'Bobina USB'
        ..paper = roll;
      await state.savePrintSettings();

      final restarted = SettingsState(
        printStore: store,
        printStations: await store.load(),
      );
      addTearDown(restarted.dispose);
      final restored = restarted.savedPrinting;
      expect(restored.preferred, PrinterFormat.a4);
      expect(restored.ticket.enabled, isFalse);
      expect(restored.a4.queue, r'\\rede\A4');
      expect(restored.a4.copies, 4);
      expect(restored.emitExit, isFalse);
      expect(restored.emitEntry, isFalse);
      expect(restored.logo, TicketLogo.demonstration);
      expect(restored.companyName, 'Cooperativa - unidade de teste');
      expect((restored.header, restored.footer), ('Cabeçalho', 'Rodapé'));
      restarted.update(() => restarted.unitCode = 7);
      expect(restarted.savedPrinting.ticket.paper?.matches(roll), isTrue);
      expect(restarted.savedPrinting.a4.enabled, isFalse);
      expect(
        restarted.savedPrinting.companyName,
        TicketBranding.defaultCompanyName,
      );
    },
  );

  test('Teste usa o destino e cópias certos e valida antes de gerar', () async {
    final adapter = FakePrinterAdapter();
    final service = PrinterService(adapter);
    addTearDown(service.dispose);
    final settings = configured(adapter)..a4.enabled = false;
    Future<PrintStatus> run(PrinterFormat format, {bool test = false}) async =>
        (await service.print(
          settings: settings,
          format: format,
          document: printTest,
          test: test,
        )).status;

    expect(await run(PrinterFormat.a4), PrintStatus.disabled);
    expect(adapter.preparations, isEmpty);
    expect(await run(PrinterFormat.a4, test: true), PrintStatus.accepted);
    expect(await run(PrinterFormat.ticket, test: true), PrintStatus.accepted);
    final (a4Target, title, a4Pages) = adapter.jobs.first;
    final (rollTarget, _, rollPages) = adapter.jobs.last;
    expect(title, 'Teste de impressão');
    expect(
      (a4Target.queue, a4Target.format, a4Target.copies),
      (adapter.installed.last, PrinterFormat.a4, 3),
    );
    expect(
      (rollTarget.queue, rollTarget.paper, rollTarget.copies),
      (adapter.installed.first, roll, 2),
    );
    expect(a4Pages.single.width, greaterThan(rollPages.single.width));
    expect(rollPages.single.height, lessThan(rollArea.heightMm / 25.4 * 203));
    settings.ticket.copies = 0;
    expect(await run(PrinterFormat.ticket), PrintStatus.invalidCopies);
    settings.ticket
      ..copies = 1
      ..paper = a4;
    expect(await run(PrinterFormat.ticket), PrintStatus.unsupportedPaper);
    settings.ticket.paper = roll;
    expect(await service.queues(), hasLength(2));
    adapter.installed = [];
    expect(await service.queues(), isEmpty);
    expect(await run(PrinterFormat.ticket), PrintStatus.queueMissing);
    settings.simulated = true;
    expect(await run(PrinterFormat.ticket, test: true), PrintStatus.simulated);
    expect(adapter.jobs, hasLength(2));
  });

  test('Cupom e A4 compartilham dados e quebram textos extensos', () async {
    final issued = DateTime(2026, 11, 25, 15);
    final text = List.filled(14, 'ÁREA-Ç-SEM-ESPAÇO').join();
    final ticket = TicketPesagem(
      ticketNumber: '92821',
      documents: [text],
      observation: 'Aferição e saída confirmadas.',
      firstWeight: 123456789.321,
      firstWeighedAt: issued,
      issuedAt: issued,
      traceabilityId: '92821',
      captureType: TicketCaptureType.automatic,
      branding: TicketBranding(
        headerLines: ['Cooxupé'],
        footerLines: ['Até logo'],
      ),
    );
    final data = PrintDocument.fromJson(
      jsonDecode(jsonEncode(PrintDocument.ticket(ticket).toJson()))
          as Map<String, dynamic>,
    );
    expect(data.ticket?.toJson(), ticket.toJson());
    final rollPages = await renderPrintDocument(
      data,
      const PrintableArea(52, 300, 203),
      a4: false,
    );
    final a4Pages = await renderPrintDocument(data, a4Area, a4: true);
    expect(rollPages, hasLength(1));
    expect(a4Pages, hasLength(1));
    final tall = await renderPrintDocument(
      data,
      const PrintableArea(52, 38, 203),
      a4: false,
    );
    expect(tall.length, greaterThan(1));
    for (final page in [...rollPages, ...a4Pages, ...tall]) {
      expect(page.pixels.length, page.width * page.height * 4);
      expect(page.pixels, contains(0));
    }
  });

  testWidgets('Cupom impresso reproduz pixel a pixel o papel da prévia', (
    tester,
  ) async {
    viewport(tester);
    final at = DateTime(2026, 11, 25, 15);
    final ticket = TicketPesagem(
      ticketNumber: '92821',
      traceabilityId: '92821',
      tractorPlate: 'ABC1D23',
      firstWeighedAt: at,
      firstWeight: 40000,
      secondWeighedAt: at.add(const Duration(minutes: 15)),
      secondWeight: 12000,
      netWeight: 28000,
      issuedAt: at,
      captureType: TicketCaptureType.manual,
      manualAuthorizer: 'Operador',
      manualJustification: 'Conferência de impressão',
      branding: TicketBranding(
        logo: TicketLogoKind.standard,
        headerLines: ['Cabeçalho'],
        footerLines: ['Rodapé'],
      ),
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: boundary,
              child: TicketPaper(ticket: ticket, format: PrinterFormat.ticket),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final reference =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final preview = await reference.toImage();
      try {
        final data = (await preview.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final width = TicketPaper.widthFor(PrinterFormat.ticket);
        final printed = (await renderPrintDocument(
          PrintDocument.ticket(ticket),
          PrintableArea((width + 0.5) * 25.4 / 150, 300, 150),
          a4: false,
        )).single;
        expect(
          (printed.width, printed.height),
          (preview.width, preview.height),
        );
        expect(
          listEquals(
            printed.pixels,
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ),
          isTrue,
        );
      } finally {
        preview.dispose();
      }
    });
  });

  testWidgets('Aba atualiza filas vazias e conserva a seleção removida', (
    tester,
  ) async {
    viewport(tester);
    final adapter = FakePrinterAdapter();
    final service = PrinterService(adapter);
    addTearDown(service.dispose);
    await tester.pumpWidget(
      BalancaApp(
        printerService: service,
        lookupService: const DemoOperationLookupService(),
        printStations: {'homologacao/4': configured(adapter).toJson()},
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tap(Finder button) async {
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    await tap(keyed('menu-config'));
    await tap(keyed('settings-tab-printing'));
    expect(find.text('Papel da bobina'), findsOneWidget);
    expect(find.text('Papel A4 · Retrato'), findsOneWidget);
    adapter.installed = [];
    await tap(find.text('Atualizar impressoras'));
    expect(
      find.text('Nenhuma fila de impressão instalada no Windows.'),
      findsOneWidget,
    );
    expect(find.text('Bobina USB (fila não localizada)'), findsOneWidget);
    final settings = tester
        .widget<ConfiguracoesPage>(find.byType(ConfiguracoesPage))
        .settings;
    expect(settings.savedPrinting.ticket.queue, 'Bobina USB');
    expect(settings.savedPrinting.a4.queue, r'\\rede\A4');
    expect(adapter.jobs, isEmpty);
  });

  test(
    'Documento que ultrapassa o tempo limite nunca chega ao envio',
    () async {
      final adapter = FakePrinterAdapter();
      final service = PrinterService(
        adapter,
        timeout: const Duration(milliseconds: 80),
      );
      addTearDown(service.dispose);
      final pending = Completer<PrintDocument>();
      final result = await service.print(
        settings: configured(adapter),
        format: PrinterFormat.ticket,
        document: () => pending.future,
      );
      expect(result.status, PrintStatus.generationError);
      expect(result.canOfferAlternative, isFalse);
      expect(service.busy, isFalse);
      pending.complete(printTest());
      await Future<void>.delayed(Duration.zero);
      expect(adapter.jobs, isEmpty);
    },
  );

  testWidgets(
    'Cupom com fila salva passa a imprimir pelo botão após ativar e salvar',
    (tester) async {
      viewport(tester);
      final adapter = FakePrinterAdapter();
      final service = PrinterService(adapter);
      addTearDown(service.dispose);
      final saved = configured(adapter)
        ..ticket.enabled = false
        ..a4.enabled = false;
      await tester.pumpWidget(
        BalancaApp(
          printerService: service,
          lookupService: const DemoOperationLookupService(),
          printStations: {'homologacao/4': saved.toJson()},
        ),
      );
      await tester.pumpAndSettle();

      Future<void> tap(Finder button) async {
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await tap(keyed('menu-config'));
      await tap(keyed('settings-tab-printing'));
      final page = tester.widget<ConfiguracoesPage>(
        find.byType(ConfiguracoesPage),
      );
      page.ticketSession
        ..printableStation = page.settings.indicatorStationId
        ..printableTicket = TicketPesagem(
          ticketNumber: '2308',
          firstWeight: 5700,
          issuedAt: DateTime(2026, 11, 25),
          captureType: TicketCaptureType.automatic,
          branding: TicketBranding(),
        );

      await tap(keyed('save-settings'));
      expect(find.textContaining('Configuração salva. Ative'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap(keyed('menu-balanca_icon'));
      await tap(keyed('pesagem-action-imprimir'));
      expect(
        find.text('Ticket/Cupom · ${PrintStatus.disabled.message}'),
        findsOneWidget,
      );
      expect(adapter.jobs, isEmpty);

      await tap(keyed('menu-config'));
      await tap(keyed('settings-tab-printing'));
      await tap(keyed(('print-enabled', PrinterFormat.ticket)));
      await tap(keyed('save-settings'));
      expect(page.settings.savedPrinting.ticket.enabled, isTrue);
      expect(page.settings.savedPrinting.a4.enabled, isFalse);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tap(keyed('menu-balanca_icon'));
      await tap(keyed('pesagem-action-imprimir'));
      await waitFor(tester, () => adapter.jobs.length == 1 && !service.busy);
      expect(adapter.jobs.single.$1.queue, 'Bobina USB');
    },
  );

  testWidgets(
    'Entrada, F5, tempo excedido, alternativa e saída usam a mesma confirmação',
    (tester) async {
      viewport(tester);
      final adapter = FakePrinterAdapter();
      final results = <Object?>[];
      final service = PrinterService(
        adapter,
        timeout: const Duration(seconds: 2),
        log: (record) => results.add(record['resultado']),
      );
      addTearDown(service.dispose);
      final bus = FakeSerialBus();
      final settings = SettingsState(
        printerService: service,
        printStations: {'homologacao/4': configured(adapter).toJson()},
        serialTransportFactory: bus.create,
      );
      addTearDown(settings.dispose);
      settings.indicators.update(() {
        final item = serialInstallation(timeout: 30000);
        settings.indicators.installations.add(item);
        settings.indicators.operationalId = item.id;
        settings.indicators.mode = IndicatorMode.real;
      });
      await settings.saveIndicatorSettings(catalog: false);
      final session = TicketSession(ticketNumber: '2308');
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
      Future<void> weigh(String weight) async {
        bus.current.send(toledoFrame(weight: weight));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.f12);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: keyed('weighing-confirmation'),
            matching: find.text('Salvar Pesagem'),
          ),
        );
        await tester.pumpAndSettle();
      }

      adapter.pending = Completer<PrintResult>();
      await weigh(' 57009');
      await waitFor(tester, () => adapter.jobs.length == 1);
      expect(adapter.jobs.single.$1.copies, 2);
      final entry = session.printableTicket;
      expect(entry?.ticketNumber, '2308');
      expect(session.phase, WeighingPhase.aberta);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      bus.current.send(toledoFrame(weight: ' 98105'));
      await tester.pump(const Duration(milliseconds: 2100));
      await tester.pumpAndSettle();
      expect(settings.indicatorState.reading.wholeKg, 9810);
      expect(results, contains(PrintStatus.unknown.name));
      expect(
        find.textContaining('Resultado do envio desconhecido.'),
        findsOneWidget,
      );
      expect(service.busy, isTrue);
      expect(adapter.jobs, hasLength(1));
      expect(session.printableTicket, same(entry));
      expect(find.text('Imprimir em A4'), findsNothing);
      adapter.pending!.complete(
        const PrintResult(PrintStatus.accepted, jobId: 31),
      );
      adapter.pending = null;
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await waitFor(tester, () => adapter.jobs.length == 2 && !service.busy);
      expect(adapter.jobs[1].$1.queue, 'Bobina USB');
      expect(session.printableTicket, same(entry));
      await tester.pumpAndSettle();
      adapter.installed = [adapter.installed.last];
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(adapter.jobs, hasLength(2));
      await tester.tap(find.text('Imprimir em A4'));
      await waitFor(tester, () => adapter.jobs.length == 3 && !service.busy);
      expect(adapter.jobs[2].$1.format, PrinterFormat.a4);

      settings.printing.preferred = PrinterFormat.a4;
      await settings.savePrintSettings();
      await tester.pumpAndSettle();
      await weigh(' 98105');
      await waitFor(tester, () => adapter.jobs.length == 4 && !service.busy);
      expect(session.phase, WeighingPhase.fechada);
      expect(session.printableTicket?.firstWeight, 5700);
      expect(session.printableTicket?.secondWeight, 9810);
      expect(session.printableTicket?.netWeight, 4110);
      expect(session.current?.summary.netWeight, 4110);
      final net = tester.widget<Text>(keyed('summary-value-Peso Líquido'));
      expect(net.textSpan?.toPlainText(), '4110 Kg');
      expect(session.printableTicket?.ticketNumber, entry?.ticketNumber);
      expect(adapter.jobs[3].$1.format, PrinterFormat.a4);
      expect(adapter.jobs[3].$1.copies, 3);
      var closed = false;
      final closing = settings.serialIndicator.close().then(
        (_) => closed = true,
      );
      await waitFor(tester, () => closed);
      await closing;
    },
  );

  if (Platform.isWindows &&
      const bool.fromEnvironment('PRINT_WINDOWS_READ_ONLY')) {
    final executable = File(
      'build/windows/x64/runner/Release/balanca_desktop.exe',
    ).absolute;
    test(
      'Win32 consulta filas e formatos instalados sem submeter trabalho',
      () async {
        final adapter = WindowsPrinterAdapter(executable: executable.path);
        final queues = await adapter.queues();
        for (final queue in queues) {
          await adapter.inspect(queue).timeout(const Duration(seconds: 15));
        }
      },
    );
    test(
      'Executável Windows renderiza em processo auxiliar com bobina longa',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'balanca-print-probe-',
        );
        addTearDown(() => directory.delete(recursive: true));
        await File('${directory.path}/request.json').writeAsString(
          jsonEncode({
            'operation': 'render',
            'widthMm': 70,
            'heightMm': 3002.9,
            'dpi': 203,
            'document': PrintDocument.ticket(
              TicketPesagem(
                ticketNumber: 'TEST-92821',
                traceabilityId: 'TEST-92821',
                firstWeight: 40000,
                secondWeight: 12000,
                netWeight: 28000,
                issuedAt: DateTime(2026, 11, 25, 15),
                captureType: TicketCaptureType.automatic,
                branding: TicketBranding(
                  headerLines: ['Cooxupé'],
                  footerLines: ['Até logo'],
                ),
              ),
            ).toJson(),
          }),
        );
        final process = await Process.start(executable.path, [
          windowsPrintWorkerArgument,
          directory.path,
        ], workingDirectory: executable.parent.path);
        unawaited(process.stdout.drain<void>());
        unawaited(process.stderr.drain<void>());
        expect(
          await process.exitCode.timeout(
            const Duration(seconds: 15),
            onTimeout: () async {
              process.kill();
              return process.exitCode;
            },
          ),
          0,
        );
        final response = jsonDecode(
          await File('${directory.path}/response.json').readAsString(),
        );
        expect(response, {'pages': 1});
      },
    );
    test(
      'Tempo limite encerra o processo e libera nova consulta antes do envio',
      () async {
        final adapter = WindowsPrinterAdapter(executable: executable.path);
        final installed = await adapter.queues();
        var missing = 'Fila fictícia de regressão';
        while (installed.contains(missing)) {
          missing = '${missing}_';
        }
        final target = PrintTarget(missing, PrinterFormat.ticket, roll, 1);
        final timedOut = await adapter.printJob(
          target,
          printTest(),
          Duration.zero,
        );
        expect(timedOut.status, PrintStatus.queueUnavailable);
        expect(timedOut.detail, contains('Tempo limite'));
        final retry = await adapter.printJob(
          target,
          printTest(),
          const Duration(seconds: 12),
        );
        expect(retry.status, PrintStatus.queueMissing);
      },
    );
  }
}
