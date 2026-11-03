import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/app/app_shell.dart';
import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/core/widgets/visual_components.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_actions.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_layout.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_side_panel.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_action_bar.dart';

void main() {
  for (final trailer in <String?>[null, '', '   ', 'ABC1D23']) {
    testWidgets('lista mostra carreta opcional: ${trailer ?? 'null'}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: PesagemSidePanel(
                layout: PesagemLayout.fromSize(const Size(1366, 900)),
                vehicles: [(plate: 'ZZZ9Z99', trailer: trailer, time: '09:12')],
              ),
            ),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('operation-list')),
          matching: find.text(
            trailer == null || trailer.trim().isEmpty ? '-' : trailer,
          ),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('Salvar usa o padrão de ícone ilustrado e preserva a caixa', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: PesagemActionBar(
              layout: PesagemLayout.fromSize(const Size(1366, 900)),
              actions: const {},
            ),
          ),
        ),
      ),
    );
    for (final action in [PesagemAction.imprimir, PesagemAction.salvar]) {
      final button = find.byKey(ValueKey('pesagem-action-${action.name}'));
      final asset = find.descendant(
        of: button,
        matching: find.byType(AppAsset),
      );
      expect(tester.widget<AppAsset>(asset).size, 30);
      final scale = tester.widget<Transform>(
        find.ancestor(of: asset, matching: find.byType(Transform)).first,
      );
      expect(scale.transform.entry(0, 0), 1.1);
      expect(scale.transform.entry(1, 1), 1.1);
      final slot = find.ancestor(
        of: asset,
        matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 29),
      );
      expect(slot, findsOneWidget);
    }
  });

  for (final action in PesagemAction.values) {
    testWidgets('${action.shortcut} é tratado uma vez com foco em TextField', (
      tester,
    ) async {
      final dispatcher = PesagemActionDispatcher();
      final calls = <PesagemAction>[];
      dispatcher.bind((action) async => calls.add(action));
      await tester.pumpWidget(
        MaterialApp(
          home: PesagemActionScope(
            dispatcher: dispatcher,
            child: const Scaffold(body: TextField(autofocus: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(action.key!);
      await tester.sendKeyRepeatEvent(action.key!);
      await tester.sendKeyUpEvent(action.key!);
      await tester.pumpAndSettle();
      expect(calls, [action]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets('F2 não aciona nenhuma ação com campo em foco', (tester) async {
    final dispatcher = PesagemActionDispatcher();
    final calls = <PesagemAction>[];
    dispatcher.bind((action) async => calls.add(action));
    await tester.pumpWidget(
      MaterialApp(
        home: PesagemActionScope(
          dispatcher: dispatcher,
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('Resumo Pesagem'), findsNothing);
  });

  testWidgets('F12 funciona com foco no cabeçalho da tela de Pesagem', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const AppShell()),
    );
    await tester.pumpAndSettle();
    final headerButton = find.byKey(const ValueKey('user-menu'));
    Focus.of(tester.element(find.text('AR'))).requestFocus();
    await tester.pump();
    expect(headerButton, findsOneWidget);
    expect(Focus.of(tester.element(find.text('AR'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('weighing-confirmation')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'atalhos de Pesagem não atuam em outra aba e voltam ao retornar',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1366, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const AppShell()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-cadastros')));
      await tester.pumpAndSettle();
      for (final action in PesagemAction.values) {
        await tester.sendKeyEvent(action.key!);
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('menu-balanca_icon')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('weighing-confirmation')),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
