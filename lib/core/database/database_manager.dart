import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_windows/path_provider_windows.dart';

import 'database_migrations.dart';
import 'database_worker.dart';
import 'ddl_policy.dart';

class DatabaseIssue implements Exception {
  const DatabaseIssue(this.message, [this.details = '']);
  final String message, details;
  @override
  String toString() => message;
}

/// API assíncrona da única conexão, que vive num isolate e serializa todo acesso.
class DatabaseManager {
  DatabaseManager({
    required this.path,
    this.backupRetention = 10,
    this.migrations = databaseMigrations,
  });
  final String path;
  final int backupRetention;
  final List<DatabaseMigration> migrations;
  SendPort? _port;
  Isolate? _isolate;
  bool available = false;
  bool maintenanceInProgress = false;
  bool Function()? isOperationActive;
  Future<void> Function()? onRestored;
  DatabaseIssue? lastError;
  Future<void>? _opening;

  static Future<DatabaseManager> forWindows() async {
    final local = await _localDataPath();
    if (local == null) {
      throw const DatabaseIssue('Diretório local do Windows indisponível.');
    }
    return DatabaseManager(
      path: p.join(local, 'Cooxupe', 'Balanca', 'data', 'balanca.db'),
    );
  }

  static Future<String?> _localDataPath() async =>
      PathProviderWindows().getPath(
        // FOLDERID_LocalAppData (Known Folder do Windows, não um caminho fixo).
        '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}',
      );

  Future<void> open() =>
      _opening ??= _openOnce().whenComplete(() => _opening = null);

  Future<void> _openOnce() async {
    if (available) return;
    if (backupRetention < 1) throw ArgumentError('Retenção deve ser positiva.');
    try {
      await Directory(p.dirname(path)).create(recursive: true);
      final real = await Directory(p.dirname(path)).resolveSymbolicLinks();
      if (real.startsWith(r'\\') || !p.isAbsolute(path)) {
        throw const DatabaseIssue(
          'O banco deve ficar em disco local, fora de compartilhamentos.',
        );
      }
      if (Platform.isWindows) {
        final drive = p.windows.rootPrefix(real).toNativeUtf16();
        try {
          final driveType = DynamicLibrary.open('kernel32.dll')
              .lookupFunction<
                Uint32 Function(Pointer<Utf16>),
                int Function(Pointer<Utf16>)
              >('GetDriveTypeW')(drive);
          if (driveType != 3) {
            throw const DatabaseIssue(
              'Use uma unidade local fixa para o banco da estação.',
            );
          }
        } finally {
          calloc.free(drive);
        }
      }
      if (_port == null) {
        final ready = ReceivePort();
        _isolate = await Isolate.spawn(databaseWorker, ready.sendPort);
        _port = await ready.first as SendPort;
        ready.close();
      }
      await _request('open', {
        'path': p.normalize(path),
        'retention': backupRetention,
        'migrations': migrations,
      });
      available = true;
      lastError = null;
    } catch (e) {
      lastError = e is DatabaseIssue
          ? e
          : DatabaseIssue(
              'Não foi possível abrir o banco local.',
              e.toString(),
            );
      rethrow;
    }
  }

  Future<dynamic> _request(
    String action, [
    Map<String, Object?> args = const {},
  ]) async {
    if (_port == null) throw const DatabaseIssue('Banco local indisponível.');
    final reply = ReceivePort();
    _port!.send([reply.sendPort, action, args]);
    try {
      final result = await reply.first as Map;
      if (result.containsKey('error')) {
        throw DatabaseIssue(switch (action) {
          'ddl' => 'Script não aplicado. Nenhuma alteração foi confirmada.',
          'restore' => 'Não foi possível restaurar o backup. Consulte os detalhes técnicos.',
          _ => 'Não foi possível concluir a operação no banco local.',
        }, result['error'] as String);
      }
      return result['value'];
    } finally {
      reply.close();
    }
  }

  Future<Map<String, Object?>> status() async => available
      ? Map<String, Object?>.from(await _request('status') as Map)
      : {'available': false, 'path': path};
  Future<List<String>> checkIntegrity() async =>
      (await _request('integrity') as List).cast<String>();
  Future<String> backup() async => await _request('backup') as String;
  Future<List<Map<String, Object?>>> backups() async =>
      (await _request('backups') as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
  Future<List<Map<String, Object?>>> history() async =>
      (await _request('history') as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
  Future<void> optimize() async {
    await _request('optimize');
  }

  Future<T> _maintenance<T>(Future<T> Function() work) async {
    if (maintenanceInProgress || (isOperationActive?.call() ?? false)) {
      throw const DatabaseIssue(
        'Não é possível executar esta manutenção enquanto existe uma pesagem ou manutenção em andamento.',
      );
    }
    maintenanceInProgress = true;
    try {
      return await work();
    } finally {
      maintenanceInProgress = false;
    }
  }

  Future<void> vacuum() => _maintenance(() async {
    await _request('vacuum');
  });
  Future<void> executeScript(
    SqlScriptPreview preview, {
    required String operator,
  }) => _maintenance(() async {
    if (!preview.allowed) {
      throw DatabaseIssue('Script bloqueado.', preview.rejection!);
    }
    await _request('ddl', {
      'filename': p.basename(preview.filename),
      'content': preview.content,
      'operator': operator,
    });
  });
  Future<void> restore(String backupPath, {required String operator}) =>
      _maintenance(() async {
        try {
          await _request('restore', {'path': backupPath, 'operator': operator});
        } catch (_) {
          try {
            await _request('status');
          } catch (_) {
            available = false;
          }
          rethrow;
        }
        try {
          await onRestored?.call();
        } catch (e) {
          throw DatabaseIssue(
            'Backup restaurado. Reinicie a aplicação para recarregar a sessão.',
            e.toString(),
          );
        }
      });

  Future<List<Map<String, Object?>>> loadWeighings() async =>
      (await _request('load') as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
  Future<void> saveWeighing(Map<String, Object?> data) async {
    if (maintenanceInProgress) {
      throw const DatabaseIssue(
        'Aguarde a manutenção antes de registrar dados operacionais.',
      );
    }
    await _request('save', data);
  }

  Future<void> close() async {
    if (_port != null) await _request('close');
    _port = null;
    available = false;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
  }
}
