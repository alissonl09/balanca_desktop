import 'dart:io';

import 'package:balanca_desktop/app/balanca_app.dart';
import 'package:balanca_desktop/core/theme/app_colors.dart';
import 'package:balanca_desktop/core/widgets/visual_components.dart';
import 'package:balanca_desktop/features/configuracoes/configuracoes_page.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';
import 'package:balanca_desktop/features/configuracoes/settings_widgets.dart';
import 'package:balanca_desktop/features/relatorios/report_catalog.dart';
import 'package:balanca_desktop/features/relatorios/relatorios_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder key(String value) => find.byKey(ValueKey(value));
SettingsState state(WidgetTester tester) =>
    tester.widget<ConfiguracoesPage>(find.byType(ConfiguracoesPage)).settings;

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String field, String value) async {
  await tester.ensureVisible(key(field));
  await tester.pumpAndSettle();
  await tester.enterText(key(field), value);
  await tester.pumpAndSettle();
}

Future<void> dropdown(WidgetTester tester, String field, String option) async {
  await tap(tester, key(field));
  if (find.text(option).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(option),
      150,
      scrollable: find.byType(Scrollable).last,
    );
  } else {
    await tester.ensureVisible(find.text(option).last);
  }
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> open(
  WidgetTester tester, {
  String menu = 'config',
  Size size = const Size(1366, 768),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const BalancaApp());
  await tester.pumpAndSettle();
  await tap(tester, key('menu-$menu'));
}

Finder toggle(String label) => find.byWidgetPredicate(
  (widget) => widget is SettingsToggle && widget.label == label,
);

void main() {
  setUpAll(() async {
    if (Platform.isWindows) {
      final fonts = FontLoader('Arial');
      for (final name in ['arial.ttf', 'arialbd.ttf']) {
        fonts.addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/$name',
              ).readAsBytesSync(),
            ),
          ),
        );
      }
      await fonts.load();
    }
  });

  testWidgets('Placa e Carreta compartilham rótulo, inclusive com bitrem', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const BalancaApp());
    await tester.pumpAndSettle();
    void expectVehicleBoxHeights() {
      final plate = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == 'ABC1D23',
      );
      final inputs = find.byType(TextField);
      final plateInput = plate.evaluate().isEmpty ? inputs.first : plate;
      final trailerInput =
          find.byType(DropdownButtonFormField<String>).evaluate().isNotEmpty
          ? find.byType(DropdownButtonFormField<String>)
          : inputs.at(1);
      Size visibleBox(Finder input) {
        final decorator = find
            .descendant(of: input, matching: find.byType(InputDecorator))
            .first;
        final content = find
            .descendant(
              of: decorator,
              matching: find.byWidgetPredicate(
                (w) => w is Text || w is EditableText,
              ),
            )
            .first;
        return InputDecorator.containerOf(tester.element(content))!.size;
      }

      expect(visibleBox(trailerInput).height, visibleBox(plateInput).height);
      expect(
        tester.getSize(trailerInput).height,
        tester.getSize(plateInput).height,
      );
    }

    expectVehicleBoxHeights();
    Text label(String name) => tester.widget<Text>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is VisualFieldLabel && widget.label == name,
        ),
        matching: find.byType(Text),
      ),
    );
    expect(label('Carreta').style, label('Placa').style);
    final plateLabel = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is VisualFieldLabel && widget.label == 'Placa',
      ),
    );
    final trailerLabel = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is VisualFieldLabel && widget.label == 'Carreta',
      ),
    );
    expect(plateLabel.height, trailerLabel.height);
    await tester.enterText(find.byType(TextField).first, 'ABC1D23');
    await tap(tester, find.byTooltip('Consultar placa'));
    expectVehicleBoxHeights();
    expect(label('Carreta').style, label('Placa').style);
    await tap(tester, find.byTooltip('Limpar consulta'));
    await tester.enterText(find.byType(TextField).first, 'DEF2E34');
    await tap(tester, find.byTooltip('Consultar placa'));
    expectVehicleBoxHeights();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).readOnly,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Unidade, Ambiente, aba SGV condicional e estado conservado no menu',
    (tester) async {
      await open(tester);
      expect(key('settings-tab-vehicles'), findsNothing);
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(key('station-unit'))
            .initialValue,
        4,
      );
      final environments = tester
          .widget<DropdownButton<StationEnvironment>>(
            find.descendant(
              of: key('station-environment'),
              matching: find.byType(DropdownButton<StationEnvironment>),
            ),
          )
          .items!;
      expect(environments.map((item) => item.value), StationEnvironment.values);
      await dropdown(tester, 'station-unit', '1 - MATRIZ');
      await dropdown(tester, 'station-environment', 'Produção');
      expect(state(tester).unitCode, 1);
      expect(state(tester).environment, StationEnvironment.producao);
      await tap(tester, key('sgv-integration'));
      expect(key('settings-tab-vehicles'), findsOneWidget);
      await tap(tester, key('settings-tab-vehicles'));
      expect(key('entry-barrier'), findsNothing);
      expect(key('ocr-address'), findsNothing);
      await tap(tester, key('barriers-enabled'));
      await dropdown(tester, 'entry-barrier', 'Cancela Entrada 01 (simulada)');
      await dropdown(tester, 'exit-barrier', 'Cancela Saída 01 (simulada)');
      await tap(tester, toggle('Semáforo'));
      await tap(tester, toggle('Display de Informações'));
      await tap(tester, toggle('Serviço de Voz'));
      expect(state(tester).entryBarrierId, 'entrada-01');
      expect(state(tester).exitBarrierId, 'saida-01');
      expect(state(tester).trafficLight, isTrue);
      expect(state(tester).informationDisplay, isTrue);
      expect(state(tester).voice, isTrue);
      await tap(tester, key('barriers-enabled'));
      expect(key('entry-barrier'), findsNothing);
      await tap(tester, key('settings-tab-general'));
      await tap(tester, key('sgv-integration'));
      expect(key('settings-tab-vehicles'), findsNothing);
      await tap(tester, key('menu-cadastros'));
      await tap(tester, key('menu-config'));
      expect(state(tester).unitCode, 1);
      expect(state(tester).environment, StationEnvironment.producao);
      expect(state(tester).integratedSgv, isFalse);
      expect(state(tester).voice, isTrue);
      await tap(tester, key('settings-tab-indicators'));
      expect(find.text('Indicadores de Peso'), findsNWidgets(2));
      await tap(tester, key('settings-tab-models'));
      expect(find.text('Modelos de Indicadores'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('OCR valida porta TCP e protege o token', (tester) async {
    await open(tester);
    await tap(tester, key('sgv-integration'));
    await tap(tester, key('settings-tab-vehicles'));
    await tap(tester, key('ocr-enabled'));
    await fill(tester, 'ocr-address', 'ocr.local');
    await fill(tester, 'ocr-port', '99999');
    await fill(tester, 'ocr-token', 'token-local-de-teste');
    Finder tokenField() =>
        find.descendant(of: key('ocr-token'), matching: find.byType(TextField));
    expect(tester.widget<TextField>(tokenField()).obscureText, isTrue);
    await tap(tester, find.byTooltip('Exibir token'));
    expect(tester.widget<TextField>(tokenField()).obscureText, isFalse);
    await tap(tester, find.byTooltip('Ocultar token'));
    await tap(tester, key('save-settings'));
    expect(find.text('Informe uma porta de 1 a 65535.'), findsOneWidget);
    await fill(tester, 'ocr-port', '65535');
    await tap(tester, key('save-settings'));
    expect(
      find.textContaining('Configurações mantidas somente nesta sessão.'),
      findsOneWidget,
    );
    expect(state(tester).ocrPort, 65535);
    await tap(tester, key('ocr-enabled'));
    expect(key('ocr-token'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Impressoras simuladas, papel por impressora e contingência A4', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, key('settings-tab-printing'));
    await dropdown(tester, 'printer-selection', 'Ticket Rede (simulada)');
    expect(find.text('Offline (simulado)'), findsOneWidget);
    expect(find.text('192.168.1.50'), findsOneWidget);
    await dropdown(tester, 'printer-selection', 'A4 USB (simulada)');
    expect(find.text('USB002'), findsOneWidget);
    await dropdown(tester, 'paper-size-a4-usb', 'Carta');
    await dropdown(tester, 'paper-source-a4-usb', 'Alimentação manual');
    await dropdown(tester, 'paper-orientation-a4-usb', 'Paisagem');
    await dropdown(tester, 'printer-selection', 'Ticket USB (simulada)');
    expect(find.text('USB001'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(key('paper-size-ticket-usb'))
          .initialValue,
      'Bobina 80 mm',
    );
    await dropdown(tester, 'printer-selection', 'A4 USB (simulada)');
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(key('paper-size-a4-usb'))
          .initialValue,
      'Carta',
    );
    expect(
      state(tester).printing.paperByPrinter['a4-usb']!.orientation,
      PaperOrientation.landscape,
    );
    await dropdown(tester, 'fallback-printer', 'A4 Rede (simulada)');
    expect(state(tester).printing.fallbackPrinterId, 'a4-rede');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Impressão limita cópias e três linhas, compartilha textos nas prévias e restaura imagem',
    (tester) async {
      await open(tester);
      await tap(tester, key('settings-tab-printing'));
      expect(find.text('0/3 linhas'), findsNWidgets(2));
      await fill(tester, 'ticket-copies', '0');
      await tap(tester, key('save-settings'));
      expect(find.text('Informe de 1 a 10 cópias.'), findsOneWidget);
      await fill(tester, 'ticket-copies', '11');
      await tap(tester, key('save-settings'));
      expect(find.text('Informe de 1 a 10 cópias.'), findsOneWidget);
      await fill(tester, 'ticket-copies', '2');
      await fill(tester, 'ticket-header', 'Linha 1\nLinha 2\nLinha 3\nLinha 4');
      await fill(
        tester,
        'ticket-footer',
        'Rodapé 1\r\nRodapé 2\r\nRodapé 3\r\nRodapé 4',
      );
      expect(state(tester).printing.header, 'Linha 1\nLinha 2\nLinha 3');
      expect(state(tester).printing.footer, 'Rodapé 1\nRodapé 2\nRodapé 3');
      expect(find.text('3/3 linhas'), findsNWidgets(2));
      await tap(tester, toggle('Entrada'));
      await tap(tester, toggle('Saída'));
      await tap(tester, toggle('Ticket Windows'));
      expect(state(tester).printing.emitEntry, isFalse);
      expect(state(tester).printing.emitExit, isFalse);
      expect(state(tester).printing.windowsTicket, isTrue);
      await tap(tester, find.text('Alterar imagem'));
      await tap(tester, find.text('Imagem de demonstração'));
      expect(state(tester).printing.logo, TicketLogo.demonstration);
      for (final format in ['Ticket', 'A4']) {
        await tap(tester, find.text('Visualizar $format'));
        expect(key('print-layout-preview'), findsOneWidget);
        expect(
          find.descendant(
            of: key('print-layout-preview'),
            matching: find.text('Linha 1\nLinha 2\nLinha 3'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: key('print-layout-preview'),
            matching: find.text('Rodapé 1\nRodapé 2\nRodapé 3'),
          ),
          findsOneWidget,
        );
        expect(find.text('Fechar').hitTestable(), findsOneWidget);
        await tap(tester, find.text('Fechar'));
      }
      await tap(tester, find.text('Restaurar padrão'));
      expect(state(tester).printing.logo, TicketLogo.standard);
      await tap(tester, key('save-settings'));
      expect(
        find.textContaining('Configurações mantidas somente nesta sessão.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Menu e nove relatórios com filtros locais, sem geração fictícia',
    (tester) async {
      await open(tester, menu: 'relatorios');
      expect(find.byType(RelatoriosPage), findsOneWidget);
      expect(
        tester.getRect(key('menu-cadastros')).top,
        lessThan(tester.getRect(key('menu-relatorios')).top),
      );
      expect(
        tester.getRect(key('menu-relatorios')).top,
        lessThan(tester.getRect(key('menu-config')).top),
      );
      final reportIcon = find.descendant(
        of: key('menu-relatorios'),
        matching: find.byIcon(Icons.assessment_outlined),
      );
      expect(tester.widget<Icon>(reportIcon).color, AppColors.green);
      expect(reportCatalog, hasLength(9));
      for (final report in reportCatalog) {
        await tap(tester, key('report-${report.id}'));
        expect(find.text('Resultados'), findsOneWidget);
        final generate = find.widgetWithText(ElevatedButton, 'Gerar relatório');
        expect(tester.widget<ElevatedButton>(generate).onPressed, isNull);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Imprimir'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Exportar'),
              )
              .onPressed,
          isNull,
        );
      }
      await tap(tester, key('report-motoristas'));
      await fill(tester, 'filter-motoristas-driver', 'João da Silva');
      await tap(tester, key('report-pesagens'));
      await dropdown(tester, 'filter-pesagens-unit', '4 - JAPY (simulada)');
      await dropdown(tester, 'filter-pesagens-status', 'Em aberto');
      await tap(tester, key('filter-pesagens-startDate-'));
      await tap(tester, find.text('Selecionar'));
      await tap(tester, key('report-motoristas'));
      expect(
        tester
            .widget<TextFormField>(key('filter-motoristas-driver'))
            .initialValue,
        'João da Silva',
      );
      await tap(tester, key('menu-config'));
      expect(tester.widget<Icon>(reportIcon).color, Colors.white);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(1920, 1080),
    const Size(1366, 768),
    const Size(800, 700),
  ]) {
    testWidgets('Configurações e Relatórios sem overflow em $size', (
      tester,
    ) async {
      await open(tester, size: size);
      await tap(tester, key('settings-tab-printing'));
      await fill(tester, 'ticket-header', 'Cabeçalho');
      await tap(tester, key('save-settings'));
      await tap(tester, find.text('Visualizar A4'));
      final preview = tester.getRect(key('print-layout-preview'));
      expect(preview.left, greaterThanOrEqualTo(0));
      expect(preview.right, lessThanOrEqualTo(size.width));
      expect(preview.bottom, lessThanOrEqualTo(size.height));
      await tap(tester, find.text('Fechar'));
      await tap(tester, key('menu-relatorios'));
      await tap(tester, key('report-pesagens'));
      expect(find.text('Resultados'), findsOneWidget);
      final page = tester.getRect(key('reports-main-card'));
      expect(page.left, greaterThanOrEqualTo(0));
      expect(page.right, lessThanOrEqualTo(size.width));
      expect(tester.takeException(), isNull);
    });
  }
}
