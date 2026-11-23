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
  List<Map<String, Object?>> seedWeighings = [];
  bool failLoading = false;
  @override
  Future<List<Map<String, Object?>>> loadWeighings() async {
    if (failLoading) throw const DatabaseIssue('Falha de leitura local.');
    return seedWeighings;
  }

  @override
  Future<Map<String, Object?>> status() async => {
    'available': available,
    'path': path,
    'schema': 1,
    'sqlite': '3.test',
    'bytes': 1024 * 1024,
    'journal': 'wal',
    'foreignKeys': true,
    'synchronous': 2,
    'pending': 3,
  };
  @override
  Future<List<Map<String, Object?>>> history() async => [];
  @override
  Future<List<String>> checkIntegrity() async => ['ok'];
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
    tester.view.physicalSize = const Size(1100, 1000);
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
    expect(find.text('SQLite operacional'), findsOneWidget);
    expect(find.text('Schema: v1'), findsOneWidget);
    expect(find.text('Eventos pendentes: 3'), findsOneWidget);
    expect(find.textContaining(database.path), findsOneWidget);
    await tap(tester, 'integrity');
    expect(find.text('Banco íntegro.'), findsOneWidget);
    await tap(tester, 'backup');
    expect(database.backupsCreated, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview de arquivo e confirmação forte antes de executar DDL', (
    tester,
  ) async {
    await mount(tester);
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
    for (final name in [
      'backup',
      'restore',
      'select-sql',
      'integrity',
      'vacuum',
    ]) {
      expect(tester.widget<OutlinedButton>(key(name)).onPressed, isNull);
    }
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
