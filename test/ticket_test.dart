import 'dart:io';

import 'package:balanca_desktop/core/widgets/visual_components.dart';

import 'package:balanca_desktop/app/balanca_app.dart';
import 'package:balanca_desktop/features/configuracoes/configuracoes_page.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';
import 'package:balanca_desktop/features/pesagem/weighing_preview.dart';
import 'package:balanca_desktop/features/ticket/a4_ticket.dart';
import 'package:balanca_desktop/features/ticket/thermal_ticket.dart';
import 'package:balanca_desktop/features/ticket/ticket_mapper.dart';
import 'package:balanca_desktop/features/ticket/ticket_mock_data.dart';
import 'package:balanca_desktop/features/ticket/ticket_pesagem.dart';
import 'package:balanca_desktop/features/ticket/ticket_sections.dart';
import 'package:balanca_desktop/features/ticket/ticket_session.dart';
import 'package:balanca_desktop/features/ticket/ticket_traceability.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final emitted = DateTime(2026, 2, 10, 15, 35);

TicketSession session({
  WeighingSummary summary = const WeighingSummary(),
  String trailer = '',
  Map<String, String> operation = const {},
}) => TicketSession()
  ..current = WeighingPreview(
    plate: 'ABC1D23',
    trailer: trailer,
    operation: operation,
    currentWeight: 0,
    summary: summary,
  );

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> render(
  WidgetTester tester,
  TicketPesagem ticket, {
  bool a4 = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: a4 ? 720 : 340,
            child: a4
                ? A4Ticket(ticket: ticket)
                : ThermalTicket(ticket: ticket),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    if (Platform.isWindows) {
      final fonts = FontLoader('Arial');
      for (final file in ['arial.ttf', 'arialbd.ttf']) {
        fonts.addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/$file',
              ).readAsBytesSync(),
            ),
          ),
        );
      }
      await fonts.load();
    }
  });

  test('Abertura não inventa saída, líquido, data ou dados sem fonte', () {
    final source = session(
      summary: const WeighingSummary(first: 32000),
      operation: {'Item': 'Integração futura'},
    );
    final ticket = ticketFromSession(
      source,
      SettingsState(),
      issuedAt: emitted,
    );
    expect(ticket.ticketNumber, '318875');
    expect(ticket.firstWeight, 32000);
    expect(ticket.secondWeight, isNull);
    expect(ticket.netWeight, isNull);
    expect(ticket.firstWeighedAt, isNull);
    expect(ticket.secondWeighedAt, isNull);
    expect(ticket.isClosing, isFalse);
    expect(ticket.product, isNull);
    expect(ticket.sender, isNull);
    expect(ticket.recipient, isNull);
    expect(ticket.city, isNull);
    expect(ticket.uf, isNull);
    expect(ticket.quantity, isNull);
    expect(ticket.operationReference, isNull);
    expect(ticket.operatorName, isNull);
    expect(ticket.trailerPlate, isNull);
    expect(ticket.issuedAt, emitted);
  });

  test(
    'Fechamento preserva as duas pesagens e o líquido calculado no estado',
    () {
      const first = 32000.0, second = 12500.0;
      final at1 = DateTime(2026, 2, 10, 9), at2 = DateTime(2026, 2, 10, 10);
      final source = session(
        trailer: 'DEF4G56',
        summary: WeighingSummary(
          first: first,
          second: second,
          net: first - second,
          dry: 19000,
          firstWeighedAt: at1,
          secondWeighedAt: at2,
        ),
      );
      final ticket = ticketFromSession(
        source,
        SettingsState(),
        issuedAt: emitted,
      );
      expect(ticket.isClosing, isTrue);
      expect(ticket.firstWeight, first);
      expect(ticket.secondWeight, second);
      expect(ticket.firstWeighedAt, at1);
      expect(ticket.secondWeighedAt, at2);
      expect(ticket.netWeight, 19500);
      expect(ticketWeight(ticket.netWeight!), '19.500 Kg');
      expect(ticketWeight(1234.5), '1.234,5 Kg');
      expect(ticket.dryWeight, 19000);
      expect(ticket.trailerPlate, 'DEF4G56');
      expect(ticket.issuedAt, isNot(ticket.secondWeighedAt));
    },
  );

  test('Documento, emissores, observação e configurações são mapeados sem perder valores', () {
    final settings = SettingsState();
    settings.printing.header =
        'Cabeçalho 1\nCabeçalho 2\nCabeçalho 3\nIgnorar 4';
    settings.printing.footer = 'Rodapé';
    settings.printing.logo = TicketLogo.demonstration;
    final source = session(
      operation: {
        'Nº Nota(s) / Documento(s)': 'DOC-A; DOC-B\nDOC-C',
        'Tipo do documento': 'Nota Fiscal',
        'Emissor(es)': 'Emissor A; Emissor B',
        'Transportador': 'Transportador Atual',
        'Motorista': 'Motorista Atual',
        'Depósito': 'Depósito Atual',
        'Embalagem': 'Granel',
        'Peso N.F. (Kg)': '28.450,5',
        'Observação': 'Texto livre\nSegunda linha',
        'Operador': 'Operador disponível',
      },
    );
    final ticket = ticketFromSession(source, settings, issuedAt: emitted);
    expect(ticket.documents, ['DOC-A', 'DOC-B', 'DOC-C']);
    expect(ticket.issuers, ['Emissor A', 'Emissor B']);
    expect(ticket.carrier, 'Transportador Atual');
    expect(ticket.driver, 'Motorista Atual');
    expect(ticket.depot, 'Depósito Atual');
    expect(ticket.packaging, 'Granel');
    expect(ticket.invoiceWeight, 28450.5);
    expect(ticket.observation, 'Texto livre\nSegunda linha');
    expect(ticket.operatorName, 'Operador disponível');
    expect(ticket.branding.headerLines, [
      'Cabeçalho 1',
      'Cabeçalho 2',
      'Cabeçalho 3',
    ]);
    expect(ticket.branding.footerLines, ['Rodapé']);
    expect(ticket.branding.logo, TicketLogoKind.demonstration);
    expect(() => ticket.documents.add('outro'), throwsUnsupportedError);
  });

  test('Captura manual confirmada mantém autoria e data distintas da emissão, sem calcular líquido', () {
    final capturedAt = DateTime(2026, 2, 10, 12);
    final source = session(summary: const WeighingSummary(first: 32000));
    source.confirmed = WeighingPreview(
      plate: 'ABC1D23',
      trailer: '',
      operation: const {},
      currentWeight: 12500,
      summary: const WeighingSummary(first: 32000),
      capturedAt: capturedAt,
      manualOperator: 'balanca',
      manualJustification: 'Justificativa já disponível no estado',
    );
    final ticket = ticketFromSession(
      source,
      SettingsState(),
      issuedAt: emitted,
    );
    expect(ticket.captureType, TicketCaptureType.manual);
    expect(ticket.secondWeight, 12500);
    expect(ticket.secondWeighedAt, capturedAt);
    expect(ticket.manualAuthorizer, 'balanca');
    expect(ticket.manualJustification, 'Justificativa já disponível no estado');
    expect(
      ticket.operatorName,
      isNull,
    ); // Autorizador não é automaticamente operador.
    expect(ticket.netWeight, isNull); // O estado ainda não calculou esse peso.
    expect(ticket.issuedAt, emitted);
  });

  test('Captura de outra composição não contamina o ticket e indicador desconectado não vira peso real', () {
    final source = session();
    source.confirmed = WeighingPreview(
      plate: 'ABC1D23',
      trailer: 'OUT9A99',
      operation: const {},
      currentWeight: 9999,
      summary: const WeighingSummary(),
      capturedAt: emitted,
      manualOperator: 'balanca',
    );
    final ticket = ticketFromSession(
      source,
      SettingsState(),
      issuedAt: emitted,
    );
    expect(ticket.firstWeight, isNull);
    expect(ticket.captureType, TicketCaptureType.automatic);
    source.confirmed = WeighingPreview(
      plate: 'ABC1D23',
      trailer: '',
      operation: const {},
      currentWeight: 0,
      summary: const WeighingSummary(),
    );
    expect(ticketFromSession(source, SettingsState()).firstWeight, isNull);
  });

  test('Identificador é substituível e Code 39 possui delimitadores e zonas de silêncio', () {
    final source = session();
    expect(ticketFromSession(source, SettingsState()).traceabilityId, '318875');
    expect(
      ticketFromSession(
        source,
        SettingsState(),
        identifierFactory: (number) => 'TEST-$number',
      ).traceabilityId,
      'TEST-318875',
    );
    final modules = encodeCode39('318875');
    expect(modules.take(10), everyElement(isFalse));
    expect(modules.skip(modules.length - 10), everyElement(isFalse));
    expect(modules.where((module) => module), isNotEmpty);
    // Code 39: três segmentos largos de razão 3:1 em nove segmentos por símbolo.
    // Cada símbolo ocupa 15 módulos; dois delimitadores e espaços entre símbolos.
    expect(modules.length, (6 + 2) * 15 + 7 + 20);
    expect(
      modules.sublist(10, 25),
      modules.sublist(modules.length - 25, modules.length - 10),
    );
    expect(() => encodeCode39('inválido'), throwsFormatException);
  });

  for (final a4 in [false, true]) {
    testWidgets(
      '${a4 ? 'A4' : 'Térmico'}: abertura/fechamento, carreta opcional e identificação manual',
      (tester) async {
        final examples = ticketPreviewExamples(TicketBranding(), emitted);
        await render(tester, examples[0], a4: a4);
        expect(find.text('ABERTURA DE PESO'), findsOneWidget);
        expect(find.text('Peso Final'), findsNothing);
        expect(find.text('Placa Carreta'), findsNothing);
        expect(find.text('32.000 Kg'), findsOneWidget);
        await render(tester, examples[1], a4: a4);
        expect(find.text('FECHAMENTO DE PESO'), findsOneWidget);
        expect(find.text('Peso Inicial'), findsOneWidget);
        expect(find.text('Peso Final'), findsOneWidget);
        expect(find.text('Placa Carreta'), findsOneWidget);
        expect(find.text('MCK2B34'), findsOneWidget);
        expect(find.text('19.500 Kg'), findsOneWidget);
        expect(find.byKey(const ValueKey('ticket-barcode')), findsOneWidget);
        await render(tester, examples[2], a4: a4);
        expect(find.text('Pesagem Manual'), findsOneWidget);
        expect(find.text('Autorizado por: usuário-demo'), findsOneWidget);
        expect(find.textContaining('Justificativa:'), findsOneWidget);
        expect(find.text('BALANÇA / AUTOMÁTICA'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${a4 ? 'A4' : 'Térmico'}: texto longo quebra linhas integralmente sem reticências',
      (tester) async {
        final longText =
            'Transportadora com identificação extensa e conteúdo integral para conferência. ' *
            12;
        final ticket = TicketPesagem(
          ticketNumber: 'TEST-LONG',
          carrier: longText,
          documents: ['DOC-${'1' * 100}', 'DOC-B'],
          issuers: [longText],
          observation: '$longText\nSegunda linha completa.',
          issuedAt: emitted,
          captureType: TicketCaptureType.automatic,
          branding: TicketBranding(),
        );
        await render(tester, ticket, a4: a4);
        expect(find.text(longText), findsNWidgets(2));
        for (final finder in [
          find.text(longText).first,
          find.text(longText).last,
        ]) {
          final text = tester.widget<Text>(finder);
          expect(text.maxLines, isNull);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(tester.getSize(finder).height, greaterThan(200));
          expect(
            tester.getSize(finder).width,
            lessThanOrEqualTo(a4 ? 308 : 300),
          );
        }
        expect(find.text('$longText\nSegunda linha completa.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Preview usa placa/carreta/observação e captura manual da sessão atual nos dois formatos',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1366, 768);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const BalancaApp());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'ABC1D23');
      await tapVisible(tester, find.byTooltip('Consultar placa'));
      await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
      await tapVisible(tester, find.text('DEF4G56').last);
      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is VisualField && w.label == 'Observação',
          ),
          matching: find.byType(TextField),
        ),
        'Observação atual para o comprovante',
      );
      await tapVisible(tester, find.text('Peso Manual'));
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
        'Leitura manual para teste do ticket',
      );
      await tapVisible(tester, find.text('Liberar'));
      await tester.enterText(
        find.byKey(const ValueKey('manual-weight')),
        '10000',
      );
      await tapVisible(tester, find.text('Prosseguir'));
      await tapVisible(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('weighing-confirmation')),
          matching: find.text('Salvar Pesagem'),
        ),
      );
      await tapVisible(tester, find.byKey(const ValueKey('menu-config')));
      await tapVisible(
        tester,
        find.byKey(const ValueKey('settings-tab-printing')),
      );
      for (final format in ['Ticket', 'A4']) {
        await tapVisible(tester, find.text('Visualizar $format'));
        final preview = find.byKey(const ValueKey('print-layout-preview'));
        expect(
          find.descendant(of: preview, matching: find.text('ABC1D23')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: preview, matching: find.text('DEF4G56')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: preview,
            matching: find.text('Observação atual para o comprovante'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: preview, matching: find.text('10.000 Kg')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: preview, matching: find.text('Pesagem Manual')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: preview,
            matching: find.text('Autorizado por: balanca'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: preview, matching: find.text('Peso Final')),
          findsNothing,
        );
        final ticket = format == 'Ticket'
            ? tester.widget<ThermalTicket>(find.byType(ThermalTicket)).ticket
            : tester.widget<A4Ticket>(find.byType(A4Ticket)).ticket;
        expect(ticket.issuedAt.isBefore(ticket.firstWeighedAt!), isFalse);
        expect(
          ticket.manualJustification,
          'Leitura manual para teste do ticket',
        );
        await tapVisible(tester, find.text('Fechar'));
      }
      final saved = tester
          .widget<ConfiguracoesPage>(find.byType(ConfiguracoesPage))
          .ticketSession;
      expect(saved.current!.plate, 'ABC1D23');
      await tapVisible(tester, find.byKey(const ValueKey('menu-balanca_icon')));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).readOnly,
        isTrue,
      );
      expect(find.text('Observação atual para o comprovante'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('Limpar consulta'));
      expect(saved.confirmed, isNull);
      expect(saved.current!.plate, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
