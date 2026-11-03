import 'dart:io';

import 'package:balanca_desktop/core/permissions/permission_models.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/app/balanca_app.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_page.dart';
import 'package:balanca_desktop/features/configuracoes/configuracoes_page.dart';
import 'package:balanca_desktop/features/cadastros/cadastros_page.dart';
import 'package:balanca_desktop/core/theme/app_colors.dart';
import 'package:balanca_desktop/core/widgets/visual_components.dart';
import 'package:balanca_desktop/core/widgets/read_only_value_field.dart';
import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/features/pesagem/weighing_preview.dart';
import 'package:balanca_desktop/features/pesagem/weighing_dialogs.dart';

Future<void> tapAction(WidgetTester tester, String label) async {
  final button = find.text(label).last;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // Ahem, a fonte padrão do tester, tem métricas diferentes das do Windows.
    // Valida-se o layout desktop com a mesma Arial usada pela aplicação.
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
  for (final size in [
    const Size(1920, 1080),
    const Size(1600, 900),
    const Size(1366, 768),
    const Size(1366, 700),
    const Size(1280, 680),
    const Size(1280, 720),
    const Size(900, 700),
    const Size(600, 800),
  ]) {
    testWidgets('Layout e navegação em ${size.width} x ${size.height}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const BalancaApp());
      await tester.pumpAndSettle();
      expect(find.byType(PesagemPage), findsOneWidget);
      expect(find.text('Veículos em Operação'), findsOneWidget);
      expect(find.text('Indicador desconectado'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('pesagem-action-salvar')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('318875'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TextField).first).height,
        greaterThanOrEqualTo(34),
      );
      if (size.width >= 1280) {
        expect(find.text('F12'), findsOneWidget);
        expect(find.text('Observação'), findsOneWidget);
      }
      // Verifica os limites dos painéis visíveis. O conteúdo lateral pode
      // rolar dentro da coluna em resoluções mais baixas.
      for (final key in ['pesagem-main-scroll', 'pesagem-side-panel']) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.top, greaterThanOrEqualTo(0), reason: key);
        expect(
          rect.bottom,
          lessThanOrEqualTo(size.height),
          reason: '$key em $size',
        );
        if (size.width >= 1280) {
          expect(rect.left, greaterThanOrEqualTo(0), reason: key);
          expect(rect.right, lessThanOrEqualTo(size.width), reason: key);
        }
      }
      final pageScrollViews = find.descendant(
        of: find.byType(PesagemPage),
        matching: find.byType(SingleChildScrollView),
      );
      for (final scroll in tester.widgetList<SingleChildScrollView>(
        pageScrollViews,
      )) {
        if (scroll.key != const ValueKey('pesagem-side-panel') &&
            scroll.key != const ValueKey('pesagem-main-scroll')) {
          expect(scroll.scrollDirection, Axis.horizontal);
        }
      }
      expect(
        find.ancestor(
          of: find.byType(PesagemPage),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      expect(find.text('Veículos'), findsNothing);
      final cadastrosMenu = find.byKey(const ValueKey('menu-cadastros'));
      final cadastrosIcon = find.descendant(
        of: cadastrosMenu,
        matching: find.byIcon(Icons.badge_outlined),
      );
      expect(tester.widget<Icon>(cadastrosIcon).color, Colors.white);
      await tester.tap(cadastrosMenu);
      await tester.pumpAndSettle();
      expect(find.byType(CadastrosPage), findsOneWidget);
      expect(find.byType(PesagemPage), findsNothing);
      expect(tester.widget<Icon>(cadastrosIcon).color, AppColors.green);
      expect(
        tester.widget<Icon>(cadastrosIcon).size,
        size.width <= 900 ? 28 : 34,
      );
      final cadastrosRect = tester.getRect(
        find.byKey(const ValueKey('cadastros-main-card')),
      );
      expect(cadastrosRect.left, greaterThanOrEqualTo(0));
      expect(cadastrosRect.right, lessThanOrEqualTo(size.width));
      expect(cadastrosRect.bottom, lessThanOrEqualTo(size.height));
      final tabBar = find.byKey(const ValueKey('cadastros-tabs'));
      expect(tester.widget<TabBar>(tabBar).isScrollable, isTrue);
      expect(tester.widget<TabBar>(tabBar).tabs, hasLength(7));
      for (final label in [
        'Remetentes / Destinatários',
        'Transportadoras',
        'Motoristas',
        'Placas',
        'Operações',
        'Itens / Produtos',
        'Unidades',
      ]) {
        final tab = find.descendant(of: tabBar, matching: find.text(label));
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(find.text('Cadastro de $label'), findsOneWidget);
        final provisional = [
          'Operações',
          'Itens / Produtos',
          'Unidades',
        ].contains(label);
        expect(
          find.text(
            'Os campos deste cadastro serão definidos em uma próxima etapa.',
          ),
          provisional ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(TextField),
          provisional ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('menu-config')));
      await tester.pumpAndSettle();
      expect(find.byType(ConfiguracoesPage), findsOneWidget);
      expect(find.byType(CadastrosPage), findsNothing);
      expect(tester.widget<Icon>(cadastrosIcon).color, Colors.white);
      expect(find.text('Unidade da balança'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('menu-balanca_icon')));
      await tester.pumpAndSettle();
      expect(find.byType(PesagemPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Nova Pesagem limpa a placa sem conectar ou consultar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const BalancaApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ABC1D23');
    await tapAction(tester, 'Nova Pesagem');
    await tester.pump();
    expect(find.text('ABC1D23'), findsNWidgets(2)); // Bitrem na lista simulada.
    expect(find.text('Indicador desconectado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Consulta por TAB, seleção do bitrem e limpeza', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const BalancaApp());
    await tester.pumpAndSettle();
    final plate = find.byType(TextField).first;
    await tester.enterText(plate, 'abc1d23');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(plate).readOnly, isTrue);
    expect(tester.widget<TextField>(plate).controller!.text, 'ABC1D23');
    final trailers = find.byType(DropdownButtonFormField<String>);
    expect(trailers, findsOneWidget);
    await tester.tap(trailers);
    await tester.pumpAndSettle();
    await tester.tap(find.text('XYZ9H87').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: trailers, matching: find.text('XYZ9H87')),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is VisualField && widget.label == 'Observação',
        ),
        matching: find.byType(TextField),
      ),
      'Observação livre',
    );
    await tester.tap(find.byTooltip('Limpar consulta'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(plate).readOnly, isFalse);
    expect(tester.widget<TextField>(plate).controller!.text, isEmpty);
    expect(trailers, findsNothing);
    expect(find.text('Observação livre'), findsNothing);
    expect(find.byTooltip('Consultar placa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Consulta por lupa e ENTER, carreta única e filtro local', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const BalancaApp());
    await tester.pumpAndSettle();
    final plate = find.byType(TextField).first;
    final trailer = find.byType(TextField).at(1);
    await tester.enterText(trailer, 'AAA1234');
    expect(tester.widget<TextField>(trailer).readOnly, isFalse);
    await tester.enterText(plate, 'ABC');
    await tester.tap(find.byTooltip('Consultar placa'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(plate).readOnly, isFalse);
    await tester.enterText(plate, 'ZZZ9999');
    await tester.tap(find.byTooltip('Consultar placa'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(plate).readOnly, isFalse);
    await tester.enterText(plate, 'DEF2E34');
    await tester.tap(find.byTooltip('Consultar placa'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(plate).readOnly, isTrue);
    expect(tester.widget<TextField>(trailer).controller!.text, 'GHI5J67');
    await tapAction(tester, 'Nova Pesagem');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(trailer).controller!.text, isEmpty);
    await tester.enterText(plate, 'DEF2E34');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(plate).readOnly, isTrue);
    final search = find.byKey(const ValueKey('operation-search'));
    await tester.enterText(search, 'xyz9h87');
    await tester.pumpAndSettle();
    expect(find.text('09:14'), findsOneWidget);
    expect(find.text('09:12'), findsNothing);
    await tester.enterText(search, 'ZZZ');
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma operação encontrada.'), findsOneWidget);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(find.text('09:12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> openPage(
    WidgetTester tester, {
    Size size = const Size(1366, 768),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const BalancaApp());
    await tester.pumpAndSettle();
  }

  testWidgets('Cabeçalho global e menu mock do usuário', (tester) async {
    await openPage(tester);
    expect(find.text('Sistema de Gerenciamento de Pesagens'), findsOneWidget);
    expect(find.text('Alisson Rodrigues Romano'), findsNothing);
    expect(find.byTooltip('Notificações'), findsNothing);
    expect(find.byKey(const ValueKey('station-connectivity')), findsOneWidget);

    final menu = find.byKey(const ValueKey('user-menu'));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Alisson Romano'), findsNWidgets(2));
    expect(find.text('Operador'), findsAtLeastNWidgets(2));
    expect(find.byIcon(Icons.switch_account_outlined), findsOneWidget);
    expect(find.byIcon(Icons.logout_outlined), findsOneWidget);
    expect(find.text('Trocar usuário'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    await tester.tap(find.text('Trocar usuário'));
    await tester.pumpAndSettle();
    expect(find.text('Trocar usuário: simulação local'), findsOneWidget);
    expect(find.text('Logout'), findsNothing);
    ScaffoldMessenger.of(tester.element(menu)).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(find.text('Deseja realmente sair do sistema?'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();
    expect(find.text('Logout: simulação local'), findsOneWidget);
    expect(find.byType(PesagemPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cards da Pesagem seguem em sequência sem vazio interno', (
    tester,
  ) async {
    await openPage(tester);
    final mainScroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('pesagem-main-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(mainScroll.position.maxScrollExtent, 0);
    final operation = tester.getRect(
      find.byKey(const ValueKey('pesagem-operation-card')),
    );
    final weights = tester.getRect(find.byKey(const ValueKey('weight-panels')));
    expect(weights.top - operation.bottom, inInclusiveRange(0, 8));
    final motorist = find.byWidgetPredicate(
      (widget) => widget is VisualField && widget.label == 'Motorista',
    );
    final plateField = find.byWidgetPredicate(
      (widget) => widget is VisualField && widget.label == 'Placa',
    );
    final trailerField = find.byWidgetPredicate(
      (widget) => widget is VisualField && widget.label == 'Carreta',
    );
    expect(tester.getSize(motorist).height, tester.getSize(plateField).height);
    expect(
      tester.getSize(motorist).height,
      tester.getSize(trailerField).height,
    );
    expect(find.text('Transportadora'), findsOneWidget);
    expect(find.text('Destino'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Grade ampla, placas iguais e quatro valores centralizados', (
    tester,
  ) async {
    await openPage(tester);
    final plate = find.byWidgetPredicate(
      (widget) => widget is VisualField && widget.label == 'Placa',
    );
    final trailer = find.byWidgetPredicate(
      (widget) => widget is VisualField && widget.label == 'Carreta',
    );
    expect(tester.getSize(plate).width, tester.getSize(trailer).width);
    Finder valueField(String label) => find.byWidgetPredicate(
      (widget) => widget is VisualField && widget.label == label,
    );
    expect(
      tester.getRect(valueField('Motorista')).left,
      lessThan(tester.getRect(valueField('Transportadora')).left),
    );
    for (final label in [
      'Motorista',
      'Transportadora',
      'Emissor(es)',
      'Depósito',
    ]) {
      expect(tester.getSize(valueField(label)).width, greaterThan(300));
    }
    for (final label in [
      'Pesagem 1',
      'Pesagem 2',
      'Peso Líquido',
      'Peso Seco',
    ]) {
      final card = tester.getRect(find.byKey(ValueKey('summary-card-$label')));
      final value = tester.getRect(
        find.byKey(ValueKey('summary-value-$label')),
      );
      expect(value.center.dx, closeTo(card.center.dx, 1));
      expect((value.center.dy - card.center.dy).abs(), lessThan(13));
      expect(value.height, greaterThan(28));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lista mantém cinco linhas, pesquisa fixa e altura estável', (
    tester,
  ) async {
    await openPage(tester);
    final area = find.byKey(const ValueKey('operation-list-area'));
    final list = find.byKey(const ValueKey('operation-list'));
    final search = find.byKey(const ValueKey('operation-search'));
    final areaBefore = tester.getRect(area);
    final searchBefore = tester.getRect(search);
    final panelBefore = tester.getRect(
      find.byKey(const ValueKey('pesagem-side-panel')),
    );
    expect(areaBefore.height, 150);
    expect(find.text('09:12').hitTestable(), findsOneWidget);
    expect(find.text('09:40').hitTestable(), findsNothing);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.maxScrollExtent, 60);
    await tester.drag(list, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('09:45').hitTestable(), findsOneWidget);
    expect(tester.getRect(search), searchBefore);
    expect(tester.getRect(area), areaBefore);
    await tester.enterText(search, 'PQR6J78');
    await tester.pumpAndSettle();
    expect(find.text('09:45').hitTestable(), findsOneWidget);
    expect(tester.getRect(area), areaBefore);
    expect(
      tester.getRect(find.byKey(const ValueKey('pesagem-side-panel'))),
      panelBefore,
    );
    await tester.enterText(search, 'ZZZ');
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma operação encontrada.'), findsOneWidget);
    expect(tester.getRect(area), areaBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Texto longo mostra indicador e diálogo copiável somente quando necessário',
    (tester) async {
      const longValue =
          'Transportadora Motoristas Autônomos de Cargas do Sul de Minas Gerais';
      Future<void> renderValue(String value, double width) => tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: ReadOnlyValueField(
                  label: 'Transportador',
                  value: value,
                  height: 36,
                  labelGap: 4,
                ),
              ),
            ),
          ),
        ),
      );
      await renderValue(longValue, 190);
      final more = find.byTooltip('Ver conteúdo completo: Transportador');
      expect(more, findsOneWidget);
      expect(
        tester.widget<Text>(find.text(longValue)).overflow,
        TextOverflow.ellipsis,
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        longValue,
      );
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      await renderValue(longValue, 850);
      expect(more, findsNothing);
      await renderValue('ABC', 190);
      expect(more, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('Classificação provisória contempla os quatro pesos', () {
    expect(const WeighingSummary().isClosing, isFalse);
    for (final summary in [
      const WeighingSummary(first: 100),
      const WeighingSummary(second: 100),
      const WeighingSummary(net: 100),
      const WeighingSummary(dry: 100),
    ]) {
      expect(summary.isClosing, isTrue);
    }
  });

  for (final size in [const Size(1366, 768), const Size(800, 700)]) {
    testWidgets(
      'Confirmação automática, abertura, fechamento e cancelamento em $size',
      (tester) async {
        await openPage(tester, size: size);
        if (size.width < 1280) {
          await tester.drag(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is SingleChildScrollView &&
                      w.scrollDirection == Axis.horizontal,
                )
                .last,
            const Offset(-1000, 0),
          );
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('pesagem-action-pesar')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pesagem-action-pesar')));
        await tester.pumpAndSettle();
        expect(find.text('ABERTURA DE PESO'), findsOneWidget);
        expect(
          find.text('PESO AUTOMÁTICO • indicador desconectado'),
          findsOneWidget,
        );
        expect(
          find
              .descendant(
                of: find.byKey(const ValueKey('weighing-confirmation')),
                matching: find.text('Salvar Pesagem'),
              )
              .hitTestable(),
          findsOneWidget,
        );
        final dialog = tester.getRect(
          find.byKey(const ValueKey('weighing-confirmation')),
        );
        expect(dialog.left, greaterThanOrEqualTo(0));
        expect(dialog.right, lessThanOrEqualTo(size.width));
        expect(dialog.bottom, lessThanOrEqualTo(size.height));
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('confirmada em simulação local'),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('weighing-confirmation')),
          findsNothing,
        );
        if (size.width < 1280) {
          await tester.drag(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is SingleChildScrollView &&
                      w.scrollDirection == Axis.horizontal,
                )
                .last,
            const Offset(1000, 0),
          );
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextField).first, 'DEF2E34');
        await tester.tap(find.byTooltip('Consultar placa'));
        await tester.pumpAndSettle();
        if (size.width < 1280) {
          await tester.drag(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is SingleChildScrollView &&
                      w.scrollDirection == Axis.horizontal,
                )
                .last,
            const Offset(-1000, 0),
          );
          await tester.pumpAndSettle();
        }
        await tapAction(tester, 'Pesagem');
        await tester.pumpAndSettle();
        expect(find.text('FECHAMENTO DE PESO'), findsOneWidget);
        final values = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data)
            .toList();
        expect(values, contains('DEF2E34'));
        expect(values, contains('GHI5J67'));
        expect(values, contains('José Antônio dos Santos Oliveira'));
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('weighing-confirmation')),
            matching: find.text('Salvar Pesagem'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('weighing-confirmation')),
          findsNothing,
        );
        expect(
          find.textContaining('confirmada em simulação local'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Peso Manual exige autenticação, valida peso, reutiliza confirmação e salva só a simulação',
    (tester) async {
      await openPage(tester);
      await tapAction(tester, 'Peso Manual');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('manual-user')),
        'balanca',
      );
      await tester.enterText(
        find.byKey(const ValueKey('manual-password')),
        'incorreta',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('manual-password')))
            .obscureText,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('manual-justification')),
        'Contingência desta leitura',
      );
      await tester.tap(find.text('Liberar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Autenticação inválida'), findsOneWidget);
      expect(find.byKey(const ValueKey('manual-weight-dialog')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('manual-password')),
        'Cxp123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('manual-justification')),
        'Contingência desta leitura',
      );
      await tester.tap(find.text('Liberar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('manual-authentication')), findsNothing);
      expect(find.text('PESO MANUAL'), findsOneWidget);
      await tester.tap(find.text('Prosseguir'));
      await tester.pumpAndSettle();
      expect(find.text('Informe um peso maior que zero.'), findsOneWidget);
      final manualWeight = find.byKey(const ValueKey('manual-weight'));
      await tester.enterText(manualWeight, '123abc');
      expect(
        tester.widget<TextFormField>(manualWeight).controller!.text,
        isEmpty,
      );
      await tester.enterText(manualWeight, '12345,5');
      await tester.tap(find.text('Prosseguir'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('weighing-confirmation')),
        findsOneWidget,
      );
      expect(
        find.text('PESO MANUAL • informado pelo operador'),
        findsOneWidget,
      );
      expect(find.text('Liberado por: balanca'), findsOneWidget);
      expect(find.text('12345,5 Kg'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('weighing-confirmation')),
          matching: find.text('Salvar Pesagem'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Pesagem de 12345,5 Kg confirmada em simulação local',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('peso-atual'))).data,
        '0',
      );
      // Uma nova tentativa sempre exige autenticação; a autorização não fica retida.
      await tapAction(tester, 'Peso Manual');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('manual-authentication')),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('manual-weight-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cancelar entrada e confirmação manuais não confirma nem altera o indicador',
    (tester) async {
      await openPage(tester);
      Future<void> authorize() async {
        await tapAction(tester, 'Peso Manual');
        await tester.pumpAndSettle();
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
          'Contingência desta leitura',
        );
        await tester.tap(find.text('Liberar'));
        await tester.pumpAndSettle();
      }

      await authorize();
      await tester.enterText(
        find.byKey(const ValueKey('manual-weight')),
        '1234.125',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('weighing-confirmation')), findsNothing);
      expect(
        find.textContaining('confirmada em simulação local'),
        findsNothing,
      );
      await authorize();
      await tester.enterText(
        find.byKey(const ValueKey('manual-weight')),
        '1234.125',
      );
      await tester.tap(find.text('Prosseguir'));
      await tester.pumpAndSettle();
      expect(find.text('1234,125 Kg'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('confirmada em simulação local'),
        findsNothing,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('peso-atual'))).data,
        '0',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Modais cabem em área pequena e mantêm ações acessíveis', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 400);
    final testPermissions = PermissionState();
    addTearDown(testPermissions.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showManualAuthentication(
                    context,
                    permissions: testPermissions,
                  ),
                  child: const Text('Autenticação'),
                ),
                TextButton(
                  onPressed: () => showManualWeightEntry(context),
                  child: const Text('Entrada'),
                ),
                TextButton(
                  onPressed: () => showWeighingConfirmation(
                    context,
                    WeighingPreview(
                      plate: 'ABC1D23',
                      trailer: 'DEF4G56',
                      operation: {'Motorista': 'Nome completo ' * 30},
                      currentWeight: 1234,
                      summary: const WeighingSummary(),
                      manualOperator: 'balanca',
                    ),
                  ),
                  child: const Text('Confirmação'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (final action in ['Autenticação', 'Entrada', 'Confirmação']) {
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(find.text('Cancelar').hitTestable(), findsOneWidget);
      final rect = tester.getRect(find.byType(AlertDialog));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(600));
      expect(rect.bottom, lessThanOrEqualTo(400));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
