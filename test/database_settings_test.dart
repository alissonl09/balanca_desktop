import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/database/database_manager.dart';
import 'package:balanca_desktop/core/database/ddl_policy.dart';
import 'package:balanca_desktop/core/permissions/permission_models.dart';
import 'package:balanca_desktop/features/configuracoes/database_settings.dart';
import 'package:balanca_desktop/app/balanca_app.dart';
import 'package:balanca_desktop/features/pesagem/operation_lookup.dart';

class _MaintenanceDatabase extends DatabaseManager {
  _MaintenanceDatabase() : super(path: r'C:\Local\Balanca\data\balanca.db') {
    available = true;
  }
  int backupsCreated = 0, scriptsExecuted = 0, restores = 0;
  int opens = 0, statusReads = 0, integrityChecks = 0, historyReads = 0;
  List<Map<String, Object?>> seedWeighings = [];
  List<Map<String, Object?>> seedHistory = [];
  bool failLoading = false;
  bool failStatus = false;
  @override
  Future<List<Map<String, Object?>>> loadWeighings() async {
    if (failLoading) throw const DatabaseIssue('Falha de leitura local.');
    return seedWeighings;
  }

  @override
  Future<void> open() async => opens++;
  @override
  Future<Map<String, Object?>> status() async {
    statusReads++;
    if (failStatus) throw const DatabaseIssue('Falha de consulta.');
    return {
      'available': available,
      'path': path,
      'schema': 1,
      'bytes': 1024 * 1024,
      'journal': 'wal',
      'pending': 3,
    };
  }

  @override
  Future<List<Map<String, Object?>>> history() async {
    historyReads++;
    return seedHistory;
  }

  @override
  Future<List<String>> checkIntegrity() async {
    integrityChecks++;
    return ['ok'];
  }

  @override
  Future<String> backup() async {
    backupsCreated++;
    return 'backup.db';
  }

  @override
  Future<List<Map<String, Object?>>> backups() async => [
    {
      'path': r'C:\Local\Balanca\backup\balanca_20261123143500.db',
      'bytes': 1024,
      'at': '2026-11-23T17:35:00Z',
    },
  ];
  @override
  Future<void> executeScript(
    SqlScriptPreview preview, {
    required String operator,
  }) async {
    scriptsExecuted++;
  }

  @override
  Future<void> restore(String backupPath, {required String operator}) async {
    restores++;
  }
}

void main() {
  late _MaintenanceDatabase database;
  late PermissionState permissions;
  Finder key(String key) => find.byKey(ValueKey('db-$key'));
  Future<void> tap(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.pumpAndSettle();
    await tester.tap(key(name));
    if (name == 'apply-sql' || name == 'restore') {
      await tester.pump(const Duration(milliseconds: 350));
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    String sql = 'CREATE TABLE SUPPORT_TEST(id INTEGER);',
  }) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DatabaseSettings(
              database: database,
              permissions: permissions,
              selectSqlFile: () async => XFile.fromData(
                utf8.encode(sql),
                name: 'support.sql',
                path: 'support.sql',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    database = _MaintenanceDatabase();
    permissions = PermissionState();
    addTearDown(permissions.dispose);
  });

  testWidgets('status amigável, caminho real, integridade e backup', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Disponível'), findsOneWidget);
    expect(find.textContaining(database.path), findsOneWidget);
    expect(tester.widget<SelectableText>(key('path')).data, database.path);
    expect(key('test-connection').hitTestable(), findsOneWidget);
    expect(key('backup').hitTestable(), findsOneWidget);
    expect(key('restore').hitTestable(), findsOneWidget);
    expect(find.textContaining('Schema v1'), findsNothing);
    expect(find.textContaining('Eventos pendentes'), findsNothing);
    expect(key('select-sql'), findsNothing);
    expect(database.historyReads, 0);
    await tap(tester, 'test-connection');
    expect(find.text('Conexão com o banco local verificada.'), findsOneWidget);
    expect(database.statusReads, 2);
    expect(database.opens, 0);
    expect(database.integrityChecks, 0);
    expect(database.backupsCreated, 0);
    await tap(tester, 'advanced');
    expect(find.textContaining('Schema v1'), findsOneWidget);
    expect(find.textContaining('Journal'), findsNothing);
    await tap(tester, 'history');
    expect(database.historyReads, 1);
    await tap(tester, 'integrity');
    expect(find.text('Banco íntegro.'), findsOneWidget);
    await tap(tester, 'backup');
    expect(database.backupsCreated, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teste de conexão informa falha sem tentar abrir o banco', (
    tester,
  ) async {
    await mount(tester);
    database.failStatus = true;
    await tap(tester, 'test-connection');
    expect(find.text('Indisponível'), findsOneWidget);
    expect(
      find.text('Banco local indisponível para consulta.'),
      findsOneWidget,
    );
    expect(find.text('Conexão com o banco local verificada.'), findsNothing);
    expect(database.opens, 0);
    expect(database.backupsCreated, 0);
    expect(tester.widget<OutlinedButton>(key('backup')).onPressed, isNull);
    database.failStatus = false;
    database.available = false;
    await tap(tester, 'test-connection');
    expect(find.text('Indisponível'), findsOneWidget);
    expect(database.opens, 0);
  });

  testWidgets('histórico separa o resultado dos detalhes técnicos', (
    tester,
  ) async {
    database.seedHistory = [
      {
        'id': 3,
        'origin': 'RESTORE',
        'status': 'SUCCESS',
        'filename': 'backup.db',
        'operator': 'suporte',
        'version_before': 1,
        'version_after': 2,
      },
      {
        'id': 2,
        'origin': 'MANUAL',
        'status': 'FAILED',
        'filename': 'manutencao.sql',
        'executed_at': '2026-11-23T14:30:00',
        'operator': 'alisson',
        'version_before': 1,
        'version_after': 1,
      },
      {
        'id': 1,
        'origin': 'MIGRATION',
        'status': 'SUCCESS',
        'filename': 'V001__infraestrutura_e_contingencia',
        'operator': 'APPLICATION',
        'version_before': 0,
        'version_after': 1,
      },
      {'id': 0},
    ];
    await mount(tester);
    await tap(tester, 'advanced');
    await tap(tester, 'history');

    expect(find.text('Concluída'), findsNWidgets(2));
    expect(find.text('Falhou'), findsOneWidget);
    expect(find.text('Resultado desconhecido'), findsOneWidget);
    expect(find.text('Data e hora: 23/11/2026 14:30'), findsOneWidget);
    expect(find.textContaining('FAILED'), findsNothing);
    expect(find.textContaining('manutencao.sql'), findsNothing);

    Future<void> expand(String operation) async {
      final title = find.text(operation);
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();
    }

    await expand('Execução de script SQL');
    expect(find.text('Arquivo: manutencao.sql'), findsOneWidget);
    expect(
      find.text('Executado por: Alisson Rodrigues Romano (alisson)'),
      findsOneWidget,
    );
    expect(find.text('Estrutura do banco na versão 1.'), findsOneWidget);

    await expand('Restauração de backup');
    expect(find.text('Executado por: suporte'), findsOneWidget);
    expect(
      find.text('Versão do backup: 1. Versão após a restauração: 2.'),
      findsOneWidget,
    );

    await expand('Configuração inicial do banco');
    expect(find.text('Executado por: Aplicativo'), findsOneWidget);
    expect(find.text('Estrutura do banco criada na versão 1.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview de arquivo e confirmação forte antes de executar DDL', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'advanced');
    await tap(tester, 'select-sql');
    expect(find.text('Arquivo: support.sql'), findsOneWidget);
    expect(find.textContaining('1 comandos'), findsWidgets);
    expect(database.scriptsExecuted, 0);
    await tap(tester, 'apply-sql');
    expect(tester.widget<FilledButton>(key('confirm')).onPressed, isNull);
    await tester.enterText(key('confirm-phrase'), 'APLICAR');
    await tester.pump();
    await tester.tap(key('confirm'));
    await tester.pumpAndSettle();
    expect(database.scriptsExecuted, 1);
  });

  testWidgets('script bloqueado não oferece execução', (tester) async {
    await mount(tester, sql: 'DROP TABLE BAL_PESAGEM;');
    await tap(tester, 'advanced');
    await tap(tester, 'select-sql');
    expect(find.textContaining('Operação bloqueada:'), findsOneWidget);
    expect(key('apply-sql'), findsNothing);
    expect(database.scriptsExecuted, 0);
  });

  testWidgets('permissões existentes protegem as ações administrativas', (
    tester,
  ) async {
    permissions.currentUserId = 'carlos';
    await mount(tester);
    await tap(tester, 'advanced');
    for (final name in [
      'test-connection',
      'backup',
      'restore',
      'select-sql',
      'integrity',
      'vacuum',
    ]) {
      expect(tester.widget<OutlinedButton>(key(name)).onPressed, isNull);
    }
  });

  testWidgets('restauração revalida a permissão após a confirmação', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'restore');
    await tester.tap(find.text('balanca_20261123143500.db'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(key('confirm-phrase'), 'RESTAURAR');
    await tester.pump();
    permissions.setGrant(1, AppPermission.restoreDatabase, false);
    await tester.tap(key('confirm'));
    await tester.pumpAndSettle();
    expect(database.restores, 0);
    expect(find.text('Sem permissão para esta operação.'), findsOneWidget);
  });

  testWidgets('restauração mostra metadados e exige RESTAURAR', (tester) async {
    await mount(tester);
    await tap(tester, 'restore');
    await tester.tap(find.text('balanca_20261123143500.db'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('inclusive eventos pendentes'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('confirm')).onPressed, isNull);
    await tester.enterText(key('confirm-phrase'), 'RESTAURAR');
    await tester.pump();
    await tester.tap(key('confirm'));
    await tester.pumpAndSettle();
    expect(database.restores, 1);
  });

  testWidgets('aplicação carrega pendências SQLite mesmo iniciando offline', (
    tester,
  ) async {
    database.seedWeighings = [
      {
        'id': 'w',
        'pre_ticket_id': 'p',
        'plate': 'ABC1D23',
        'created_at': '2026-11-23T12:00:00Z',
        'phase': 'fechada',
        'first_reading': 100.0,
        'second_reading': 60.0,
        'events': [
          {
            'id': 'e',
            'weighing_id': 'w',
            'type': 'aberturaPesagem',
            'payload': '{}',
            'created_at': '2026-11-23T12:00:00Z',
            'sequence': 1,
            'depends_on': null,
            'status': 'pendente',
            'attempts': 0,
            'last_error': null,
            'remote_id': null,
          },
        ],
      },
    ];
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      BalancaApp(
        database: database,
        lookupService: const DemoOperationLookupService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline · 1 pendências'), findsOneWidget);
  });

  testWidgets('aba Banco de Dados usa ações próprias em 1366 por 768', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      BalancaApp(
        database: database,
        lookupService: const DemoOperationLookupService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-config')));
    await tester.pumpAndSettle();
    final tab = find.byKey(const ValueKey('settings-tab-database'));
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(key('test-connection').hitTestable(), findsOneWidget);
    expect(key('backup').hitTestable(), findsOneWidget);
    expect(key('restore').hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('save-settings')), findsNothing);
    expect(tester.takeException(), isNull);
    final general = find.byKey(const ValueKey('settings-tab-general'));
    await tester.ensureVisible(general);
    await tester.pumpAndSettle();
    await tester.tap(general);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-settings')), findsOneWidget);
  });

  testWidgets('falha de leitura durável não libera pesagem em memória', (
    tester,
  ) async {
    database.failLoading = true;
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      BalancaApp(
        database: database,
        lookupService: const DemoOperationLookupService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Não foi possível carregar as pesagens locais.'),
      findsOneWidget,
    );
  });
}
