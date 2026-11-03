import 'dart:io';

import 'package:balanca_desktop/app/balanca_app.dart';
import 'package:balanca_desktop/features/cadastros/cadastro_record.dart';
import 'package:balanca_desktop/features/cadastros/cadastros_memory.dart';
import 'package:balanca_desktop/features/cadastros/cadastros_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

Future<void> openCadastros(
  WidgetTester tester, {
  Size size = const Size(1366, 768),
}) async {
  tester.view.devicePixelRatio = 1;
  // A janela menor é aplicada já em Cadastros, sem alterar o limite operacional
  // da tela de Pesagem que a aplicação abre inicialmente.
  tester.view.physicalSize = size.height < 700 ? Size(size.width, 700) : size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const BalancaApp());
  await tester.pumpAndSettle();
  await tester.tap(byKey('menu-cadastros'));
  await tester.pumpAndSettle();
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Future<void> tab(WidgetTester tester, CadastroKind kind) async {
  final target = find.descendant(
    of: byKey('cadastros-tabs'),
    matching: find.text(kind.label),
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String field, String value) async {
  final target = byKey('cadastro-$field');
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.enterText(target, value);
}

Future<void> choose(WidgetTester tester, String field, String option) async {
  await tester.ensureVisible(byKey('cadastro-$field'));
  await tester.pumpAndSettle();
  await tester.tap(byKey('cadastro-$field'));
  await tester.pumpAndSettle();
  if (find.text(option).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(option),
      200,
      scrollable: find.byType(Scrollable).last,
    );
  } else {
    await tester.ensureVisible(find.text(option).last);
  }
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> chooseCarrier(WidgetTester tester, String name, int code) async {
  await tester.ensureVisible(byKey('cadastro-carrier'));
  await tester.pumpAndSettle();
  await tester.tap(byKey('cadastro-carrier'));
  await tester.pumpAndSettle();
  await tester.enterText(byKey('carrier-search'), name);
  await tester.pumpAndSettle();
  await tester.tap(byKey('carrier-option-$code'));
  await tester.pumpAndSettle();
}

CadastrosMemory memory(WidgetTester tester) =>
    tester.widget<CadastrosPage>(find.byType(CadastrosPage)).memory;

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

  for (final kind in CadastroKind.values) {
    testWidgets(
      '${kind.label}: busca, seleção, inserir, alterar e excluir com cancelamentos',
      (tester) async {
        await openCadastros(tester);
        await tab(tester, kind);
        final state = memory(tester);
        final count = state.records(kind).length;
        final nextCode = state.nextCode(kind);
        expect(
          tester.widget<OutlinedButton>(byKey('cadastro-edit')).onPressed,
          isNull,
        );
        expect(
          tester.widget<OutlinedButton>(byKey('cadastro-delete')).onPressed,
          isNull,
        );

        await fill(tester, 'search', '1');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(byKey('cadastro-row-${kind.name}-1'), findsOneWidget);
        expect(byKey('cadastro-row-${kind.name}-2'), findsNothing);
        final firstName = state.records(kind).first.identification;
        await fill(tester, 'search', firstName.toUpperCase());
        await tester.tap(find.byTooltip('Pesquisar cadastro'));
        await tester.pumpAndSettle();
        expect(byKey('cadastro-row-${kind.name}-1'), findsOneWidget);
        await tester.tap(byKey('cadastro-row-${kind.name}-1'));
        await tester.pump();
        expect(
          tester.widget<OutlinedButton>(byKey('cadastro-edit')).onPressed,
          isNotNull,
        );
        await fill(tester, 'search', 'NENHUM RESULTADO');
        await tester.tap(find.byTooltip('Pesquisar cadastro'));
        await tester.pumpAndSettle();
        expect(find.text('Nenhum registro encontrado.'), findsOneWidget);
        expect(
          tester.widget<OutlinedButton>(byKey('cadastro-edit')).onPressed,
          isNull,
        );
        await fill(tester, 'search', '');
        await tester.tap(find.byTooltip('Pesquisar cadastro'));
        await tester.pumpAndSettle();

        await tester.tap(byKey('cadastro-insert'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: byKey('cadastro-code'),
                  matching: find.byType(TextField),
                ),
              )
              .readOnly,
          isTrue,
        );
        expect(
          tester.widget<TextFormField>(byKey('cadastro-code')).initialValue,
          '$nextCode',
        );
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(state.records(kind), hasLength(count));
        expect(state.nextCode(kind), nextCode);

        await tester.tap(byKey('cadastro-insert'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();
        if (kind == CadastroKind.placas) {
          expect(find.text('Informe a placa.'), findsOneWidget);
          expect(
            find.text('Selecione uma transportadora cadastrada.'),
            findsOneWidget,
          );
          await fill(tester, 'plate', ' gh i 7j89 ');
          expect(
            tester
                .widget<TextFormField>(byKey('cadastro-plate'))
                .controller!
                .text,
            'GHI7J89',
          );
          await chooseCarrier(tester, 'horizonte', 1);
        } else {
          expect(find.text('Informe o nome.'), findsOneWidget);
          if (kind == CadastroKind.remetentes) {
            expect(find.text('Selecione o tipo.'), findsOneWidget);
            await choose(tester, 'type', 'Fornecedor');
          }
          if (kind == CadastroKind.motoristas) {
            expect(find.text('Selecione o vínculo.'), findsOneWidget);
            await choose(tester, 'link', 'Autônomo');
          }
          await fill(tester, 'name', 'Novo cadastro ${kind.name}');
          await fill(tester, 'address', 'Rua de Teste');
          await fill(tester, 'number', '12-A');
          await fill(tester, 'complement', 'Galpão de teste');
          await fill(tester, 'city', 'Cidade de Teste');
          await choose(tester, 'uf', 'SP');
          await fill(tester, 'postalCode', '00000-000');
          await fill(tester, 'taxId', 'Documento de teste');
          if (kind != CadastroKind.motoristas) {
            await fill(tester, 'stateRegistration', 'ISENTO');
          }
          if (kind == CadastroKind.remetentes) {
            await fill(tester, 'enrollment', 'MAT-123');
          }
          await fill(tester, 'observation', 'Observação livre\nSegunda linha');
        }
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();
        expect(byKey('cadastro-form'), findsNothing);
        expect(state.records(kind), hasLength(count + 1));
        final inserted = state.records(kind).last;
        expect(inserted.code, nextCode);
        if (kind != CadastroKind.placas) {
          expect(inserted.number, '12-A');
          expect(inserted.uf, 'SP');
          expect(inserted.observation, 'Observação livre\nSegunda linha');
        } else {
          expect(inserted.carrierCode, 1);
        }
        expect(
          tester.widget<OutlinedButton>(byKey('cadastro-edit')).onPressed,
          isNotNull,
        );
        final field = kind == CadastroKind.placas ? 'plate' : 'name';
        final changed = kind == CadastroKind.placas
            ? 'ZZZ9Z99'
            : 'Registro alterado ${kind.name}';
        await tester.tap(byKey('cadastro-edit'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(byKey('cadastro-code')).initialValue,
          '$nextCode',
        );
        expect(
          tester
              .widget<TextFormField>(byKey('cadastro-$field'))
              .controller!
              .text,
          inserted.identification,
        );
        await fill(tester, field, changed);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(
          state.records(kind).last.identification,
          inserted.identification,
        );
        await tester.tap(byKey('cadastro-edit'));
        await tester.pumpAndSettle();
        await fill(tester, field, changed);
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();
        expect(state.records(kind).last.identification, changed);
        expect(state.records(kind).last.code, nextCode);
        await tester.tap(byKey('cadastro-delete'));
        await tester.pumpAndSettle();
        expect(
          find.text('Deseja realmente excluir este registro?'),
          findsOneWidget,
        );
        expect(find.text('$nextCode - $changed'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(state.records(kind), hasLength(count + 1));
        await tester.tap(byKey('cadastro-delete'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: byKey('cadastro-delete-confirmation'),
            matching: find.text('Excluir'),
          ),
        );
        await tester.pumpAndSettle();
        expect(state.records(kind), hasLength(count));
        expect(
          tester.widget<OutlinedButton>(byKey('cadastro-delete')).onPressed,
          isNull,
        );
        expect(state.nextCode(kind), nextCode + 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Transportadora recém-criada é reutilizada em Motoristas e Placas; vínculo autônomo limpa a referência',
    (tester) async {
      await openCadastros(tester);
      await tab(tester, CadastroKind.transportadoras);
      await tester.tap(byKey('cadastro-insert'));
      await tester.pumpAndSettle();
      await fill(tester, 'name', 'Nova Transportadora Teste');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final carrierCode = memory(tester)
          .records(CadastroKind.transportadoras)
          .last
          .code;
      await tab(tester, CadastroKind.motoristas);
      await tester.tap(byKey('cadastro-insert'));
      await tester.pumpAndSettle();
      await fill(tester, 'name', 'Motorista de Teste');
      await choose(tester, 'link', 'Transportadora');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Selecione uma transportadora cadastrada.'),
        findsOneWidget,
      );
      await tester.tap(byKey('cadastro-carrier'));
      await tester.pumpAndSettle();
      await tester.enterText(byKey('carrier-search'), 'Não existente');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nenhuma transportadora encontrada.'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: byKey('carrier-picker'),
          matching: find.text('Cancelar'),
        ),
      );
      await tester.pumpAndSettle();
      await chooseCarrier(tester, 'Nova Transportadora', carrierCode);
      await choose(tester, 'link', 'Autônomo');
      expect(byKey('cadastro-carrier'), findsNothing);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      final driver = memory(tester).records(CadastroKind.motoristas).last;
      expect(driver.driverLink, DriverLink.autonomo);
      expect(driver.carrierCode, isNull);
      await tester.tap(byKey('cadastro-edit'));
      await tester.pumpAndSettle();
      await choose(tester, 'link', 'Transportadora');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Selecione uma transportadora cadastrada.'),
        findsOneWidget,
      );
      await chooseCarrier(tester, 'Nova Transportadora', carrierCode);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(
        memory(tester).records(CadastroKind.motoristas).last.carrierCode,
        carrierCode,
      );
      await tab(tester, CadastroKind.placas);
      await tester.tap(byKey('cadastro-insert'));
      await tester.pumpAndSettle();
      await fill(tester, 'plate', 'xyz 9h87');
      await chooseCarrier(tester, '$carrierCode', carrierCode);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(
        memory(tester).records(CadastroKind.placas).last.carrierCode,
        carrierCode,
      );
      await tester.tap(byKey('menu-config'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('menu-cadastros'));
      await tester.pumpAndSettle();
      expect(
        memory(tester).records(CadastroKind.transportadoras).last.name,
        'Nova Transportadora Teste',
      );
      expect(
        memory(tester).records(CadastroKind.motoristas).last.carrierCode,
        carrierCode,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Renomear e excluir transportadora atualiza os vínculos sem excluir motoristas ou placas',
    (tester) async {
      await openCadastros(tester);
      await tab(tester, CadastroKind.transportadoras);
      await tester.tap(byKey('cadastro-row-transportadoras-1'));
      await tester.pump();
      await tester.tap(byKey('cadastro-edit'));
      await tester.pumpAndSettle();
      await fill(tester, 'name', 'Transportadora Renomeada');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      await tab(tester, CadastroKind.motoristas);
      expect(find.text('Transportadora Renomeada'), findsOneWidget);
      await tab(tester, CadastroKind.placas);
      expect(find.text('Transportadora Renomeada'), findsOneWidget);
      await tab(tester, CadastroKind.transportadoras);
      await tester.tap(byKey('cadastro-row-transportadoras-1'));
      await tester.pump();
      await tester.tap(byKey('cadastro-delete'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: byKey('cadastro-delete-confirmation'),
          matching: find.text('Excluir'),
        ),
      );
      await tester.pumpAndSettle();
      expect(memory(tester).records(CadastroKind.motoristas), hasLength(2));
      expect(memory(tester).records(CadastroKind.placas), hasLength(2));
      await tab(tester, CadastroKind.placas);
      expect(find.text('Transportadora indisponível (cód. 1)'), findsOneWidget);
      await tester.tap(byKey('cadastro-row-placas-1'));
      await tester.pump();
      await tester.tap(byKey('cadastro-edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Selecione uma transportadora cadastrada.'),
        findsOneWidget,
      );
      await chooseCarrier(tester, 'Serra', 2);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(memory(tester).records(CadastroKind.placas).first.carrierCode, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(1920, 1080),
    const Size(1366, 768),
    const Size(800, 600),
  ]) {
    testWidgets(
      'Formulários e seletor de transportadora respeitam a área útil em $size',
      (tester) async {
        await openCadastros(tester, size: size);
        for (final kind in CadastroKind.values) {
          await tab(tester, kind);
          await tester.tap(byKey('cadastro-insert'));
          await tester.pumpAndSettle();
          final rect = tester.getRect(byKey('cadastro-form'));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          expect(find.text('Salvar').hitTestable(), findsOneWidget);
          expect(find.text('Cancelar').hitTestable(), findsOneWidget);
          if (kind == CadastroKind.placas) {
            await tester.ensureVisible(byKey('cadastro-carrier'));
            await tester.pumpAndSettle();
            await tester.tap(byKey('cadastro-carrier'));
            await tester.pumpAndSettle();
            final picker = tester.getRect(byKey('carrier-picker'));
            expect(picker.top, greaterThanOrEqualTo(0));
            expect(picker.bottom, lessThanOrEqualTo(size.height));
            await tester.tap(
              find.descendant(
                of: byKey('carrier-picker'),
                matching: find.text('Cancelar'),
              ),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
