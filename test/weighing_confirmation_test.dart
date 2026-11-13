import 'dart:async';

import 'package:balanca_desktop/core/permissions/permission_models.dart';
import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';
import 'package:balanca_desktop/features/pesagem/operation_lookup.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_page.dart';
import 'package:balanca_desktop/features/pesagem/weighing_dialogs.dart';
import 'package:balanca_desktop/features/pesagem/weighing_preview.dart';
import 'package:balanca_desktop/features/ticket/ticket_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final confirmation = find.byKey(const ValueKey('weighing-confirmation'));
Finder dialogButton(String text) =>
    find.descendant(of: confirmation, matching: find.text(text));

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> openConfirmation(WidgetTester tester, bool manual) async {
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
      '12345',
    );
    await tap(tester, find.text('Prosseguir'));
  }
  expect(confirmation, findsOneWidget);
}

void main() {
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
