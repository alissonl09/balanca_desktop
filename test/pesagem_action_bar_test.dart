import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_action_bar.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_actions.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [1000.0, 600.0]) {
    testWidgets('barra de ações distribui cinco botões em largura $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 500);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: PesagemActionBar(
              layout: PesagemLayout.fromSize(Size(width, 500)),
              actions: const {},
            ),
          ),
        ),
      );
      final buttons = [
        for (final action in PesagemAction.values)
          find.byKey(ValueKey('pesagem-action-${action.name}')),
      ];
      expect(buttons, hasLength(5));
      for (final button in buttons) {
        expect(button, findsOneWidget);
      }
      expect(find.text('Resumo Pesagem'), findsNothing);
      expect(find.text('F2'), findsNothing);
      final first = tester.getRect(buttons[0]);
      final third = tester.getRect(buttons[2]);
      final last = tester.getRect(buttons[4]);
      if (width >= 810) {
        expect(first.top, third.top);
        expect(first.top, last.top);
      } else {
        expect(third.top, greaterThan(first.top));
        expect(last.top, greaterThan(third.top));
      }
      for (final button in buttons) {
        final rect = tester.getRect(button);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
