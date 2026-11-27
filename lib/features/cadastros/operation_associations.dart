import 'package:flutter/material.dart';

import '../configuracoes/settings_widgets.dart';
import 'cadastro_record.dart';
import 'cadastros_memory.dart';
import 'catalog_details.dart';

class OperationAssociations extends StatelessWidget {
  const OperationAssociations({
    super.key,
    required this.memory,
    required this.bindings,
    required this.readOnly,
    required this.onChanged,
  });

  final CadastrosMemory memory;
  final List<AttributeBinding> bindings;
  final bool readOnly;
  final ValueChanged<List<AttributeBinding>> onChanged;

  static const _headers = [
    'Atributo',
    'Tipo',
    'Obrigatório',
    'Coleta',
    'Permite alteração',
    'Exibir no ticket',
    'Ordem',
    'Produto',
    'Acondicionamento',
  ];

  String _label(CadastroKind kind, CadastroRecord record) =>
      '${record.displayCode(kind, simulated: memory.simulated)} · ${record.name}';
  String _yesNo(bool value) => value ? 'Sim' : 'Não';

  List<String> _row(AttributeBinding binding) {
    final attribute = memory
        .records(CadastroKind.complementos)
        .where((record) => record.id == binding.attributeId)
        .firstOrNull;
    final product = memory
        .records(CadastroKind.itens)
        .where((record) => record.id == binding.productId)
        .firstOrNull;
    final definition = attribute?.catalog;
    return [
      attribute == null
          ? 'Atributo indisponível (${binding.attributeId})'
          : _label(CadastroKind.complementos, attribute),
      definition is AttributeDetails ? definition.type.label : '—',
      _yesNo(binding.required),
      binding.phase.label,
      _yesNo(binding.editable),
      _yesNo(binding.printOnTicket),
      '${binding.order}',
      product != null
          ? _label(CadastroKind.itens, product)
          : binding.productId == null
          ? 'Todos'
          : 'Indisponível (${binding.productId})',
      binding.packaging ?? 'Todos',
    ];
  }

  Future<void> _edit(BuildContext context, [int? index]) async {
    if (readOnly && index == null) return;
    final prior = index == null ? null : bindings[index];
    Map<String, String> options(CadastroKind kind, String? current) {
      final records = memory.records(kind);
      return {
        if (current != null && !records.any((record) => record.id == current))
          current: 'Registro indisponível ($current)',
        for (final record in records)
          if (record.active || record.id == current)
            record.id: _label(kind, record),
      };
    }

    final attributes = options(CadastroKind.complementos, prior?.attributeId);
    if (attributes.isEmpty) return;
    final products = options(CadastroKind.itens, prior?.productId);
    final result = await showDialog<AttributeBinding>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BindingForm(
        initial: prior,
        readOnly: readOnly,
        attributes: attributes,
        products: products,
        others: [
          for (final (position, binding) in bindings.indexed)
            if (position != index) binding,
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    final updated = [...bindings];
    if (index == null) {
      updated.add(result);
    } else {
      updated[index] = result;
    }
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = OperationDetails(
      nature: OperationNature.outro,
      attributes: bindings,
    ).hasContextConflict;
    return SettingsSection(
      title: 'Informações complementares associadas',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 725;
          final rows = [for (final binding in bindings) _row(binding)];
          Widget cell(String value, {bool header = false}) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: header ? FontWeight.w600 : null,
              ),
            ),
          );
          Widget actions(int index) => Wrap(
            children: [
              IconButton(
                tooltip: readOnly
                    ? 'Consultar associação'
                    : 'Alterar associação',
                icon: Icon(
                  readOnly ? Icons.visibility_outlined : Icons.edit_outlined,
                  size: 18,
                ),
                onPressed: () => _edit(context, index),
              ),
              if (!readOnly)
                IconButton(
                  tooltip: 'Remover associação do rascunho',
                  icon: const Icon(Icons.link_off, size: 18),
                  onPressed: () => onChanged([...bindings]..removeAt(index)),
                ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              if (conflicts)
                const Text(
                  'Conflito de contexto: produto e acondicionamento podem aplicar regras ao mesmo atributo. A precedência depende de homologação.',
                ),
              if (bindings.isEmpty)
                const Text('Nenhuma informação complementar associada.')
              else if (wide)
                Table(
                  key: const ValueKey('catalog-bindings-table'),
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    7: FlexColumnWidth(1.45),
                    8: FlexColumnWidth(1.4),
                    6: FlexColumnWidth(.65),
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      children: [
                        for (final label in _headers) cell(label, header: true),
                        cell('Ações', header: true),
                      ],
                    ),
                    for (final (index, values) in rows.indexed)
                      TableRow(
                        children: [
                          for (final value in values) cell(value),
                          actions(index),
                        ],
                      ),
                  ],
                )
              else
                for (final (index, values) in rows.indexed)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 10),
                      for (final (column, value) in values.indexed)
                        Text('${_headers[column]}: $value'),
                      actions(index),
                    ],
                  ),
              if (!readOnly)
                OutlinedButton.icon(
                  key: const ValueKey('catalog-add-binding'),
                  onPressed:
                      memory
                          .records(CadastroKind.complementos)
                          .any((record) => record.active)
                      ? () => _edit(context)
                      : null,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Adicionar associação'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BindingForm extends StatefulWidget {
  const _BindingForm({
    required this.initial,
    required this.readOnly,
    required this.attributes,
    required this.products,
    required this.others,
  });
  final AttributeBinding? initial;
  final bool readOnly;
  final Map<String, String> attributes, products;
  final List<AttributeBinding> others;
  @override
  State<_BindingForm> createState() => _BindingFormState();
}

class _BindingFormState extends State<_BindingForm> {
  final _form = GlobalKey<FormState>();
  late String? _attribute = widget.initial?.attributeId;
  late String? _product = widget.initial?.productId;
  late String? _packaging = widget.initial?.packaging;
  late CollectionPhase? _phase = widget.initial?.phase;
  late bool _required = widget.initial?.required ?? false;
  late bool _editable = widget.initial?.editable ?? false;
  late bool _printOnTicket = widget.initial?.printOnTicket ?? false;
  late int? _order = widget.initial?.order;
  String? _error;

  Widget _select<T>(
    String label,
    T? value,
    Map<T, String> options,
    ValueChanged<T?> change, {
    bool optional = false,
  }) => DropdownButtonFormField<T>(
    key: ValueKey('binding-$label'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      if (optional) const DropdownMenuItem(child: Text('Todos')),
      for (final entry in options.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(entry.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: widget.readOnly ? null : change,
    validator: optional
        ? null
        : (value) => value == null ? 'Selecione uma opção.' : null,
  );

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (widget.others.any(
      (entry) =>
          entry.attributeId == _attribute &&
          entry.productId == _product &&
          entry.packaging == _packaging,
    )) {
      setState(
        () => _error = 'O mesmo atributo já está associado neste contexto.',
      );
      return;
    }
    Navigator.pop(context, (
      attributeId: _attribute!,
      required: _required,
      phase: _phase!,
      editable: _editable,
      printOnTicket: _printOnTicket,
      order: _order!,
      productId: _product,
      packaging: _packaging,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.readOnly
          ? 'Consultar associação'
          : widget.initial == null
          ? 'Adicionar associação'
          : 'Alterar associação',
    ),
    scrollable: true,
    content: SizedBox(
      width: 700,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            _select(
              'Atributo',
              _attribute,
              widget.attributes,
              (value) => _attribute = value,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                _select('Momento de coleta', _phase, {
                  for (final phase in CollectionPhase.values)
                    phase: phase.label,
                }, (value) => _phase = value),
                TextFormField(
                  key: const ValueKey('catalog-binding-order'),
                  initialValue: _order?.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Ordem de apresentação',
                  ),
                  keyboardType: TextInputType.number,
                  readOnly: widget.readOnly,
                  onChanged: (value) => _order = int.tryParse(value.trim()),
                  validator: (_) => _order == null || _order! < 1
                      ? 'Informe uma ordem positiva.'
                      : null,
                ),
                _select(
                  'Produto específico',
                  _product,
                  widget.products,
                  (value) => _product = value,
                  optional: true,
                ),
                _select(
                  'Acondicionamento específico',
                  _packaging,
                  {
                    'BAG': 'BAG',
                    'GRANEL': 'GRANEL',
                    if (_packaging != null &&
                        _packaging != 'BAG' &&
                        _packaging != 'GRANEL')
                      _packaging!: _packaging!,
                  },
                  (value) => _packaging = value,
                  optional: true,
                ),
              ],
            ),
            if (widget.readOnly) ...[
              Text('Obrigatório: ${_required ? 'Sim' : 'Não'}'),
              Text('Permite alteração: ${_editable ? 'Sim' : 'Não'}'),
              Text('Exibir no ticket: ${_printOnTicket ? 'Sim' : 'Não'}'),
            ] else ...[
              SettingsToggle(
                label: 'Obrigatório',
                value: _required,
                onChanged: (value) => setState(() => _required = value),
              ),
              SettingsToggle(
                label: 'Permite alteração',
                value: _editable,
                onChanged: (value) => setState(() => _editable = value),
              ),
              SettingsToggle(
                label: 'Exibir no ticket',
                value: _printOnTicket,
                onChanged: (value) => setState(() => _printOnTicket = value),
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.readOnly ? 'Fechar' : 'Cancelar'),
      ),
      if (!widget.readOnly)
        FilledButton(
          onPressed: _save,
          child: const Text('Confirmar associação'),
        ),
    ],
  );
}
