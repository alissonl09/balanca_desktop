import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/visual_components.dart';
import 'cadastro_form.dart';
import 'cadastro_record.dart';
import 'cadastros_memory.dart';
import '../../core/permissions/permission_models.dart';

/// Pesquisa, seleção e ações comuns às quatro abas, sem acesso a persistência.
class CadastroPanel extends StatefulWidget {
  const CadastroPanel({
    super.key,
    required this.kind,
    required this.memory,
    this.permissions,
  });
  final CadastroKind kind;
  final CadastrosMemory memory;
  final PermissionState? permissions;

  @override
  State<CadastroPanel> createState() => _CadastroPanelState();
}

class _CadastroPanelState extends State<CadastroPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _filter = '';
  int? _selectedCode;
  bool _dialogOpen = false;
  CadastroKind get kind => widget.kind;
  bool _allowed(AppPermission permission) =>
      widget.permissions?.allows(permission) ?? true;

  List<CadastroRecord> get _results => widget.memory
      .records(kind)
      .where(
        (record) =>
            record.code.toString().contains(_filter) ||
            record.identification.toLowerCase().contains(_filter) ||
            (kind == CadastroKind.placas &&
                widget.memory
                    .carrierName(record.carrierCode)
                    .toLowerCase()
                    .contains(_filter)),
      )
      .toList();

  void _applySearch() => setState(() {
    _filter = _search.text.trim().toLowerCase();
    if (!_results.any((record) => record.code == _selectedCode)) {
      _selectedCode = null;
    }
  });

  Future<void> _edit([CadastroRecord? record]) async {
    final permission = record == null
        ? AppPermission.insertRegistry
        : AppPermission.editRegistry;
    if (!_allowed(permission)) return;
    if (_dialogOpen) return;
    setState(() => _dialogOpen = true);
    final result = await showCadastroForm(
      context,
      kind: kind,
      memory: widget.memory,
      record: record,
    );
    if (!mounted) return;
    setState(() {
      _dialogOpen = false;
      if (result != null && _allowed(permission)) {
        widget.memory.save(kind, result);
        _search.clear();
        _filter = '';
        _selectedCode = result.code;
      }
    });
    if (result != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final index = _results.indexWhere(
          (record) => record.code == result.code,
        );
        _scroll.jumpTo(
          (index * 48.0).clamp(0.0, _scroll.position.maxScrollExtent),
        );
      });
    }
  }

  Future<void> _delete(CadastroRecord record) async {
    if (!_allowed(AppPermission.deactivateRegistry)) return;
    if (_dialogOpen) return;
    setState(() => _dialogOpen = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('cadastro-delete-confirmation'),
        scrollable: true,
        title: const Text('Excluir registro'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Deseja realmente excluir este registro?'),
              const SizedBox(height: 12),
              SelectableText(
                '${record.code} - ${record.identification}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xffc62828),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _dialogOpen = false;
      if (confirmed == true && _allowed(AppPermission.deactivateRegistry)) {
        widget.memory.remove(kind, record.code);
        _selectedCode = null;
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _detail(CadastroRecord record) => switch (kind) {
    CadastroKind.remetentes => record.personType?.label ?? '',
    CadastroKind.transportadoras => [
      record.city,
      record.uf,
    ].where((text) => text.isNotEmpty).join(' / '),
    CadastroKind.motoristas =>
      record.driverLink == DriverLink.autonomo
          ? 'Autônomo'
          : widget.memory.carrierName(record.carrierCode),
    CadastroKind.placas => widget.memory.carrierName(record.carrierCode),
  };

  String get _detailLabel => switch (kind) {
    CadastroKind.remetentes => 'Tipo',
    CadastroKind.transportadoras => 'Cidade / UF',
    CadastroKind.motoristas => 'Vínculo / Transportadora',
    CadastroKind.placas => 'Transportadora',
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.memory,
      if (widget.permissions != null) widget.permissions!,
    ]),
    builder: (context, _) {
      final records = _results;
      final selected = records
          .where((record) => record.code == _selectedCode)
          .firstOrNull;
      return VisualCard(
        padding: const EdgeInsets.all(14),
        radius: 9,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  key: const ValueKey('cadastro-insert'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed:
                      _dialogOpen || !_allowed(AppPermission.insertRegistry)
                      ? null
                      : () => _edit(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Inserir'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('cadastro-edit'),
                  onPressed:
                      _dialogOpen ||
                          selected == null ||
                          !_allowed(AppPermission.editRegistry)
                      ? null
                      : () => _edit(selected),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Alterar'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('cadastro-delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xffc62828),
                  ),
                  onPressed:
                      _dialogOpen ||
                          selected == null ||
                          !_allowed(AppPermission.deactivateRegistry)
                      ? null
                      : () => _delete(selected),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Excluir'),
                ),
              ],
            );
            final title = Text(
              kind.title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: AppColors.heading,
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  )
                else ...[
                  title,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: actions),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: TextField(
                      key: const ValueKey('cadastro-search'),
                      controller: _search,
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) => _applySearch(),
                      decoration: InputDecoration(
                        hintText: kind == CadastroKind.placas
                            ? 'Pesquisar por código, placa ou transportadora'
                            : 'Pesquisar por código ou nome',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Pesquisar cadastro',
                          onPressed: _applySearch,
                          icon: const Icon(
                            Icons.search,
                            size: 20,
                            color: AppColors.green,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.paleGreen,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 66,
                        child: Text(
                          'Código',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          kind == CadastroKind.placas ? 'Placa' : 'Nome',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (constraints.maxWidth >= 600)
                        Expanded(
                          child: Text(
                            _detailLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  key: const ValueKey('cadastro-list-area'),
                  height: math.min(
                    260.0,
                    math.max(112.0, MediaQuery.sizeOf(context).height - 590),
                  ),
                  child: records.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhum registro encontrado.',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      : Scrollbar(
                          controller: _scroll,
                          child: ListView.builder(
                            key: const ValueKey('cadastro-list'),
                            controller: _scroll,
                            itemCount: records.length,
                            itemExtent: 48,
                            itemBuilder: (context, index) {
                              final record = records[index];
                              final isSelected = selected?.code == record.code;
                              final detail = _detail(record);
                              return Semantics(
                                selected: isSelected,
                                child: Material(
                                  color: isSelected
                                      ? AppColors.paleGreen
                                      : Colors.white,
                                  child: InkWell(
                                    key: ValueKey(
                                      'cadastro-row-${kind.name}-${record.code}',
                                    ),
                                    onTap: () => setState(
                                      () => _selectedCode = record.code,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          left: BorderSide(
                                            width: 3,
                                            color: isSelected
                                                ? AppColors.green
                                                : Colors.transparent,
                                          ),
                                          bottom: const BorderSide(
                                            color: AppColors.border,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 66,
                                            child: Text(
                                              '${record.code}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _cell(
                                                  record.identification,
                                                  bold: isSelected,
                                                ),
                                                if (constraints.maxWidth <
                                                        600 &&
                                                    detail.isNotEmpty)
                                                  _cell(detail, muted: true),
                                              ],
                                            ),
                                          ),
                                          if (constraints.maxWidth >= 600)
                                            Expanded(child: _cell(detail)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${records.length} registro(s) • Dados temporários, somente nesta sessão.',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            );
          },
        ),
      );
    },
  );

  Widget _cell(String value, {bool bold = false, bool muted = false}) =>
      Tooltip(
        message: value,
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: muted ? 12 : 14,
            color: muted ? AppColors.muted : AppColors.text,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      );
}
