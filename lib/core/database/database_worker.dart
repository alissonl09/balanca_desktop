import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'database_migrations.dart';
import 'ddl_policy.dart';

// Apenas este isolate possui a conexão. Repositories e telas nunca a recebem.
void databaseWorker(SendPort ready) {
  final port = ReceivePort();
  final worker = _Worker();
  var tail = Future<void>.value();
  ready.send(port.sendPort);
  port.listen((dynamic message) {
    final request = message as List;
    final reply = request[0] as SendPort;
    tail = tail.then((_) async {
      try {
        reply.send({
          'value': await worker.run(request[1] as String, request[2] as Map),
        });
      } catch (e, st) {
        worker.log(e, st);
        reply.send({'error': e.toString()});
      }
      if (request[1] == 'close') port.close();
    });
  });
}

class _Worker {
  Database? _db;
  Database get db => _db ?? (throw StateError('Banco indisponível.'));
  late String path, backupDirectory;
  late List<DatabaseMigration> migrations;
  late int retention;
  RandomAccessFile? _lock;
  static const applicationId = 1111575601;

  void log(Object error, StackTrace stack) {
    try {
      File(p.join(p.dirname(path), 'database-maintenance.log'))
          .writeAsStringSync(
            '${DateTime.now().toUtc().toIso8601String()} $error\n$stack\n',
            mode: FileMode.append,
            flush: true,
          );
    } catch (_) {
      /* O erro original continua sendo devolvido. */
    }
  }

  Future<Object?> run(String operation, Map args) async {
    switch (operation) {
      case 'open':
        path = args['path'] as String;
        backupDirectory = p.join(p.dirname(p.dirname(path)), 'backup');
        retention = args['retention'] as int;
        migrations = (args['migrations'] as List).cast<DatabaseMigration>();
        Directory(p.dirname(path)).createSync(recursive: true);
        Directory(backupDirectory).createSync(recursive: true);
        try {
          _db?.close();
          _db = null;
          _lock?.closeSync();
          _lock = null;
          _lock ??= File('$path.station-lock').openSync(mode: FileMode.append);
          _lock!.lockSync(FileLock.exclusive);
          final recovering = File('$path.restore.json').existsSync();
          if (recovering) await _recoverInterruptedRestore();
          _open();
          if (recovering) File('$path.restore.json').deleteSync();
        } catch (_) {
          _db?.close();
          _db = null;
          _lock?.closeSync();
          _lock = null;
          rethrow;
        }
        return _status();
      case 'status':
        return _status();
      case 'integrity':
        final result = _integrity(db);
        _meta('integrity', jsonEncode({'at': _now(), 'result': result}));
        return result;
      case 'backup':
        return await _backup();
      case 'backups':
        return _backups();
      case 'history':
        return db
            .select(
              'SELECT * FROM BAL_DB_SCRIPT_HIST ORDER BY id DESC LIMIT 100',
            )
            .map((r) => Map<String, Object?>.from(r))
            .toList();
      case 'optimize':
        db.execute('PRAGMA optimize');
        return null;
      case 'vacuum':
        _requireIdle();
        db.execute('VACUUM');
        return null;
      case 'ddl':
        return await _executeScript(args);
      case 'restore':
        return await _restore(
          args['path'] as String,
          args['operator'] as String,
        );
      case 'load':
        return _load();
      case 'save':
        _save(args);
        return null;
      case 'close':
        _db?.close();
        _db = null;
        _lock?.closeSync();
        _lock = null;
        return null;
      default:
        throw ArgumentError('Operação de banco desconhecida.');
    }
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
  void _open() {
    _db = sqlite3.open(path);
    db.execute('PRAGMA busy_timeout=5000');
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute('PRAGMA trusted_schema=OFF');
    // SQLITE_DBCONFIG_DEFENSIVE: desabilita operações que corrompem o schema.
    db.config.setIntConfig(1010, 1);
    db.config.doubleQuotedStringLiterals = false;
    if (db.userVersion > migrations.length) {
      throw StateError('Schema mais novo que esta aplicação.');
    }
    final existingId = db.select('PRAGMA application_id').first.values.first;
    if (db.userVersion > 0 && existingId != applicationId) {
      throw StateError('Arquivo não pertence à aplicação da balança.');
    }
    for (var i = 0; i < migrations.length; i++) {
      final m = migrations[i];
      if (m.version != i + 1) {
        throw StateError('Migrations devem ser sequenciais.');
      }
      final hash = sha256.convert(utf8.encode(m.sql)).toString();
      if (m.version <= db.userVersion) {
        final history = db.select(
          'SELECT hash FROM BAL_SCHEMA_VERSION WHERE version=?',
          [m.version],
        );
        if (history.isEmpty || history.first['hash'] != hash) {
          throw StateError('Migration aplicada foi alterada.');
        }
        continue;
      }
      final before = db.userVersion;
      try {
        _transaction(() {
          db.execute(m.sql);
          db.execute('INSERT INTO BAL_SCHEMA_VERSION VALUES(?,?,?,?,?)', [
            m.version,
            m.name,
            _now(),
            'SUCCESS',
            hash,
          ]);
          db.userVersion = m.version;
          db.execute('PRAGMA application_id=$applicationId');
          _history(
            m.name,
            hash,
            before,
            m.version,
            'SUCCESS',
            null,
            'APPLICATION',
            'MIGRATION',
          );
        });
      } catch (e) {
        // V001 pode falhar antes da existência do histórico. Nesse caso, log local.
        if (before > 0) {
          _history(
            m.name,
            hash,
            before,
            before,
            'FAILED',
            e.toString(),
            'APPLICATION',
            'MIGRATION',
          );
        }
        rethrow;
      }
    }
  }

  T _transaction<T>(T Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final value = body();
      db.execute('COMMIT');
      return value;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _meta(String key, String value) => db.execute(
    'INSERT INTO BAL_DB_META VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
  void _history(
    String file,
    String hash,
    int before,
    int after,
    String status,
    String? error,
    String operator,
    String origin,
  ) => db.execute(
    'INSERT INTO BAL_DB_SCRIPT_HIST(filename,hash,executed_at,version_before,version_after,status,error,operator,origin) VALUES(?,?,?,?,?,?,?,?,?)',
    [file, hash, _now(), before, after, status, error, operator, origin],
  );

  List<String> _integrity(Database database) => [
    ...database
        .select('PRAGMA integrity_check')
        .map((r) => '${r.values.first}'),
    if (database.select('PRAGMA foreign_key_check').isNotEmpty)
      'Referências inconsistentes.',
  ];
  bool _valid(List<String> result) =>
      result.length == 1 && result.first == 'ok';

  Map<String, Object?> _status() {
    final meta = {
      for (final r in db.select('SELECT * FROM BAL_DB_META'))
        r['key'] as String: r['value'],
    };
    var bytes = 0;
    for (final name in [path, '$path-wal', '$path-shm']) {
      final f = File(name);
      if (f.existsSync()) bytes += f.lengthSync();
    }
    return {
      'available': true,
      'path': path,
      'bytes': bytes,
      'sqlite': db.select('SELECT sqlite_version() AS v').first['v'],
      'schema': db.userVersion,
      'journal': db.select('PRAGMA journal_mode').first.values.first,
      'foreignKeys': db.select('PRAGMA foreign_keys').first.values.first == 1,
      'synchronous': db.select('PRAGMA synchronous').first.values.first,
      'lastBackup': meta['backup'],
      'integrity': meta['integrity'],
      'pending': db
          .select(
            "SELECT count(*) AS n FROM BAL_SYNC_EVENTO WHERE status!='confirmado'",
          )
          .first['n'],
    };
  }

  List<Map<String, Object?>> _backups() =>
      Directory(backupDirectory)
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (f) => RegExp(r'^balanca_.*\.db$').hasMatch(p.basename(f.path)),
          )
          .map(
            (f) => {
              'path': f.path,
              'bytes': f.lengthSync(),
              'at': f.lastModifiedSync().toUtc().toIso8601String(),
            },
          )
          .toList()
        ..sort((a, b) => (b['at'] as String).compareTo(a['at'] as String));

  Future<String> _backup({bool prune = true}) async {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final target = p.join(backupDirectory, 'balanca_$stamp.db');
    final destination = sqlite3.open(target);
    try {
      destination.execute('PRAGMA synchronous=FULL');
      await db.backup(destination).drain<void>();
      if (!_valid(_integrity(destination))) {
        throw StateError('Backup não passou na verificação de integridade.');
      }
    } catch (_) {
      destination.close();
      if (File(target).existsSync()) File(target).deleteSync();
      rethrow;
    }
    destination.close();
    _meta('backup', jsonEncode({'path': target, 'at': _now()}));
    if (prune) {
      for (final entry in _backups().skip(retention)) {
        File(entry['path'] as String).deleteSync();
      }
    }
    return target;
  }

  void _requireIdle() {
    if (db
        .select(
          "SELECT 1 FROM BAL_PESAGEM WHERE phase IN ('aberta','ticketPendente') LIMIT 1",
        )
        .isNotEmpty) {
      throw StateError(
        'Não é possível executar esta manutenção enquanto existe uma pesagem em andamento.',
      );
    }
  }

  Future<Object?> _executeScript(Map args) async {
    _requireIdle();
    final sql = args['content'] as String;
    final preview = SqlScriptPreview(args['filename'] as String, sql);
    final before = db.userVersion;
    try {
      if (!preview.allowed) throw StateError(preview.rejection!);
      if (db.select(
        "SELECT 1 FROM BAL_DB_SCRIPT_HIST WHERE hash=? AND status='SUCCESS' AND origin='MANUAL'",
        [preview.hash],
      ).isNotEmpty) {
        throw StateError(
          'Este conteúdo já foi aplicado. Reaplicação bloqueada.',
        );
      }
      final backup = await _backup();
      _transaction(() {
        for (final statement in preview.statements) {
          db.execute(statement);
        }
        if (!_valid(_integrity(db))) {
          throw StateError('Script causou inconsistência.');
        }
        _history(
          preview.filename,
          preview.hash,
          before,
          before,
          'SUCCESS',
          null,
          args['operator'] as String,
          'MANUAL',
        );
      });
      return backup;
    } catch (e) {
      _history(
        preview.filename,
        preview.hash,
        before,
        before,
        'FAILED',
        e.toString(),
        args['operator'] as String,
        'MANUAL',
      );
      rethrow;
    }
  }

  Future<Object?> _restore(String candidatePath, String operator) async {
    _requireIdle();
    // Apenas snapshots geridos pela aplicação; não recebe caminho SQL arbitrário.
    if (!_backups().any((b) => b['path'] == candidatePath) ||
        File(candidatePath).resolveSymbolicLinksSync() !=
            p.normalize(candidatePath)) {
      throw StateError('Selecione um backup local gerenciado pela aplicação.');
    }
    final candidate = sqlite3.open(candidatePath, mode: OpenMode.readOnly);
    String? safety;
    try {
      if (!_valid(_integrity(candidate)) ||
          candidate.userVersion < 1 ||
          candidate.userVersion > migrations.length ||
          candidate.select('PRAGMA application_id').first.values.first !=
              applicationId) {
        throw StateError('Backup incompatível ou inválido.');
      }
      for (final table in [
        'BAL_SCHEMA_VERSION',
        'BAL_DB_SCRIPT_HIST',
        'BAL_DB_META',
        'BAL_PESAGEM',
        'BAL_SYNC_EVENTO',
      ]) {
        if (candidate.select(
          "SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?",
          [table],
        ).isEmpty) {
          throw StateError('Backup sem estrutura obrigatória.');
        }
      }
      safety = await _backup(prune: false);
      File('$path.restore.json').writeAsStringSync(
        jsonEncode({
          'safety': safety,
          'hash': sha256.convert(File(safety).readAsBytesSync()).toString(),
        }),
        flush: true,
      );
      // A API de backup grava o destino atomicamente, incluindo tratamento de WAL.
      // Todas as operações da estação aguardam na mesma fila do worker.
      await candidate.backup(db).drain<void>();
      db.close();
      _db = null;
      _open();
      final result = _integrity(db);
      if (!_valid(result)) {
        throw StateError('Falha de integridade após restauração.');
      }
      _meta('integrity', jsonEncode({'at': _now(), 'result': result}));
      _meta('backup', jsonEncode({'path': safety, 'at': _now()}));
      _history(
        p.basename(candidatePath),
        sha256.convert(File(candidatePath).readAsBytesSync()).toString(),
        candidate.userVersion,
        db.userVersion,
        'SUCCESS',
        null,
        operator,
        'RESTORE',
      );
      File('$path.restore.json').deleteSync();
      return safety;
    } catch (e) {
      if (safety != null) {
        // Se a migração/validação posterior falhar, recupera o snapshot anterior.
        _db?.close();
        _db = sqlite3.open(path);
        final recovery = sqlite3.open(safety, mode: OpenMode.readOnly);
        try {
          await recovery.backup(db).drain<void>();
        } finally {
          recovery.close();
        }
        db.close();
        _db = null;
        _open();
        if (!_valid(_integrity(db))) {
          throw StateError(
            'Falha de recuperação. Preserve o backup $safety e contate o suporte.',
          );
        }
        _history(
          p.basename(candidatePath),
          '',
          db.userVersion,
          db.userVersion,
          'FAILED',
          e.toString(),
          operator,
          'RESTORE',
        );
        File('$path.restore.json').deleteSync();
      }
      rethrow;
    } finally {
      candidate.close();
    }
  }

  Future<void> _recoverInterruptedRestore() async {
    final marker =
        jsonDecode(File('$path.restore.json').readAsStringSync()) as Map;
    final safety = marker['safety'] as String;
    if (!_backups().any((b) => b['path'] == safety) ||
        sha256.convert(File(safety).readAsBytesSync()).toString() !=
            marker['hash']) {
      throw StateError(
        'Restauração interrompida: backup de recuperação inválido. Preserve os arquivos e contate o suporte.',
      );
    }
    final source = sqlite3.open(safety, mode: OpenMode.readOnly);
    final target = sqlite3.open(path);
    try {
      if (!_valid(_integrity(source))) {
        throw StateError('Backup de recuperação inconsistente.');
      }
      await source.backup(target).drain<void>();
    } finally {
      source.close();
      target.close();
    }
  }

  List<Map<String, Object?>> _load() => db
      .select('SELECT * FROM BAL_PESAGEM ORDER BY created_at,id')
      .map(
        (row) => <String, Object?>{
          ...row,
          'events': db
              .select(
                'SELECT * FROM BAL_SYNC_EVENTO WHERE weighing_id=? ORDER BY sequence',
                [row['id']],
              )
              .map((e) => Map<String, Object?>.from(e))
              .toList(),
        },
      )
      .toList();

  void _save(Map args) => _transaction(() {
    db.execute(
      'INSERT INTO BAL_PESAGEM(id,pre_ticket_id,plate,created_at,phase,first_reading,second_reading) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET pre_ticket_id=excluded.pre_ticket_id,plate=excluded.plate,created_at=excluded.created_at,phase=excluded.phase,first_reading=excluded.first_reading,second_reading=excluded.second_reading',
      [
        args['id'],
        args['pre_ticket_id'],
        args['plate'],
        args['created_at'],
        args['phase'],
        args['first_reading'],
        args['second_reading'],
      ],
    );
    db.execute('DELETE FROM BAL_SYNC_EVENTO WHERE weighing_id=?', [args['id']]);
    for (final event in args['events'] as List) {
      if (event['weighing_id'] != args['id']) {
        throw StateError('Evento de outra pesagem.');
      }
      db.execute(
        'INSERT INTO BAL_SYNC_EVENTO(id,weighing_id,type,payload,created_at,sequence,depends_on,status,attempts,last_error,remote_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          event['id'],
          event['weighing_id'],
          event['type'],
          event['payload'],
          event['created_at'],
          event['sequence'],
          event['depends_on'],
          event['status'],
          event['attempts'],
          event['last_error'],
          event['remote_id'],
        ],
      );
    }
  });
}
