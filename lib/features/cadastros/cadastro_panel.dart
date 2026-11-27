import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/visual_components.dart';
import 'cadastro_form.dart';
import 'cadastro_record.dart';
import 'cadastros_memory.dart';
import 'catalog_details.dart';
import 'catalog_form.dart';

/// Pesquisa, seleção e ações comuns às quatro abas, sem acesso a persistência.
class CadastroPanel extends StatefulWidget {
  const CadastroPanel({super.key, required this.kind, required this.memory});
  final CadastroKind kind;
  final CadastrosMemory memory;

  @override
  State<CadastroPanel> createState() => _CadastroPanelState();
}

class _CadastroPanelState extends State<CadastroPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _filter = '';
  String? _selectedId;
  bool _dialogOpen = false;
  CadastroKind get kind => widget.kind;
  bool get _isDriver => kind == CadastroKind.motoristas;
  CadastrosMemory get memory => widget.memory;

  List<CadastroRecord> get _results => widget.memory
      .records(kind)
      .where(
        (record) =>
            record
                .displayCode(kind, simulated: memory.simulated)
                .toLowerCase()
                .contains(_filter) ||
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
    if (!_results.any((record) => record.id == _selectedId)) {
      _selectedId = null;
    }
  });

  Future<void> _openForm({
    CadastroRecord? record,
    bool readOnly = false,
  }) async {
    final action = readOnly
        ? CadastroAction.read
        : record == null
        ? CadastroAction.insert
        : CadastroAction.edit;
    if (_dialogOpen || memory.unavailable(kind, action) != null) return;
    if (record != null && !memory.records(kind).contains(record)) return;
    setState(() {
      _dialogOpen = true;
      if (record != null) _selectedId = record.id;
    });
    final form = kind.isCatalog ? showCatalogForm : showCadastroForm;
    final result = await form(
      context,
      kind: kind,
      memory: memory,
      record: record,
      readOnly: readOnly,
    );
    if (!mounted) return;
    setState(() {
      _dialogOpen = false;
      if (result != null) {
        _search.clear();
        _filter = '';
        _selectedId = result.id;
      }
    });
    if (result != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final index = _results.indexWhere((record) => record.id == result.id);
        _scroll.jumpTo(
          (index * 48.0).clamp(0.0, _scroll.position.maxScrollExtent),
        );
      });
    }
  }

  Future<void> _delete(CadastroRecord record) async {
    if (_dialogOpen ||
        memory.unavailable(kind, CadastroAction.deactivate) != null ||
        !memory.records(kind).contains(record)) {
      return;
    }
    setState(() => _dialogOpen = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('cadastro-delete-confirmation'),
        scrollable: true,
        title: Text(kind.isCatalog ? 'Inativar registro' : 'Excluir registro'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kind.isCatalog
                    ? 'Deseja inativar este registro na demonstração?'
                    : 'Deseja realmente excluir este registro?',
              ),
              const SizedBox(height: 12),
              SelectableText(
                '${record.displayCode(kind, simulated: memory.simulated)} - ${record.identification}',
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
            child: Text(kind.isCatalog ? 'Inativar' : 'Excluir'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (confirmed == true) {
      try {
        memory.remove(kind, record);
        setState(() => _selectedId = null);
      } on CadastroException catch (error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
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
    CadastroKind.motoristas => record.city,
    CadastroKind.placas => widget.memory.carrierName(record.carrierCode),
    _ => '',
  };

  String get _detailLabel => switch (kind) {
    CadastroKind.remetentes => 'Tipo',
    CadastroKind.transportadoras => 'Cidade / UF',
    CadastroKind.motoristas => 'Cidade',
    CadastroKind.placas => 'Transportadora',
    _ => '',
  };

  List<String> get _catalogHeaders => switch (kind) {
    CadastroKind.operacoes => ['Natureza', 'Situação'],
    CadastroKind.tolerancias => [
      'Calcula tolerância',
      'Tipo',
      'Quebra',
      'Renda',
      'Situação',
    ],
    CadastroKind.complementos => ['Tipo', 'Situação'],
    _ => ['Situação'],
  };

  List<String> _catalogColumns(CadastroRecord record) {
    final details = record.catalog;
    String value(double? number, ToleranceUnit? unit) => number == null
        ? '—'
        : '${number.toString().replaceAll('.', ',')} ${unit?.symbol ?? ''}'
              .trim();
    return [
      if (kind == CadastroKind.operacoes)
        details is OperationDetails ? details.nature.label : '—',
      if (kind == CadastroKind.tolerancias) ...[
        details is ToleranceDetails
            ? (details.calculates ? 'Sim' : 'Não')
            : '—',
        details is ToleranceDetails && details.calculates
            ? details.unit?.label ?? '—'
            : '—',
        details is ToleranceDetails && details.calculates
            ? value(details.loss, details.unit)
            : '—',
        details is ToleranceDetails && details.calculates
            ? value(details.yield, details.unit)
            : '—',
      ],
      if (kind == CadastroKind.complementos)
        details is AttributeDetails ? details.type.label : '—',
      record.active ? 'Ativo' : 'Inativo',
    ];
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([memory, memory.permissions]),
    builder: (context, _) {
      final records = _results;
      final selected = records
          .where((record) => record.id == _selectedId)
          .firstOrNull;
      final readReason = memory.unavailable(kind, CadastroAction.read);
      final insertReason = memory.unavailable(kind, CadastroAction.insert);
      final editReason = memory.unavailable(kind, CadastroAction.edit);
      final deleteReason = memory.unavailable(kind, CadastroAction.deactivate);
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
                if (kind.isCatalog)
                  OutlinedButton.icon(
                    key: const ValueKey('cadastro-consult'),
                    onPressed:
                        _dialogOpen || selected == null || readReason != null
                        ? null
                        : () => _openForm(record: selected, readOnly: true),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Consultar'),
                  ),
                _withReason(
                  insertReason,
                  ElevatedButton.icon(
                    key: const ValueKey('cadastro-insert'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _dialogOpen || insertReason != null
                        ? null
                        : () => _openForm(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Inserir'),
                  ),
                ),
                _withReason(
                  editReason,
                  OutlinedButton.icon(
                    key: const ValueKey('cadastro-edit'),
                    onPressed:
                        _dialogOpen || selected == null || editReason != null
                        ? null
                        : () => _openForm(record: selected),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Alterar'),
                  ),
                ),
                _withReason(
                  deleteReason,
                  OutlinedButton.icon(
                    key: const ValueKey('cadastro-delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xffc62828),
                    ),
                    onPressed:
                        _dialogOpen ||
                            selected == null ||
                            deleteReason != null ||
                            (kind.isCatalog && !selected.active)
                        ? null
                        : () => _delete(selected),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(kind.isCatalog ? 'Inativar' : 'Excluir'),
                  ),
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
                      enabled: readReason == null,
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) => _applySearch(),
                      decoration: InputDecoration(
                        hintText: switch (kind) {
                          CadastroKind.placas =>
                            'Pesquisar por código, placa ou transportadora',
                          CadastroKind.motoristas =>
                            'Pesquisar por matrícula ou nome',
                          _ when kind.isCatalog =>
                            'Pesquisar por código ou descrição',
                          _ => 'Pesquisar por código ou nome',
                        },
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
                          onPressed: readReason == null ? _applySearch : null,
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
                      SizedBox(
                        width: _isDriver ? 100 : 66,
                        child: Text(
                          _isDriver ? 'Matrícula' : 'Código',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: kind.isCatalog ? 2 : 1,
                        child: Text(
                          kind.isCatalog
                              ? 'Descrição'
                              : kind == CadastroKind.placas
                              ? 'Placa'
                              : 'Nome',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (kind.isCatalog)
                        for (final label in _catalogHeaders)
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                      else if (_isDriver || constraints.maxWidth >= 600)
                        Expanded(
                          child: Text(
                            _detailLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (_isDriver)
                        const SizedBox(
                          width: 44,
                          child: Text(
                            'UF',
                            style: TextStyle(
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
                      ? Center(
                          child: Text(
                            readReason ??
                                (!memory.simulated &&
                                        memory.records(kind).isEmpty
                                    ? 'Nenhum dado oficial disponível.'
                                    : 'Nenhum registro encontrado.'),
                            style: const TextStyle(color: AppColors.muted),
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
                              final isSelected = selected?.id == record.id;
                              final detail = _detail(record);
                              return Semantics(
                                selected: isSelected,
                                child: Material(
                                  color: isSelected
                                      ? AppColors.paleGreen
                                      : Colors.white,
                                  child: InkWell(
                                    key: ValueKey(
                                      'cadastro-row-${kind.name}-${record.id}',
                                    ),
                                    onTap: () =>
                                        setState(() => _selectedId = record.id),
                                    onDoubleTap: _isDriver || kind.isCatalog
                                        ? () => _openForm(
                                            record: record,
                                            readOnly: true,
                                          )
                                        : null,
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
                                            width: _isDriver ? 100 : 66,
                                            child: _cell(
                                              record.displayCode(
                                                kind,
                                                simulated: memory.simulated,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: kind.isCatalog ? 2 : 1,
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
                                                if (!_isDriver &&
                                                    constraints.maxWidth <
                                                        600 &&
                                                    detail.isNotEmpty)
                                                  _cell(detail, muted: true),
                                              ],
                                            ),
                                          ),
                                          if (kind.isCatalog)
                                            for (final cell in _catalogColumns(
                                              record,
                                            ))
                                              Expanded(
                                                child: _cell(cell, muted: true),
                                              )
                                          else if (_isDriver ||
                                              constraints.maxWidth >= 600)
                                            Expanded(child: _cell(detail)),
                                          if (_isDriver)
                                            SizedBox(
                                              width: 44,
                                              child: _cell(record.uf),
                                            ),
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
                  memory.simulated
                      ? '${records.length} registro(s) • Dados simulados, somente nesta sessão.'
                      : '${records.length} registro(s) • Consulta de dados oficiais disponíveis.',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            );
          },
        ),
      );
    },
  );

  Widget _withReason(String? reason, Widget child) =>
      reason == null ? child : Tooltip(message: reason, child: child);

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
