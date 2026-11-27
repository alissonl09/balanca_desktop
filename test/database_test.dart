import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:balanca_desktop/core/database/database_manager.dart';
import 'package:balanca_desktop/core/database/database_migrations.dart';
import 'package:balanca_desktop/core/database/ddl_policy.dart';
import 'package:balanca_desktop/core/offline/sqlite_pesagem_store.dart';
import 'package:balanca_desktop/core/offline/offline_models.dart';
import 'package:balanca_desktop/core/offline/offline_station.dart';
import 'package:balanca_desktop/core/offline/pre_ticket_source.dart';

void main() {
  late Directory root;
  late DatabaseManager manager;
  Future<DatabaseManager> open({
    List<DatabaseMigration> migrations = databaseMigrations,
    int retention = 10,
  }) async {
    final db = DatabaseManager(
      path: p.join(root.path, 'data', 'balanca.db'),
      migrations: migrations,
      backupRetention: retention,
    );
    addTearDown(db.close);
    await db.open();
    return db;
  }

  LocalWeighing weighing(
    String id, {
    WeighingPhase phase = WeighingPhase.fechada,
  }) => LocalWeighing(
    idLocal: id,
    preTicketId: 'ticket-$id',
    plate: 'ABC1D23',
    createdAt: DateTime.utc(2026),
    phase: phase,
    firstReading: 100,
    secondReading: 60,
    events: [
      SyncEvent(
        idLocal: 'event-$id',
        tipoEvento: SyncEventType.aberturaPesagem,
        idPesagemLocal: id,
        payload: {'reading': 100},
        dataHoraCriacao: DateTime.utc(2026),
        ordem: 1,
      ),
    ],
  );
  Future<void> apply(String content, {String name = 'support.sql'}) => manager
      .executeScript(SqlScriptPreview(name, content), operator: 'support-test');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('balanca_sqlite_test_');
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    manager = await open();
  });

  test(
    'cria automaticamente, configura durabilidade e reabre após reinício',
    () async {
      expect(File(manager.path).existsSync(), isTrue);
      final status = await manager.status();
      expect(status['schema'], 1);
      expect(status['foreignKeys'], isTrue);
      expect(status['journal'], 'wal');
      expect(status['synchronous'], 2);
      expect((await manager.history()).single['origin'], 'MIGRATION');
      await manager.close();
      manager = await open();
      expect((await manager.history()).length, 1);
      expect(await manager.checkIntegrity(), ['ok']);
    },
  );

  test(
    'diagnóstico consulta o banco em uso e não inicializa outro arquivo',
    () async {
      final path = p.join(root.path, 'outro', 'balanca.db');
      final unopened = DatabaseManager(path: path);
      expect(await unopened.status(), {'available': false, 'path': path});
      expect(await Directory(p.dirname(path)).exists(), isFalse);

      await SqlitePesagemStore(manager).save(weighing('diagnostico'));
      final records = await manager.loadWeighings();
      final history = await manager.history();
      final status = await manager.status();
      expect(status['available'], isTrue);
      expect(status['path'], manager.path);
      expect(status['pending'], 1);
      expect(status['integrity'], isNull);
      expect(await manager.loadWeighings(), records);
      expect(await manager.history(), history);

      await manager.close();
      manager = await open();
      expect(await manager.loadWeighings(), records);
      expect((await manager.status())['path'], status['path']);
    },
  );

  test('migration pendente aplica em ordem e registra versão/hash', () async {
    await manager.close();
    manager = await open(
      migrations: [
        ...databaseMigrations,
        const DatabaseMigration(
          2,
          'V002__support',
          'CREATE TABLE SUPPORT_TEST(id INTEGER PRIMARY KEY);',
        ),
      ],
    );
    expect((await manager.status())['schema'], 2);
    expect((await manager.history()).first['version_before'], 1);
    await manager.close();
    manager = await open(
      migrations: [
        ...databaseMigrations,
        const DatabaseMigration(
          2,
          'V002__support',
          'CREATE TABLE SUPPORT_TEST(id INTEGER PRIMARY KEY);',
        ),
      ],
    );
    expect((await manager.history()).length, 2);
  });

  test('migration inválida faz rollback do schema e da versão', () async {
    await manager.close();
    final failed = DatabaseManager(
      path: manager.path,
      migrations: [
        ...databaseMigrations,
        const DatabaseMigration(
          2,
          'V002__failure',
          'CREATE TABLE SHOULD_ROLLBACK(id); INVALID SQL;',
        ),
      ],
    );
    addTearDown(failed.close);
    await expectLater(failed.open(), throwsA(isA<DatabaseIssue>()));
    await failed.close();
    manager = await open();
    expect((await manager.status())['schema'], 1);
    final raw = sqlite3.open(manager.path, mode: OpenMode.readOnly);
    addTearDown(raw.close);
    expect(
      raw.select("SELECT name FROM sqlite_schema WHERE name='SHOULD_ROLLBACK'"),
      isEmpty,
    );
    expect((await manager.history()).first['status'], 'FAILED');
  });

  test(
    'agregado e outbox persistem juntos e suportam múltiplos acessos',
    () async {
      final store = SqlitePesagemStore(manager);
      await Future.wait(List.generate(25, (i) => store.save(weighing('w$i'))));
      expect((await store.loadAll()).length, 25);
      expect((await manager.status())['pending'], 25);
      await manager.close();
      manager = await open();
      final restored = await SqlitePesagemStore(manager).loadAll();
      expect(restored.first.events.single.payload, {'reading': 100});
      expect(restored.first.firstReading, 100);
      // Evento de outra pesagem aborta inclusive a inserção do pai.
      final broken = weighing('bad').copyWith(events: weighing('other').events);
      await expectLater(
        SqlitePesagemStore(manager).save(broken),
        throwsA(isA<DatabaseIssue>()),
      );
      expect(
        (await SqlitePesagemStore(
          manager,
        ).loadAll()).any((w) => w.idLocal == 'bad'),
        isFalse,
      );
    },
  );

  test('station existente usa SQLite sem alterar sequência offline', () async {
    final station = OfflineStation(
      store: SqlitePesagemStore(manager),
      canOpenOffline: (_) => true,
    );
    addTearDown(station.dispose);
    final ticket = KnownPreTicket(id: 'known', plate: 'ABC1D23');
    final w = await station.create(ticket);
    await station.open(w.idLocal, 100, ticket: ticket);
    await station.close(w.idLocal, 60);
    final recovered = OfflineStation(store: SqlitePesagemStore(manager));
    addTearDown(recovered.dispose);
    await recovered.load();
    expect(recovered.weighings.single.phase, WeighingPhase.fechada);
    expect(recovered.pendingCount, 2);
    expect(recovered.events.last.dependeDe, recovered.events.first.idLocal);
  });

  test('backup íntegro captura WAL e retenção centralizada', () async {
    await manager.close();
    manager = await open(retention: 2);
    await SqlitePesagemStore(manager).save(weighing('durable'));
    final backup = await manager.backup();
    final raw = sqlite3.open(backup, mode: OpenMode.readOnly);
    expect(raw.select('PRAGMA integrity_check').first.values.first, 'ok');
    expect(raw.select('SELECT * FROM BAL_PESAGEM').length, 1);
    raw.close();
    await manager.backup();
    await manager.backup();
    expect((await manager.backups()).length, 2);
    expect((await manager.status())['lastBackup'], isNotNull);
  });

  test('DDL válido exige backup e registra hash; duplicação bloqueada', () async {
    const sql =
        'CREATE TABLE SUPPORT_INFO(id INTEGER PRIMARY KEY, value TEXT);'
        'ALTER TABLE SUPPORT_INFO ADD COLUMN note TEXT; CREATE INDEX SUPPORT_NOTE ON SUPPORT_INFO(note);';
    await apply(sql);
    expect((await manager.backups()).length, 1);
    final history = await manager.history();
    expect(history.first['origin'], 'MANUAL');
    expect(history.first['status'], 'SUCCESS');
    expect((history.first['hash'] as String).length, 64);
    await expectLater(apply(sql), throwsA(isA<DatabaseIssue>()));
    expect((await manager.history()).first['status'], 'FAILED');
    await apply('DROP INDEX SUPPORT_NOTE;');
  });

  test('DDL inválido faz rollback de todos os comandos', () async {
    await expectLater(
      apply('CREATE TABLE ROLLED_BACK(id INTEGER); CREATE TABLE BROKEN(;'),
      throwsA(isA<DatabaseIssue>()),
    );
    final raw = sqlite3.open(manager.path, mode: OpenMode.readOnly);
    addTearDown(raw.close);
    expect(
      raw.select("SELECT name FROM sqlite_schema WHERE name='ROLLED_BACK'"),
      isEmpty,
    );
    expect((await manager.backups()).length, 1);
    expect((await manager.history()).first['status'], 'FAILED');
  });

  test('backup falhando impede execução do DDL', () async {
    final directory = Directory(p.join(root.path, 'backup'));
    directory.deleteSync();
    File(directory.path).writeAsStringSync('unavailable');
    await expectLater(
      apply('CREATE TABLE NOT_APPLIED(id INTEGER);'),
      throwsA(isA<DatabaseIssue>()),
    );
    final raw = sqlite3.open(manager.path, mode: OpenMode.readOnly);
    addTearDown(raw.close);
    expect(
      raw.select("SELECT name FROM sqlite_schema WHERE name='NOT_APPLIED'"),
      isEmpty,
    );
  });

  test(
    'restaura com backup de segurança, reabre e verifica integridade',
    () async {
      await SqlitePesagemStore(manager).save(weighing('original'));
      final backup = await manager.backup();
      await SqlitePesagemStore(manager).save(weighing('later'));
      var reloaded = false;
      manager.onRestored = () async {
        reloaded = true;
      };
      await manager.restore(backup, operator: 'support-test');
      expect(reloaded, isTrue);
      expect(
        (await SqlitePesagemStore(manager).loadAll()).map((w) => w.idLocal),
        ['original'],
      );
      expect(await manager.checkIntegrity(), ['ok']);
      expect((await manager.backups()).length, 2);
      expect((await manager.history()).first['origin'], 'RESTORE');
    },
  );

  test('backup corrompido ou externo não substitui dados atuais', () async {
    await SqlitePesagemStore(manager).save(weighing('preserved'));
    final bad = File(p.join(root.path, 'backup', 'balanca_corrupt.db'))
      ..writeAsStringSync('not sqlite');
    await expectLater(
      manager.restore(bad.path, operator: 'support'),
      throwsA(isA<DatabaseIssue>()),
    );
    await expectLater(
      manager.restore(p.join(root.path, 'external.db'), operator: 'support'),
      throwsA(isA<DatabaseIssue>()),
    );
    expect(
      (await SqlitePesagemStore(manager).loadAll()).single.idLocal,
      'preserved',
    );
  });

  test('falha de migration após restaurar recupera banco anterior', () async {
    final old = await manager.backup();
    // V2 funciona no banco atual; o snapshot antigo não contém SUPPORT_REQUIRED.
    await apply('CREATE TABLE SUPPORT_REQUIRED(id INTEGER);');
    await manager.close();
    manager = await open(
      migrations: [
        ...databaseMigrations,
        const DatabaseMigration(
          2,
          'V002__requires_support',
          'ALTER TABLE SUPPORT_REQUIRED ADD COLUMN value TEXT;',
        ),
      ],
    );
    await SqlitePesagemStore(manager).save(weighing('survives'));
    await expectLater(
      manager.restore(old, operator: 'support'),
      throwsA(isA<DatabaseIssue>()),
    );
    expect(
      (await SqlitePesagemStore(manager).loadAll()).single.idLocal,
      'survives',
    );
    expect((await manager.status())['schema'], 2);
    expect(await manager.checkIntegrity(), ['ok']);
  });

  test(
    'manutenção pesada bloqueada por callback e por pesagem durável',
    () async {
      manager.isOperationActive = () => true;
      await expectLater(manager.vacuum(), throwsA(isA<DatabaseIssue>()));
      await expectLater(
        apply('CREATE TABLE DENIED(id);'),
        throwsA(isA<DatabaseIssue>()),
      );
      manager.isOperationActive = () => false;
      await SqlitePesagemStore(manager)
          .save(weighing('open', phase: WeighingPhase.aberta));
      await expectLater(manager.vacuum(), throwsA(isA<DatabaseIssue>()));
      await expectLater(
        apply('CREATE TABLE DENIED(id);'),
        throwsA(isA<DatabaseIssue>()),
      );
      expect(await manager.checkIntegrity(), ['ok']);
      await manager.backup(); // backup online não é destrutivo
    },
  );

  test('otimização e compactação em estação ociosa', () async {
    await manager.optimize();
    await manager.vacuum();
    expect(await manager.checkIntegrity(), ['ok']);
  });

  test('DDL aditivo preserva gravação dos modelos atuais', () async {
    await apply('ALTER TABLE BAL_PESAGEM ADD COLUMN support_note TEXT;');
    await SqlitePesagemStore(manager).save(weighing('after-ddl'));
    expect(
      (await SqlitePesagemStore(manager).loadAll()).single.idLocal,
      'after-ddl',
    );
  });

  test('uma segunda conexão gerenciada não assume a mesma estação', () async {
    final duplicate = DatabaseManager(path: manager.path);
    addTearDown(duplicate.close);
    await expectLater(duplicate.open(), throwsA(isA<DatabaseIssue>()));
    expect(await manager.checkIntegrity(), ['ok']);
  });

  test(
    'reinício recupera restauração interrompida usando snapshot de segurança',
    () async {
      await SqlitePesagemStore(manager).save(weighing('safe'));
      final safety = await manager.backup();
      await SqlitePesagemStore(manager).save(weighing('uncertain'));
      await manager.close();
      File('${manager.path}.restore.json').writeAsStringSync(
        jsonEncode({
          'safety': safety,
          'hash': sha256.convert(File(safety).readAsBytesSync()).toString(),
        }),
        flush: true,
      );
      manager = await open();
      expect(
        (await SqlitePesagemStore(manager).loadAll()).single.idLocal,
        'safe',
      );
      expect(File('${manager.path}.restore.json').existsSync(), isFalse);
    },
  );
}
