import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/offline/offline_models.dart';
import 'package:balanca_desktop/core/offline/offline_station.dart';
import 'package:balanca_desktop/core/offline/pre_ticket_source.dart';
import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/core/widgets/read_only_value_field.dart';
import 'package:balanca_desktop/core/widgets/visual_components.dart';
import 'package:balanca_desktop/features/pesagem/operation_lookup.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_actions.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_edit_service.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_page.dart';
import 'package:balanca_desktop/features/pesagem/weighing_preview.dart';
import 'package:balanca_desktop/features/ticket/ticket_mapper.dart';
import 'package:balanca_desktop/features/ticket/ticket_session.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';

Finder input(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is VisualField && w.label == label),
  matching: find.byType(TextField),
);
Finder action(PesagemAction a) =>
    find.byKey(ValueKey('pesagem-action-${a.name}'));
Finder get confirmation => find.byKey(const ValueKey('weighing-confirmation'));

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> render(
  WidgetTester tester, {
  TicketSession? session,
  OperationLookupService? lookup,
  OfflineStation? station,
  PesagemEditService? editService,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1366, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: PesagemPage(
          ticketSession: session,
          lookupService: lookup,
          station: station,
          editService: editService,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> lookupPlate(WidgetTester tester, String plate) async {
  await tester.enterText(input('Placa'), plate);
  await tap(tester, find.byTooltip('Consultar placa'));
}

Future<void> manualRead(WidgetTester tester, String weight) async {
  await tap(tester, action(PesagemAction.manual));
  await tester.enterText(find.byKey(const ValueKey('manual-user')), 'balanca');
  await tester.enterText(
    find.byKey(const ValueKey('manual-password')),
    'Cxp123',
  );
  await tester.enterText(
    find.byKey(const ValueKey('manual-justification')),
    'Indicador indisponível nesta leitura',
  );
  await tap(tester, find.text('Liberar'));
  await tester.enterText(find.byKey(const ValueKey('manual-weight')), weight);
  await tap(tester, find.text('Prosseguir'));
  await tap(
    tester,
    find.descendant(of: confirmation, matching: find.text('Salvar Pesagem')),
  );
}

void windowsTestWidgets(String name, WidgetTesterCallback callback) =>
    testWidgets(
      name,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
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

  windowsTestWidgets(
    'sem integração libera Carreta e todos os campos manuais, sem preencher dados',
    (tester) async {
      final session = TicketSession();
      await render(tester, session: session);
      await tester.enterText(input('Motorista'), 'JOAO DIGITADO');
      await lookupPlate(tester, 'ZZZ9Z99');
      expect(session.operationMode, OperationMode.manual);
      expect(tester.widget<TextField>(input('Carreta')).readOnly, isFalse);
      for (final label in [
        'Motorista',
        'Transportadora',
        'Emissor(es)',
        'Depósito',
        'Item',
        'Tipo do documento',
        'Nº Nota(s) / Documento(s)',
        'Peso N.F. (Kg)',
        'Embalagem',
        'Observação',
      ]) {
        final field = tester.widget<TextField>(input(label));
        expect(field.enabled, isTrue, reason: label);
        expect(field.readOnly, isFalse, reason: label);
        expect(
          field.controller!.text,
          label == 'Motorista' ? 'JOAO DIGITADO' : '',
          reason: label,
        );
      }
      expect(find.byType(ReadOnlyValueField), findsNothing);
    },
  );

  windowsTestWidgets(
    'dados oficiais ficam readonly; ausentes continuam manuais e LOV funciona',
    (tester) async {
      final session = TicketSession();
      await render(tester, session: session);
      await lookupPlate(tester, 'ABC1D23');
      expect(session.operationMode, OperationMode.integrada);
      for (final label in session.officialOperation.keys.where(
        (label) => label != 'Destino',
      )) {
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is ReadOnlyValueField &&
                w.label ==
                    (label == 'Transportador' ? 'Transportadora' : label),
          ),
          findsOneWidget,
        );
        expect(
          input(label == 'Transportador' ? 'Transportadora' : label),
          findsNothing,
        );
      }
      expect(tester.widget<TextField>(input('Observação')).enabled, isTrue);
      final lov = find.byType(DropdownButtonFormField<String>);
      await tap(tester, lov);
      await tap(tester, find.text('XYZ9H87').last);
      expect(
        find.descendant(of: lov, matching: find.text('XYZ9H87')),
        findsOneWidget,
      );
      await tap(tester, find.byTooltip('Limpar consulta'));
      await lookupPlate(tester, 'DEF2E34');
      expect(
        tester.widget<TextField>(input('Carreta')).controller!.text,
        'GHI5J67',
      );
      expect(tester.widget<TextField>(input('Carreta')).readOnly, isTrue);
    },
  );

  windowsTestWidgets('offline rejeita resultado remoto sem dados locais', (
    tester,
  ) async {
    final station = OfflineStation();
    addTearDown(station.dispose);
    final session = TicketSession();
    await render(
      tester,
      station: station,
      session: session,
      lookup: FixedLookup(
        OperationLookup(
          values: {'Motorista': 'OFICIAL REMOTO'},
          trailers: ['DEF4G56'],
          origin: PreTicketOrigin.remota,
        ),
      ),
    );
    await lookupPlate(tester, 'ZZZ9Z99');
    expect(session.operationMode, OperationMode.manual);
    expect(
      tester.widget<TextField>(input('Motorista')).controller!.text,
      isEmpty,
    );
    expect(tester.widget<TextField>(input('Carreta')).readOnly, isFalse);
  });

  windowsTestWidgets(
    'texto manual longo mantém valor, Home/End, setas e seleção sem botão lateral',
    (tester) async {
      await render(tester);
      final long = List.filled(20, 'JOAO CARLOS DA SILVA').join(' ');
      await tester.enterText(input('Motorista'), long);
      final controller = tester
          .widget<TextField>(input('Motorista'))
          .controller!;
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(controller.selection.baseOffset, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(controller.selection.baseOffset, long.length);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(controller.selection.isCollapsed, isFalse);
      expect(controller.text, long);
      expect(find.byTooltip('Ver conteúdo completo: Motorista'), findsNothing);
    },
  );

  windowsTestWidgets(
    'readonly longo mostra conteúdo completo, nome e fecha com ESC',
    (tester) async {
      final long = List.filled(
        10,
        'CARLOS EDUARDO DA SILVA COMPLETO',
      ).join(' ');
      await render(
        tester,
        lookup: FixedLookup(
          OperationLookup(values: {'Motorista': long}, trailers: ['DEF4G56']),
        ),
      );
      await lookupPlate(tester, 'ABC1D23');
      await tap(tester, find.byTooltip('Ver conteúdo completo: Motorista'));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Motorista'),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        long,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  windowsTestWidgets(
    'TAB segue Placa, Carreta, Motorista e a ordem visual antes das ações',
    (tester) async {
      await render(tester);
      await tester.enterText(input('Placa'), 'ZZZ9Z99');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('Carreta')).focusNode!.hasFocus,
        isTrue,
      );
      for (final label in [
        'Motorista',
        'Transportadora',
        'Emissor(es)',
        'Depósito',
        'Item',
        'Tipo do documento',
        'Nº Nota(s) / Documento(s)',
        'Peso N.F. (Kg)',
        'Embalagem',
        'Observação',
      ]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(input(label)).focusNode!.hasFocus,
          isTrue,
          reason: label,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final a in [
    PesagemAction.imprimir,
    PesagemAction.manual,
    PesagemAction.pesar,
  ]) {
    windowsTestWidgets(
      '${a.shortcut} e clique chamam o mesmo fluxo, sem duplicar ou contornar modal',
      (tester) async {
        final session = TicketSession();
        await render(tester, session: session);
        Finder result() => switch (a) {
          PesagemAction.imprimir => find.byKey(
            const ValueKey('print-layout-preview'),
            skipOffstage: false,
          ),
          PesagemAction.manual => find.byKey(
            const ValueKey('manual-authentication'),
            skipOffstage: false,
          ),
          _ => find.byKey(
            const ValueKey('weighing-confirmation'),
            skipOffstage: false,
          ),
        };
        for (final focusedField in [
          null,
          'Placa',
          'Carreta',
          'Motorista',
          'Observação',
        ]) {
          if (focusedField != null) {
            await tester.tap(input(focusedField));
            await tester.sendKeyEvent(a.key!);
            await tester.pumpAndSettle();
          } else {
            await tap(tester, action(a));
          }
          expect(result(), findsOneWidget);
          for (final other in PesagemAction.values) {
            await tester.sendKeyEvent(other.key!);
          }
          await tester.pumpAndSettle();
          expect(result(), findsOneWidget);
          expect(session.phase, WeighingPhase.nova);
          if (a != PesagemAction.manual) {
            expect(
              find.byKey(const ValueKey('manual-authentication')),
              findsNothing,
            );
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(result(), findsNothing);
        }
      },
    );
  }

  windowsTestWidgets('F6 e clique limpam a mesma consulta e rascunho', (
    tester,
  ) async {
    await render(tester);
    for (final focusedField in [
      null,
      'Placa',
      'Carreta',
      'Motorista',
      'Observação',
    ]) {
      await lookupPlate(tester, 'ZZZ9Z99');
      await tester.enterText(input('Motorista'), 'JOAO');
      if (focusedField != null) {
        await tester.tap(input(focusedField));
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      } else {
        await tap(tester, action(PesagemAction.nova));
      }
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('Placa')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(input('Motorista')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(input('Placa')).focusNode!.hasFocus,
        isTrue,
      );
    }
  });

  windowsTestWidgets('TAB segue dos dados para a barra de ações', (
    tester,
  ) async {
    await render(tester);
    await tester.tap(input('Observação'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      Focus.of(tester.element(action(PesagemAction.imprimir))).hasFocus,
      isTrue,
    );
  });

  windowsTestWidgets(
    'F10 e clique salvam os mesmos dados uma vez, preservando pesos e fase',
    (tester) async {
      final session = TicketSession()
        ..phase = WeighingPhase.aberta
        ..current = WeighingPreview(
          plate: 'ZZZ9Z99',
          trailer: '',
          operation: {'Motorista': 'JOAO'},
          currentWeight: 18500,
          summary: const WeighingSummary(first: 18500),
        );
      final summary = session.current!.summary;
      final service = CountingEditService();
      await render(tester, session: session, editService: service);
      expect(
        find.descendant(
          of: action(PesagemAction.salvar),
          matching: find.text('F10'),
        ),
        findsOneWidget,
      );
      var expectedCalls = 0;
      for (final focusedField in [
        null,
        'Placa',
        'Carreta',
        'Motorista',
        'Observação',
      ]) {
        final value = 'JOAO CORRIGIDO ${++expectedCalls}';
        await tester.enterText(input('Motorista'), value);
        if (focusedField == null) {
          await tap(tester, action(PesagemAction.salvar));
        } else {
          await tester.tap(input(focusedField));
          await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
          await tester.pumpAndSettle();
          // O auto-repeat após terminar o save também não pode salvar de novo.
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f10);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
          await tester.pumpAndSettle();
        }
        expect(service.calls, expectedCalls);
        expect(session.current!.operation['Motorista'], value);
        expect(session.current!.summary, same(summary));
        expect(session.current!.summary.first, 18500);
        expect(session.current!.summary.secondWeighedAt, isNull);
        expect(session.current!.summary.second, 0);
        expect(session.phase, WeighingPhase.aberta);
        expect(confirmation, findsNothing);
        expect(find.text('Dados da pesagem atualizados.'), findsOneWidget);
      }
    },
  );

  for (final phase in [WeighingPhase.nova, WeighingPhase.fechada]) {
    windowsTestWidgets('F10 respeita Salvar desabilitado em $phase', (
      tester,
    ) async {
      final session = TicketSession()..phase = phase;
      final service = CountingEditService();
      await render(tester, session: session, editService: service);
      expect(
        tester.widget<TextButton>(action(PesagemAction.salvar)).onPressed,
        isNull,
      );
      final before = session.current;
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      expect(session.current, same(before));
      expect(session.phase, phase);
      expect(confirmation, findsNothing);
    });
  }

  windowsTestWidgets('F10 não atravessa modal nem duplica save em andamento', (
    tester,
  ) async {
    final session = TicketSession()
      ..phase = WeighingPhase.aberta
      ..current = WeighingPreview(
        plate: 'ZZZ9Z99',
        trailer: '',
        operation: {'Motorista': 'JOAO'},
        currentWeight: 18500,
        summary: const WeighingSummary(first: 18500),
      );
    final gate = Completer<void>();
    final service = CountingEditService(gate: gate.future);
    await render(tester, session: session, editService: service);
    await tester.enterText(input('Motorista'), 'CORRIGIDO');
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(session.current!.operation['Motorista'], 'JOAO');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pump();
    expect(service.calls, 1);
    expect(
      tester.widget<TextButton>(action(PesagemAction.salvar)).onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pump();
    expect(service.calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(session.current!.operation['Motorista'], 'CORRIGIDO');
    expect(session.phase, WeighingPhase.aberta);
    expect(session.current!.summary.first, 18500);
  });

  windowsTestWidgets(
    'Salvar habilita só aberta e correção preserva Peso 1, fase e captura sem Peso 2',
    (tester) async {
      final session = TicketSession();
      await render(tester, session: session);
      bool enabled() =>
          tester.widget<TextButton>(action(PesagemAction.salvar)).onPressed !=
          null;
      expect(enabled(), isFalse);
      await lookupPlate(tester, 'ZZZ9Z99');
      await tester.enterText(input('Motorista'), 'JOAO SILVA');
      await manualRead(tester, '18500');
      expect(enabled(), isTrue);
      expect(session.phase, WeighingPhase.aberta);
      final before = session.current!.summary;
      final capture = session.confirmed;
      await tester.enterText(input('Motorista'), 'JOAO CARLOS SILVA');
      expect(
        session.current!.operation['Motorista'],
        'JOAO SILVA',
      ); // rascunho separado
      await tap(tester, action(PesagemAction.salvar));
      expect(find.text('Dados da pesagem atualizados.'), findsOneWidget);
      expect(session.current!.operation['Motorista'], 'JOAO CARLOS SILVA');
      expect(session.current!.summary, same(before));
      expect(session.current!.summary.first, 18500);
      expect(session.current!.summary.second, 0);
      expect(session.current!.summary.secondWeighedAt, isNull);
      expect(session.confirmed, same(capture));
      expect(session.phase, WeighingPhase.aberta);
      expect(ticketFromSession(session, SettingsState()).secondWeight, isNull);
      expect(confirmation, findsNothing);
      await manualRead(tester, '8000');
      expect(session.phase, WeighingPhase.fechada);
      expect(enabled(), isFalse);
    },
  );

  test('serviço rejeita alteração oficial e edição fora de ABERTA sem tocar captura', () async {
    final session = TicketSession()
      ..phase = WeighingPhase.aberta
      ..officialOperation = {'Motorista': 'OFICIAL'}
      ..current = WeighingPreview(
        plate: 'ABC1D23',
        trailer: 'DEF4G56',
        operation: {'Motorista': 'OFICIAL'},
        currentWeight: 18500,
        summary: const WeighingSummary(first: 18500),
      );
    final before = session.current;
    final service = MemoryPesagemEditService();
    await expectLater(
      service.save(session, {'Motorista': 'ALTERADO'}),
      throwsStateError,
    );
    expect(session.current, same(before));
    await service.save(session, {
      'Motorista': 'OFICIAL',
      'Observação': 'MANUAL',
    });
    expect(session.phase, WeighingPhase.aberta);
    expect(session.current!.summary, same(before!.summary));
    expect(session.current!.currentWeight, 18500);
    session.phase = WeighingPhase.fechada;
    await expectLater(
      service.save(session, {'Motorista': 'OFICIAL'}),
      throwsStateError,
    );
  });

  windowsTestWidgets('salvar observação integrada não libera campo oficial', (
    tester,
  ) async {
    final session = TicketSession();
    await render(tester, session: session);
    await lookupPlate(tester, 'DEF2E34');
    final official = session.officialOperation['Motorista'];
    await tester.enterText(input('Observação'), 'Correção permitida');
    await tap(tester, action(PesagemAction.salvar));
    expect(session.current!.operation['Observação'], 'Correção permitida');
    expect(session.current!.operation['Motorista'], official);
    expect(input('Motorista'), findsNothing);
    expect(session.current!.summary.first, 28450);
    expect(session.phase, WeighingPhase.aberta);
  });
}

class FixedLookup implements OperationLookupService {
  FixedLookup(this.result);
  final OperationLookup? result;
  @override
  Future<OperationLookup?> lookup(
    String plate,
    StationConnection connection,
  ) async => result;
}

class CountingEditService implements PesagemEditService {
  CountingEditService({this.gate});
  final Future<void>? gate;
  int calls = 0;

  @override
  Future<void> save(TicketSession session, Map<String, String> values) async {
    calls++;
    if (gate != null) await gate;
    await MemoryPesagemEditService().save(session, values);
  }
}
