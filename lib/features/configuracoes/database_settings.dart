import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../core/database/database_manager.dart';
import '../../core/database/ddl_policy.dart';
import '../../core/permissions/permission_models.dart';
import '../../core/theme/app_colors.dart';
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
  bool _statusFailed = false;
  bool _historyOpen = false;
  bool _historyFailed = false;
  String? _message, _details;
  SqlScriptPreview? _script;
  DatabaseManager? get database => widget.database;
  bool _allows(AppPermission permission) =>
      widget.permissions.allows(AppPermission.maintainDatabase) &&
      widget.permissions.allows(permission);

  void _requirePermission(AppPermission permission) {
    if (!_allows(permission)) {
      throw const DatabaseIssue('Sem permissão para esta operação.');
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<bool> _refreshStatus() async {
    try {
      final status = await database?.status();
      if (mounted) {
        setState(() {
          _status = status;
          _statusFailed = false;
        });
      }
      return status?['available'] == true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = null;
          _statusFailed = true;
        });
      }
      return false;
    }
  }

  Future<void> _refreshHistory() async {
    if (_status?['available'] != true ||
        !_allows(AppPermission.maintainDatabase)) {
      return;
    }
    try {
      final history = await database!.history();
      if (!mounted) return;
      setState(() {
        _history = history;
        _historyFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _historyFailed = true);
    }
  }

  Future<void> _run(
    AppPermission permission,
    Future<String> Function() work, {
    bool refreshStatus = true,
  }) async {
    if (_busy || !_allows(permission)) return;
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
          _details = e is DatabaseIssue ? e.details : null;
        });
      }
    } finally {
      if (refreshStatus) await _refreshStatus();
      if (mounted && _historyOpen) await _refreshHistory();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() => _run(
    AppPermission.maintainDatabase,
    () async => await _refreshStatus()
        ? 'Conexão com o banco local verificada.'
        : 'Banco local indisponível para consulta.',
    refreshStatus: false,
  );

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
    _requirePermission(AppPermission.executeDatabaseDdl);
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
    _requirePermission(AppPermission.restoreDatabase);
    if (!await _confirm(
      'Restaurar backup',
      '${p.basename(chosen['path'] as String)}\n${_date(chosen['at'])} · ${_size(chosen['bytes'])}\n\n'
          'Os dados posteriores ao backup serão substituídos, inclusive eventos pendentes. '
          'Um backup de segurança do banco atual será criado antes da restauração.',
      'RESTAURAR',
    )) {
      return 'Restauração cancelada.';
    }
    if (!mounted) return 'Restauração cancelada.';
    _requirePermission(AppPermission.restoreDatabase);
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
  DateTime? _lastBackup() {
    final value = _status?['lastBackup'];
    if (value is! String) return null;
    try {
      final metadata = jsonDecode(value);
      return metadata is Map ? DateTime.tryParse('${metadata['at']}') : null;
    } on FormatException {
      return null;
    }
  }

  Widget _caption(String text) =>
      Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted));

  Widget _action(
    String key,
    String label,
    String help,
    AppPermission permission,
    Future<String> Function() work,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton(
        key: ValueKey('db-$key'),
        onPressed:
            !_busy && _status?['available'] == true && _allows(permission)
            ? () => _run(permission, work)
            : null,
        child: Text(label),
      ),
      const SizedBox(height: 4),
      _caption(help),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.permissions,
    builder: (context, _) {
      final available = _status?['available'] == true;
      final checking = _status == null && !_statusFailed && database != null;
      final lastBackup = _lastBackup();
      final error = database?.lastError;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSection(
            title: 'Banco de dados local',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Local do banco de dados',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  '${_status?['path'] ?? database?.path ?? 'Não inicializado neste ambiente'}',
                  key: const ValueKey('db-path'),
                ),
                const SizedBox(height: 4),
                _caption(
                  'Arquivo usado para guardar as pesagens e as pendências da estação.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          checking
                              ? Icons.schedule_outlined
                              : available
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 20,
                          color: checking
                              ? AppColors.muted
                              : available
                              ? AppColors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          checking
                              ? 'Consultando banco…'
                              : available
                              ? 'Disponível'
                              : 'Indisponível',
                          key: const ValueKey('db-status'),
                        ),
                      ],
                    ),
                    OutlinedButton(
                      key: const ValueKey('db-test-connection'),
                      onPressed:
                          !_busy &&
                              !checking &&
                              database != null &&
                              _allows(AppPermission.maintainDatabase)
                          ? _testConnection
                          : null,
                      child: const Text('Testar conexão'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _caption(
                  'Consulta a conexão que a estação usa para acessar o banco.',
                ),
                if (!available && error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error.message),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(),
                  ),
                if (_message case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(message, key: const ValueKey('db-message')),
                    ),
                  ),
                if (_details?.isNotEmpty == true)
                  ExpansionTile(
                    title: const Text('Detalhes da operação'),
                    tilePadding: EdgeInsets.zero,
                    children: [SelectableText(_details!)],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SettingsSection(
            title: 'Backup e restauração',
            child: SettingsFields(
              children: [
                _action(
                  'backup',
                  'Criar backup agora',
                  lastBackup == null
                      ? 'Cria uma cópia verificada dos dados locais.'
                      : 'Cria uma cópia verificada dos dados locais. Última cópia em ${_date(lastBackup)}.',
                  AppPermission.maintainDatabase,
                  () async {
                    await database!.backup();
                    return 'Backup criado e integridade verificada.';
                  },
                ),
                _action(
                  'restore',
                  'Restaurar backup',
                  'Recupera os dados locais de uma cópia de segurança.',
                  AppPermission.restoreDatabase,
                  _restore,
                ),
              ],
            ),
          ),
          Material(type: MaterialType.transparency, child: _advanced()),
        ],
      );
    },
  );

  Widget _advanced() => ExpansionTile(
    key: const ValueKey('db-advanced'),
    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    title: const Text('Manutenção avançada'),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    onExpansionChanged: (expanded) {
      if (!expanded) _historyOpen = false;
    },
    children: [
      if (_status?['schema'] case final version?)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _caption(
            'Schema v$version · Tamanho em disco ${_size(_status?['bytes'])}',
          ),
        ),
      SettingsFields(
        children: [
          _action(
            'integrity',
            'Verificar integridade',
            'Verifica a estrutura do banco e as referências entre registros.',
            AppPermission.maintainDatabase,
            () async {
              final result = await database!.checkIntegrity();
              final ok = result.length == 1 && result.first == 'ok';
              if (!ok && mounted) setState(() => _details = result.join('\n'));
              return ok
                  ? 'Banco íntegro.'
                  : 'A verificação encontrou problemas. Consulte os detalhes da operação.';
            },
          ),
          _action(
            'optimize',
            'Otimizar banco',
            'Atualiza as estatísticas usadas nas consultas.',
            AppPermission.maintainDatabase,
            () async {
              await database!.optimize();
              return 'Banco otimizado.';
            },
          ),
          _action(
            'vacuum',
            'Reorganizar / compactar',
            'Recupera espaço em disco quando a estação está ociosa.',
            AppPermission.maintainDatabase,
            () async {
              if (!await _confirm(
                    'Reorganizar banco',
                    'A compactação pode demorar e requer espaço livre. '
                        'Esta operação não pode ocorrer durante uma pesagem ativa.',
                    'COMPACTAR',
                  ) ||
                  !mounted) {
                return 'Compactação cancelada.';
              }
              _requirePermission(AppPermission.maintainDatabase);
              await database!.vacuum();
              return 'Banco reorganizado.';
            },
          ),
          _action(
            'select-sql',
            'Selecionar script .sql',
            'Exibe os comandos para revisão antes de qualquer aplicação.',
            AppPermission.executeDatabaseDdl,
            _selectSql,
          ),
        ],
      ),
      if (_script case final script?) ...[
        const SizedBox(height: 12),
        Text('Arquivo: ${script.filename}'),
        if (script.rejection != null)
          Text(
            'Operação bloqueada: ${script.rejection}',
            style: const TextStyle(color: Colors.red),
          ),
        Text('${script.statements.length} comandos · SHA-256: ${script.hash}'),
        for (final command in script.statements)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('✓ $command'),
          ),
        ExpansionTile(
          title: const Text('Conteúdo do arquivo'),
          tilePadding: EdgeInsets.zero,
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
          _action(
            'apply-sql',
            'Aplicar script',
            'Cria um backup antes de executar os comandos revisados.',
            AppPermission.executeDatabaseDdl,
            () async {
              if (!await _confirm(
                    'Executar script SQL',
                    '${script.filename}\n${script.statements.length} comandos. '
                        'Um backup íntegro será criado antes da execução. Todas as alterações serão transacionais.',
                    'APLICAR',
                  ) ||
                  !mounted) {
                return 'Execução cancelada.';
              }
              _requirePermission(AppPermission.executeDatabaseDdl);
              await database!.executeScript(
                script,
                operator: widget.permissions.currentUserId,
              );
              return 'Script aplicado. Backup de segurança disponível.';
            },
          ),
      ],
      ExpansionTile(
        key: const ValueKey('db-history'),
        title: const Text('Histórico de manutenção'),
        tilePadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        onExpansionChanged: (expanded) {
          _historyOpen = expanded;
          if (expanded) _refreshHistory();
        },
        children: [
          if (_status?['available'] != true)
            const Text('Histórico indisponível.')
          else if (_historyFailed)
            const Text('Não foi possível consultar o histórico.')
          else if (_history.isEmpty)
            const Text('Nenhuma execução registrada.'),
          if (_status?['available'] == true && !_historyFailed)
            for (final entry in _history) _historyEntry(entry),
        ],
      ),
    ],
  );

  Widget _historyEntry(Map<String, Object?> entry) {
    final initialSetup =
        entry['origin'] == 'MIGRATION' &&
        entry['version_before'] == 0 &&
        entry['status'] == 'SUCCESS';
    final operation = switch (entry['origin']) {
      'MIGRATION' when initialSetup => 'Configuração inicial do banco',
      'MIGRATION' => 'Atualização da estrutura do banco',
      'MANUAL' => 'Execução de script SQL',
      'RESTORE' => 'Restauração de backup',
      _ => 'Manutenção do banco',
    };
    final (result, icon, color) = switch (entry['status']) {
      'SUCCESS' => ('Concluída', Icons.check_circle_outline, AppColors.green),
      'FAILED' => (
        'Falhou',
        Icons.error_outline,
        Theme.of(context).colorScheme.error,
      ),
      _ => ('Resultado desconhecido', Icons.help_outline, AppColors.muted),
    };
    final operatorId = entry['operator'];
    final operator = switch (operatorId) {
      'APPLICATION' => 'Aplicativo',
      String id when id.isNotEmpty =>
        widget.permissions.users
                .where((user) => user.id == id)
                .map((user) => '${user.name} ($id)')
                .firstOrNull ??
            id,
      _ => 'Não informado',
    };
    final version = switch ((entry['version_before'], entry['version_after'])) {
      (0, int after) when initialSetup =>
        'Estrutura do banco criada na versão $after.',
      (int before, int after)
          when entry['origin'] == 'RESTORE' && entry['status'] == 'SUCCESS' =>
        'Versão do backup: $before. Versão após a restauração: $after.',
      (int before, int after) when before != after =>
        'Estrutura do banco mudou da versão $before para a versão $after.',
      (int _, int after) => 'Estrutura do banco na versão $after.',
      _ => null,
    };

    return ExpansionTile(
      key: entry['id'] == null ? null : ValueKey(entry['id']),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text(
        operation,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(result),
            ],
          ),
          _caption('Data e hora: ${_date(entry['executed_at'])}'),
        ],
      ),
      children: [
        if (entry['filename'] case String name when name.isNotEmpty)
          SelectableText('Arquivo: $name'),
        Text('Executado por: $operator'),
        if (version != null) Text(version),
      ],
    );
  }
}
