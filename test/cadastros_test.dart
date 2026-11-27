import 'dart:io';

import 'package:balanca_desktop/app/balanca_app.dart';
import 'package:balanca_desktop/core/permissions/permission_models.dart';
import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/features/cadastros/cadastro_record.dart';
import 'package:balanca_desktop/features/cadastros/cadastros_memory.dart';
import 'package:balanca_desktop/features/cadastros/cadastros_page.dart';
import 'package:balanca_desktop/features/cadastros/catalog_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

Future<void> openCadastros(
  WidgetTester tester, {
  Size size = const Size(1366, 768),
  bool simulated = true,
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
  if (simulated) await toggleSimulation(tester);
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Future<void> toggleSimulation(WidgetTester tester) async {
  await tester.tap(byKey('cadastro-simulation'));
  await tester.pumpAndSettle();
}

Future<void> selectRow(
  WidgetTester tester,
  CadastroKind kind,
  String id,
) async {
  await tester.tap(byKey('cadastro-row-${kind.name}-$id'));
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> doubleTapRow(
  WidgetTester tester,
  CadastroKind kind,
  String id,
) async {
  final row = byKey('cadastro-row-${kind.name}-$id');
  await tester.tap(row);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> cancelForm(WidgetTester tester) async {
  await tester.tap(find.text('Cancelar'));
  await tester.pumpAndSettle();
  final discard = find.text('Descartar');
  if (discard.evaluate().isNotEmpty) {
    await tester.tap(discard);
    await tester.pumpAndSettle();
  }
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

  for (final kind in CadastroKind.values.where((kind) => !kind.isCatalog)) {
    testWidgets(
      '${kind.label}: busca, seleção, inserir, alterar e excluir com cancelamentos',
      (tester) async {
        await openCadastros(tester);
        await tab(tester, kind);
        final state = memory(tester);
        final count = state.records(kind).length;
        final nextCode = state.nextCode(kind);
        final displayCode = kind == CadastroKind.motoristas
            ? 'SIM-$nextCode'
            : '$nextCode';
        expect(
          tester.widget<OutlinedButton>(byKey('cadastro-edit')).onPressed,
          isNull,
        );
        expect(
          tester.widget<OutlinedButton>(byKey('cadastro-delete')).onPressed,
          isNull,
        );

        await fill(
          tester,
          'search',
          kind == CadastroKind.motoristas ? 'sim-1' : '1',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(byKey('cadastro-row-${kind.name}-1'), findsOneWidget);
        expect(byKey('cadastro-row-${kind.name}-2'), findsNothing);
        final firstName = state.records(kind).first.identification;
        await fill(tester, 'search', firstName.toUpperCase());
        await tester.tap(find.byTooltip('Pesquisar cadastro'));
        await tester.pumpAndSettle();
        expect(byKey('cadastro-row-${kind.name}-1'), findsOneWidget);
        await selectRow(tester, kind, '1');
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
          displayCode,
        );
        await cancelForm(tester);
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
          await fill(tester, 'name', 'Novo cadastro ${kind.name}');
          await fill(tester, 'address', 'Rua de Teste');
          await fill(tester, 'number', '12-A');
          await fill(tester, 'complement', 'Galpão de teste');
          await fill(tester, 'city', 'Cidade de Teste');
          await choose(tester, 'uf', 'SP');
          await fill(tester, 'postalCode', '00000-000');
          if (kind == CadastroKind.motoristas) {
            expect(byKey('cadastro-taxId'), findsNothing);
          } else {
            await fill(tester, 'taxId', 'Documento de teste');
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
          displayCode,
        );
        expect(
          tester
              .widget<TextFormField>(byKey('cadastro-$field'))
              .controller!
              .text,
          inserted.identification,
        );
        await fill(tester, field, changed);
        await cancelForm(tester);
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
        expect(find.text('$displayCode - $changed'), findsOneWidget);
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
          .code!;
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
      await doubleTapRow(tester, CadastroKind.motoristas, '2');
      expect(find.text('Transportadora Renomeada'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
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

  testWidgets('Cadastros inicia em modo real e isola a demonstração', (
    tester,
  ) async {
    await openCadastros(tester, simulated: false);
    await tab(tester, CadastroKind.motoristas);
    expect(memory(tester).simulated, isFalse);
    expect(find.text('Nenhum dado oficial disponível.'), findsOneWidget);
    expect(
      find.byTooltip('Integração de manutenção indisponível'),
      findsNWidgets(3),
    );
    expect(
      tester.widget<ElevatedButton>(byKey('cadastro-insert')).onPressed,
      isNull,
    );
    await toggleSimulation(tester);
    expect(find.text('Cadastro de Motoristas'), findsOneWidget);
    expect(find.text('João da Silva'), findsOneWidget);
    await toggleSimulation(tester);
    expect(find.text('João da Silva'), findsNothing);
    expect(memory(tester).records(CadastroKind.motoristas), isEmpty);
  });

  testWidgets(
    'Consulta oficial usa matrícula textual e abre em somente leitura',
    (tester) async {
      final permissions = PermissionState()..currentUserId = 'carlos';
      final state = CadastrosMemory.real(
        permissions,
        available: {
          CadastroKind.motoristas: [
            CadastroRecord(
              sourceId: 'driver-id',
              registration: 'AB-008X',
              name: 'Motorista Integrado',
              taxId: 'Documento legado',
              city: 'Guaxupé',
              uf: 'UF legada',
              linkedVehicleIds: ['vehicle-id'],
            ),
          ],
          CadastroKind.placas: [
            CadastroRecord(sourceId: 'vehicle-id', plate: 'ABC1234'),
          ],
        },
      );
      addTearDown(permissions.dispose);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CadastrosPage(compact: true, memory: state),
            ),
          ),
        ),
      );
      await tab(tester, CadastroKind.motoristas);
      for (final label in ['Matrícula', 'Nome', 'Cidade', 'UF']) {
        expect(find.text(label), findsOneWidget);
      }
      await fill(tester, 'search', 'ab-008x');
      await tester.tap(find.byTooltip('Pesquisar cadastro'));
      await tester.pumpAndSettle();
      expect(find.text('AB-008X'), findsOneWidget);
      await doubleTapRow(tester, CadastroKind.motoristas, 'driver-id');
      expect(find.text('Consulta de motorista'), findsOneWidget);
      expect(byKey('cadastro-taxId'), findsNothing);
      expect(find.text('Documento legado'), findsNothing);
      expect(
        find.descendant(
          of: byKey('cadastro-uf'),
          matching: find.text('UF legada'),
        ),
        findsOneWidget,
      );
      expect(find.text('ABC1234'), findsOneWidget);
      expect(find.text('Salvar'), findsNothing);
      expect(byKey('driver-add-plate'), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: byKey('cadastro-name'),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<OutlinedButton>(byKey('cadastro-edit')).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'Vínculos em rascunho, exclusão de vínculo e proteção de cancelamento',
    (tester) async {
      await openCadastros(tester);
      await tab(tester, CadastroKind.motoristas);
      final state = memory(tester);
      await selectRow(tester, CadastroKind.motoristas, '1');
      await tester.tap(byKey('cadastro-edit'));
      await tester.pumpAndSettle();

      Future<void> addSecondPlate() async {
        await tester.tap(byKey('driver-add-plate'));
        await tester.pumpAndSettle();
        expect(byKey('driver-plate-option-1'), findsNothing);
        await tester.tap(byKey('driver-plate-option-2'));
        await tester.pumpAndSettle();
        expect(find.text('DEF4G56'), findsOneWidget);
      }

      await addSecondPlate();
      expect(state.records(CadastroKind.motoristas).first.linkedVehicleIds, {
        '1',
      });
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Alterando motorista'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Descartar alterações?'), findsOneWidget);
      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.text('DEF4G56'), findsOneWidget);
      await cancelForm(tester);
      expect(state.records(CadastroKind.motoristas).first.linkedVehicleIds, {
        '1',
      });

      await tester.tap(byKey('cadastro-edit'));
      await tester.pumpAndSettle();
      await addSecondPlate();
      await tester.tap(byKey('driver-unlink-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(state.records(CadastroKind.motoristas).first.linkedVehicleIds, {
        '2',
      });
      expect(state.records(CadastroKind.placas).map((vehicle) => vehicle.id), [
        '1',
        '2',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Falha de gravação mantém o modal e o nome digitado', (
    tester,
  ) async {
    await openCadastros(tester);
    await tab(tester, CadastroKind.motoristas);
    final state = memory(tester);
    await selectRow(tester, CadastroKind.motoristas, '1');
    await tester.tap(byKey('cadastro-edit'));
    await tester.pumpAndSettle();
    await fill(tester, 'name', 'Rascunho local');
    final previous = state.records(CadastroKind.motoristas).first;
    state.save(
      CadastroKind.motoristas,
      CadastroRecord(
        code: previous.code,
        registration: previous.registration,
        name: 'Atualizado em outra ação',
        linkedVehicleIds: previous.linkedVehicleIds,
      ),
      previous: previous,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'O cadastro foi atualizado. Reabra o formulário para continuar.',
      ),
      findsOneWidget,
    );
    expect(find.text('Rascunho local'), findsOneWidget);
    expect(
      state.records(CadastroKind.motoristas).first.name,
      'Atualizado em outra ação',
    );
    await cancelForm(tester);
  });

  testWidgets(
    'Operador consulta todos os cadastros implementados sem ações de escrita',
    (tester) async {
      await openCadastros(tester);
      memory(tester).permissions.currentUserId = 'carlos';
      await tester.pumpAndSettle();
      for (final kind in CadastroKind.values) {
        await tab(tester, kind);
        await selectRow(tester, kind, '1');
        expect(
          tester.widget<ElevatedButton>(byKey('cadastro-insert')).onPressed,
          isNull,
        );
        expect(
          tester.widget<OutlinedButton>(byKey('cadastro-edit')).onPressed,
          isNull,
        );
        expect(
          tester.widget<OutlinedButton>(byKey('cadastro-delete')).onPressed,
          isNull,
        );
      }
    },
  );

  test(
    'Serviço revalida permissões, modo, existência e unicidade do vínculo',
    () {
      final permissions = PermissionState();
      final demo = CadastrosMemory.mock(permissions);
      final real = CadastrosMemory.real(permissions);
      addTearDown(permissions.dispose);
      addTearDown(demo.dispose);
      addTearDown(real.dispose);
      Matcher failsWith(String message) => throwsA(
        isA<CadastroException>().having(
          (error) => error.message,
          'mensagem',
          contains(message),
        ),
      );

      for (final kind in CadastroKind.values) {
        final previous = demo.records(kind).first;
        final code = demo.nextCode(kind);
        final draft = CadastroRecord(
          code: code,
          registration: 'SIM-$code',
          name: 'Simulado',
        );
        permissions.currentUserId = 'carlos';
        expect(() => demo.save(kind, draft), failsWith('Sem permissão'));
        expect(
          () => demo.save(kind, previous, previous: previous),
          failsWith('Sem permissão'),
        );
        expect(() => demo.remove(kind, previous), failsWith('Sem permissão'));
        permissions.currentUserId = 'alisson';
        expect(
          () => real.save(kind, draft),
          failsWith('Integração de manutenção indisponível'),
        );
        expect(
          () => real.remove(kind, previous),
          failsWith('Integração de manutenção indisponível'),
        );
      }

      const drivers = CadastroKind.motoristas;
      final previous = demo.records(drivers).first;
      CadastroRecord driver(Set<String> ids, CadastroRecord original) =>
          CadastroRecord(
            code: original.code,
            registration: original.registration,
            name: original.name,
            linkedVehicleIds: ids,
          );

      permissions.setGrant(1, AppPermission.editDrivers, false);
      expect(
        () => demo.save(drivers, driver({'1'}, previous), previous: previous),
        failsWith('Sem permissão'),
      );
      permissions.setGrant(1, AppPermission.editDrivers, true);
      permissions.setGrant(1, AppPermission.manageDriverPlates, false);
      expect(
        () => demo.save(drivers, driver({'2'}, previous), previous: previous),
        failsWith('Sem permissão para manter vínculos'),
      );
      permissions.setGrant(1, AppPermission.manageDriverPlates, true);
      expect(
        () => demo.save(
          drivers,
          driver({'1', 'missing'}, previous),
          previous: previous,
        ),
        failsWith('placa cadastrada válida'),
      );

      final duplicate = CadastroRecord(
        code: demo.nextCode(CadastroKind.placas),
        plate: 'abc-1d23',
      );
      demo.save(CadastroKind.placas, duplicate);
      expect(
        () => demo.save(
          drivers,
          driver({'1', duplicate.id}, previous),
          previous: previous,
        ),
        failsWith('já está vinculada'),
      );
      final second = demo.records(drivers).last;
      demo.save(drivers, driver({'1'}, second), previous: second);
      expect(
        demo.records(drivers).map((driver) => driver.linkedVehicleIds),
        everyElement({'1'}),
      );
    },
  );

  testWidgets(
    'os quatro catálogos pesquisam e consultam a 800 por 600 sem edição',
    (tester) async {
      await openCadastros(tester, size: const Size(800, 600));
      for (final kind in CadastroKind.values.where((kind) => kind.isCatalog)) {
        await tab(tester, kind);
        final first = memory(tester).records(kind).first;
        await fill(tester, 'search', first.name);
        await tester.tap(find.byTooltip('Pesquisar cadastro'));
        await tester.pumpAndSettle();
        await selectRow(tester, kind, first.id);
        await tester.tap(byKey('cadastro-consult'));
        await tester.pumpAndSettle();
        expect(byKey('catalog-form'), findsOneWidget);
        expect(byKey('catalog-save'), findsNothing);
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: byKey('catalog-name'),
                  matching: find.byType(TextField),
                ),
              )
              .readOnly,
          isTrue,
        );
        if (kind == CadastroKind.operacoes) {
          for (final section in [
            'Dados gerais',
            'Tolerância associada',
            'Informações complementares associadas',
          ]) {
            expect(find.text(section), findsOneWidget);
          }
          final detail = find.byTooltip('Consultar associação').first;
          await tester.ensureVisible(detail);
          await tester.pumpAndSettle();
          await tester.tap(detail);
          await tester.pumpAndSettle();
          expect(find.text('Consultar associação'), findsOneWidget);
          expect(find.text('Confirmar associação'), findsNothing);
          await tester.tap(find.text('Fechar').last);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('itens permitem inserir, alterar e inativar na demonstração', (
    tester,
  ) async {
    await openCadastros(tester);
    const kind = CadastroKind.itens;
    await tab(tester, kind);
    await tester.tap(byKey('cadastro-insert'));
    await tester.pumpAndSettle();
    await tester.enterText(byKey('catalog-name'), 'Novo material');
    await tester.tap(byKey('catalog-save'));
    await tester.pumpAndSettle();
    final state = memory(tester);
    final inserted = state.records(kind).last;
    expect(inserted.name, 'Novo material');
    expect(inserted.active, isTrue);

    await tester.tap(byKey('cadastro-edit'));
    await tester.pumpAndSettle();
    await tester.enterText(byKey('catalog-name'), 'Material revisado');
    await tester.tap(byKey('catalog-save'));
    await tester.pumpAndSettle();
    expect(state.records(kind).last.name, 'Material revisado');

    await tester.tap(byKey('cadastro-delete'));
    await tester.pumpAndSettle();
    final confirmation = find.descendant(
      of: byKey('cadastro-delete-confirmation'),
      matching: find.text('Inativar'),
    );
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    final inactive = state.records(kind).last;
    expect(inactive.id, inserted.id);
    expect(inactive.active, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('associação fica no rascunho até o roteiro ser salvo', (
    tester,
  ) async {
    await openCadastros(tester);
    const kind = CadastroKind.operacoes;
    await tab(tester, kind);
    final state = memory(tester);
    final record = state.records(kind).first;
    final before = (record.catalog as OperationDetails).attributes.length;
    await selectRow(tester, kind, record.id);
    await tester.tap(byKey('cadastro-edit'));
    await tester.pumpAndSettle();

    Future<void> click(Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await click(byKey('catalog-add-binding'));
    await click(byKey('binding-Atributo'));
    await click(find.text('SIM-3 · Umidade informada').last);
    await click(byKey('binding-Momento de coleta'));
    await click(find.text('Ambas').last);
    final order = byKey('catalog-binding-order');
    await tester.ensureVisible(order);
    await tester.enterText(order, '3');
    await click(find.text('Confirmar associação'));
    expect(state.records(kind).first, same(record));
    await click(byKey('catalog-save'));

    final updated = state.records(kind).first.catalog as OperationDetails;
    expect(updated.attributes, hasLength(before + 1));
    expect(updated.attributes.last.attributeId, '3');
    expect(updated.attributes.last.phase, CollectionPhase.both);
    expect(tester.takeException(), isNull);
  });

  test('domínios dos atributos distinguem valores válidos e ausência', () {
    final date = DateTime(2026, 11, 26);
    for (final (definition, accepted, invalid)
        in <(AttributeDetails, Object, Object)>[
          (
            AttributeDetails(type: AttributeType.texto, maxLength: 4),
            'Café',
            'Sacaria',
          ),
          (AttributeDetails(type: AttributeType.inteiro, minimum: 0), 0, 1.1),
          (
            AttributeDetails(
              type: AttributeType.decimal,
              precision: 4,
              decimalPlaces: 2,
            ),
            0.15,
            0.001,
          ),
          (AttributeDetails(type: AttributeType.simNao), false, 'Não'),
          (
            AttributeDetails(
              type: AttributeType.listaValores,
              options: [(id: 'A', label: 'Aprovado')],
            ),
            'A',
            'Aprovado',
          ),
          (AttributeDetails(type: AttributeType.peso, minimum: 0), 0, -1),
          (
            AttributeDetails(type: AttributeType.data, startDate: date),
            date,
            DateTime(2026, 11, 25),
          ),
        ]) {
      expect(definition.issue, isNull);
      expect(
        definition.accepts(accepted),
        isTrue,
        reason: definition.type.label,
      );
      expect(
        definition.accepts(invalid),
        isFalse,
        reason: definition.type.label,
      );
      expect(definition.accepts(null), isFalse);
    }
  });

  test(
    'serviço exige referência válida, distingue dispensa e sinaliza conflitos',
    () {
      final permissions = PermissionState();
      final state = CadastrosMemory.mock(permissions);
      addTearDown(permissions.dispose);
      addTearDown(state.dispose);
      const operations = CadastroKind.operacoes;
      const tolerances = CadastroKind.tolerancias;
      final rule = state.records(tolerances);
      expect((rule.first.catalog as ToleranceDetails).loss, 0);
      expect((rule.last.catalog as ToleranceDetails).calculates, isFalse);

      CadastroRecord draft(OperationDetails details) => CadastroRecord(
        code: state.nextCode(operations),
        name: 'Roteiro demonstrativo',
        catalog: details,
      );
      bool savedWith(OperationDetails details) {
        state.save(operations, draft(details));
        return (state.records(operations).last.catalog as OperationDetails)
            .incompleteRules;
      }

      expect(
        () => savedWith(
          OperationDetails(
            nature: OperationNature.interna,
            standard: '1',
            bag: '2',
          ),
        ),
        throwsA(isA<CadastroException>()),
      );
      expect(
        () => savedWith(
          OperationDetails(
            nature: OperationNature.interna,
            standard: 'inexistente',
          ),
        ),
        throwsA(isA<CadastroException>()),
      );
      expect(
        savedWith(OperationDetails(nature: OperationNature.interna)),
        isTrue,
      );
      expect(
        savedWith(
          OperationDetails(nature: OperationNature.interna, standard: '3'),
        ),
        isFalse,
      );

      AttributeBinding binding({String? product, String? packaging}) => (
        attributeId: '1',
        required: false,
        phase: CollectionPhase.both,
        editable: false,
        printOnTicket: false,
        order: 1,
        productId: product,
        packaging: packaging,
      );
      final general = binding();
      final product = binding(product: '1');
      final bag = binding(packaging: 'BAG');
      final conflict = OperationDetails(
        nature: OperationNature.outro,
        standard: '1',
        attributes: [general, product, bag],
      );
      expect(conflict.hasContextConflict, isTrue);
      state.save(operations, draft(conflict));
      expect(
        () => savedWith(
          OperationDetails(
            nature: OperationNature.outro,
            attributes: [general, general],
          ),
        ),
        throwsA(isA<CadastroException>()),
      );
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
        for (final kind in CadastroKind.values.where(
          (kind) => !kind.isCatalog,
        )) {
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
