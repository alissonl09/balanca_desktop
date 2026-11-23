import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../core/database/database_manager.dart';
import '../../core/database/ddl_policy.dart';
import '../../core/permissions/permission_models.dart';
import 'settings_widgets.dart';

class DatabaseSettings extends StatefulWidget {
  const DatabaseSettings({
    super.key,
    required this.database,
    required this.permissions,
    this.selectSqlFile,
  });
  final DatabaseManager? database;
  final PermissionState permissions;
  final Future<XFile?> Function()? selectSqlFile;
  @override
  State<DatabaseSettings> createState() => _DatabaseSettingsState();
}

class _DatabaseSettingsState extends State<DatabaseSettings> {
  Map<String, Object?>? _status;
  List<Map<String, Object?>> _history = [];
  bool _busy = false;
  String? _message, _details;
  SqlScriptPreview? _script;
  DatabaseManager? get database => widget.database;
  bool allows(AppPermission p) => widget.permissions.allows(p);
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await database?.status();
      final history = database?.available == true
          ? await database!.history()
          : <Map<String, Object?>>[];
      if (mounted) {
        setState(() {
          _status = status;
          _history = history;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Não foi possível consultar o banco local.';
          _details = e is DatabaseIssue ? e.details : e.toString();
        });
      }
    }
  }

  Future<void> _run(
    AppPermission permission,
    Future<String> Function() work,
  ) async {
    if (_busy || !allows(permission)) return;
    setState(() {
      _busy = true;
      _message = null;
      _details = null;
    });
    try {
      final message = await work();
      if (mounted) setState(() => _message = message);
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = e is DatabaseIssue
              ? e.message
              : 'Não foi possível concluir a manutenção.';
          _details = e is DatabaseIssue ? e.details : e.toString();
        });
      }
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String explanation, String phrase) async {
    var value = '';
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(explanation),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('db-confirm-phrase'),
                      decoration: InputDecoration(
                        labelText: 'Digite $phrase para confirmar',
                      ),
                      onChanged: (text) => update(() => value = text),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  key: const ValueKey('db-confirm'),
                  onPressed: value == phrase
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('Confirmar'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<String> _selectSql() async {
    final file =
        await (widget.selectSqlFile?.call() ??
            openFile(
              acceptedTypeGroups: [
                const XTypeGroup(label: 'Scripts SQL', extensions: ['sql']),
              ],
            ));
    if (file == null) return 'Seleção cancelada.';
    if (mounted) setState(() => _script = null);
    if (p.extension(file.name).toLowerCase() != '.sql' ||
        await file.length() > 1024 * 1024) {
      throw const DatabaseIssue('Selecione um arquivo .sql de até 1 MB.');
    }
    final script = SqlScriptPreview(file.name, await file.readAsString());
    if (mounted) setState(() => _script = script);
    return script.allowed
        ? 'Preview disponível. Revise os comandos antes de aplicar.'
        : 'Script bloqueado: ${script.rejection}';
  }

  Future<String> _restore() async {
    final entries = await database!.backups();
    if (!mounted) return '';
    if (entries.isEmpty) return 'Nenhum backup local disponível.';
    final chosen = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selecionar backup'),
        content: SizedBox(
          width: 560,
          height: 300,
          child: ListView(
            children: [
              for (final entry in entries)
                ListTile(
                  title: Text(p.basename(entry['path'] as String)),
                  subtitle: Text(
                    '${_date(entry['at'])} · ${_size(entry['bytes'])}',
                  ),
                  onTap: () => Navigator.pop(context, entry),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return 'Restauração cancelada.';
    if (!await _confirm(
      'Restaurar backup',
      '${p.basename(chosen['path'] as String)}\n${_date(chosen['at'])} · ${_size(chosen['bytes'])}\n\n'
          'Os dados posteriores ao backup serão substituídos, inclusive eventos pendentes. '
          'Um backup de segurança do banco atual será criado antes da restauração.',
      'RESTAURAR',
    )) {
      return 'Restauração cancelada.';
    }
    if (!allows(AppPermission.restoreDatabase)) {
      throw const DatabaseIssue('Permissão de restauração indisponível.');
    }
    await database!.restore(
      chosen['path'] as String,
      operator: widget.permissions.currentUserId,
    );
    return 'Backup restaurado e integridade verificada. Os dados locais foram recarregados.';
  }

  String _date(Object? value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return 'Não registrado';
    String two(int v) => '$v'.padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  String _size(Object? value) =>
      value is num ? '${(value / (1024 * 1024)).toStringAsFixed(2)} MB' : '—';
  Map<String, dynamic>? _meta(Object? value) =>
      value is String ? jsonDecode(value) as Map<String, dynamic> : null;

  @override
  Widget build(BuildContext context) {
    final available = _status?['available'] == true;
    final backup = _meta(_status?['lastBackup']);
    final integrity = _meta(_status?['integrity']);
    Widget action(
      String key,
      String label,
      AppPermission permission,
      Future<String> Function() work,
    ) => OutlinedButton(
      key: ValueKey('db-$key'),
      onPressed: !_busy && available && allows(permission)
          ? () => _run(permission, work)
          : null,
      child: Text(label),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Banco de Dados Local',
          description: 'SQLite embarcado · Manutenção da estação',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    available
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: available ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      available ? 'SQLite operacional' : 'Banco indisponível',
                      key: const ValueKey('db-status'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                'Caminho: ${_status?['path'] ?? database?.path ?? 'Não inicializado neste ambiente'}',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  Text('Schema: v${_status?['schema'] ?? '—'}'),
                  Text('Tamanho (inclui WAL): ${_size(_status?['bytes'])}'),
                  Text('SQLite: ${_status?['sqlite'] ?? '—'}'),
                  Text('Journal: ${_status?['journal'] ?? '—'}'),
                  Text(
                    'Foreign keys: ${_status?['foreignKeys'] == true ? 'habilitadas' : '—'}',
                  ),
                  Text(
                    'Synchronous: ${_status?['synchronous'] == 2 ? 'FULL' : '—'}',
                  ),
                  Text('Eventos pendentes: ${_status?['pending'] ?? '—'}'),
                ],
              ),
              const SizedBox(height: 12),
              Text('Último backup: ${_date(backup?['at'])}'),
              Text('Última verificação: ${_date(integrity?['at'])}'),
              Text(
                'Integridade: ${integrity == null ? 'não verificada' : (integrity['result'] as List).join(', ')}',
              ),
              if (!available && database != null)
                TextButton(
                  key: const ValueKey('db-reopen'),
                  onPressed: _busy
                      ? null
                      : () => _run(AppPermission.maintainDatabase, () async {
                          await database!.open();
                          return 'Banco aberto.';
                        }),
                  child: const Text('Tentar abrir banco'),
                ),
              if (database?.lastError != null)
                Text(database!.lastError!.message),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Manutenção',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  action(
                    'integrity',
                    'Verificar integridade',
                    AppPermission.maintainDatabase,
                    () async {
                      final result = await database!.checkIntegrity();
                      final ok = result.length == 1 && result.first == 'ok';
                      if (!ok && mounted) {
                        setState(() => _details = result.join('\n'));
                      }
                      return ok
                          ? 'Banco íntegro.'
                          : 'A verificação encontrou problemas. Consulte os detalhes técnicos.';
                    },
                  ),
                  action(
                    'backup',
                    'Criar backup agora',
                    AppPermission.maintainDatabase,
                    () async {
                      await database!.backup();
                      return 'Backup criado e integridade verificada.';
                    },
                  ),
                  action(
                    'restore',
                    'Restaurar backup',
                    AppPermission.restoreDatabase,
                    _restore,
                  ),
                  action(
                    'optimize',
                    'Otimizar banco',
                    AppPermission.maintainDatabase,
                    () async {
                      await database!.optimize();
                      return 'Banco otimizado.';
                    },
                  ),
                  action(
                    'vacuum',
                    'Reorganizar / compactar',
                    AppPermission.maintainDatabase,
                    () async {
                      if (!await _confirm(
                        'Reorganizar banco',
                        'A compactação pode demorar e requer espaço livre. '
                            'Esta operação não pode ocorrer durante uma pesagem ativa.',
                        'COMPACTAR',
                      )) {
                        return 'Compactação cancelada.';
                      }
                      await database!.vacuum();
                      return 'Banco reorganizado.';
                    },
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_message!, key: const ValueKey('db-message')),
                ),
              if (_details?.isNotEmpty == true)
                ExpansionTile(
                  title: const Text('Detalhes técnicos'),
                  children: [SelectableText(_details!)],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Ferramentas avançadas',
          description: 'Migrations da aplicação são a forma oficial de evolução do schema.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              action(
                'select-sql',
                'Selecionar script .sql',
                AppPermission.executeDatabaseDdl,
                _selectSql,
              ),
              if (_script case final script?) ...[
                const SizedBox(height: 12),
                Text('Arquivo: ${script.filename}'),
                if (script.rejection != null)
                  Text(
                    'Operação bloqueada: ${script.rejection}',
                    style: const TextStyle(color: Colors.red),
                  ),
                Text(
                  '${script.statements.length} comandos · SHA-256: ${script.hash}',
                ),
                for (final command in script.statements)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('✓ $command'),
                  ),
                ExpansionTile(
                  title: const Text('Conteúdo do arquivo'),
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: SingleChildScrollView(
                        child: SelectableText(script.content),
                      ),
                    ),
                  ],
                ),
                if (script.allowed)
                  action(
                    'apply-sql',
                    'Aplicar script',
                    AppPermission.executeDatabaseDdl,
                    () async {
                      if (!await _confirm(
                        'Executar script SQL',
                        '${script.filename}\n${script.statements.length} comandos. '
                            'Um backup íntegro será criado antes da execução. Todas as alterações serão transacionais.',
                        'APLICAR',
                      )) {
                        return 'Execução cancelada.';
                      }
                      if (!allows(AppPermission.executeDatabaseDdl)) {
                        throw const DatabaseIssue(
                          'Permissão de DDL indisponível.',
                        );
                      }
                      await database!.executeScript(
                        script,
                        operator: widget.permissions.currentUserId,
                      );
                      return 'Script aplicado. Backup de segurança disponível.';
                    },
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Histórico de manutenção',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_history.isEmpty) const Text('Nenhuma execução registrada.'),
              for (final entry in _history)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${entry['filename']} · ${entry['status']}'),
                  subtitle: Text(
                    '${_date(entry['executed_at'])} · ${entry['origin']} · ${entry['operator']} · v${entry['version_before']} → v${entry['version_after']}',
                  ),
                  trailing: entry['status'] == 'SUCCESS'
                      ? const Icon(
                          Icons.check_circle_outline,
                          color: Colors.green,
                        )
                      : const Icon(Icons.error_outline),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
