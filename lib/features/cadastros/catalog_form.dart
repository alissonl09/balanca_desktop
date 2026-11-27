import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../configuracoes/settings_widgets.dart';
import 'cadastro_record.dart';
import 'cadastros_memory.dart';
import 'catalog_details.dart';
import 'operation_associations.dart';

Future<CadastroRecord?> showCatalogForm(
  BuildContext context, {
  required CadastroKind kind,
  required CadastrosMemory memory,
  CadastroRecord? record,
  required bool readOnly,
}) {
  final action = readOnly
      ? CadastroAction.read
      : record == null
      ? CadastroAction.insert
      : CadastroAction.edit;
  if (memory.unavailable(kind, action) != null ||
      (record == null ? readOnly : !memory.records(kind).contains(record))) {
    return Future.value();
  }
  return showDialog<CadastroRecord>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CatalogForm(
      kind: kind,
      memory: memory,
      record: record,
      readOnly: readOnly,
      action: action,
    ),
  );
}

class _CatalogForm extends StatefulWidget {
  const _CatalogForm({
    required this.kind,
    required this.memory,
    required this.record,
    required this.readOnly,
    required this.action,
  });

  final CadastroKind kind;
  final CadastrosMemory memory;
  final CadastroRecord? record;
  final bool readOnly;
  final CadastroAction action;

  @override
  State<_CatalogForm> createState() => _CatalogFormState();
}

class _CatalogFormState extends State<_CatalogForm> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final int? _code;
  late final Map<String, TextEditingController> _input;
  late bool _active;
  OperationNature? _nature;
  bool? _calculates, _receiving;
  ToleranceUnit? _toleranceUnit;
  AttributeType? _type;
  String? _standard, _bag, _bulk;
  List<AttributeBinding> _attributes = [];
  String? _error;
  bool _saving = false;

  bool get _readOnly => widget.readOnly;
  CadastroKind get _kind => widget.kind;
  CadastroRecord? get _record => widget.record;
  CadastrosMemory get _memory => widget.memory;

  @override
  void initState() {
    super.initState();
    _code = _record == null ? _memory.nextCode(_kind) : _record!.code;
    _active = _record?.active ?? true;
    final details = _record?.catalog;
    final tolerance = details is ToleranceDetails ? details : null;
    final attribute = details is AttributeDetails ? details : null;
    if (details is OperationDetails) {
      _nature = details.nature;
      _standard = details.standard;
      _bag = details.bag;
      _bulk = details.bulk;
      _attributes = [...details.attributes];
    }
    _calculates = tolerance?.calculates;
    _receiving = tolerance?.receivingWeight;
    _toleranceUnit = tolerance?.unit;
    _type = attribute?.type;
    _input = {
      for (final entry in <String, Object?>{
        'name': _record?.name,
        'observations': _record?.observation,
        'loss': tolerance?.loss,
        'yield': tolerance?.yield,
        'unit': attribute?.unit,
        'max-length': attribute?.maxLength,
        'minimum': attribute?.minimum,
        'maximum': attribute?.maximum,
        'precision': attribute?.precision,
        'decimal-places': attribute?.decimalPlaces,
        'start-date': _dateLabel(attribute?.startDate),
        'end-date': _dateLabel(attribute?.endDate),
        'options': attribute?.options
            .map((option) => '${option.id}=${option.label}')
            .join('\n'),
      }.entries)
        entry.key: TextEditingController(text: entry.value?.toString() ?? ''),
    };
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final controller in _input.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _dateLabel(DateTime? value) =>
      value?.toIso8601String().split('T').first;
  String _text(String key) => _input[key]!.text.trim();
  String? _optional(String key) => _text(key).isEmpty ? null : _text(key);
  double? _number(String key) =>
      double.tryParse(_text(key).replaceAll(',', '.'));
  int? _integer(String key) => int.tryParse(_text(key));
  DateTime? _date(String key) => DateTime.tryParse(_text(key));

  String? _validateNumber(String? value, {bool integer = false}) {
    if (value == null || value.trim().isEmpty) return null;
    return (integer
            ? int.tryParse(value.trim()) != null
            : double.tryParse(value.trim().replaceAll(',', '.'))?.isFinite ==
                  true)
        ? null
        : 'Informe um número válido.';
  }

  String? _validateDate(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return _dateLabel(DateTime.tryParse(text)) == text
        ? null
        : 'Use uma data válida no formato AAAA-MM-DD.';
  }

  List<AttributeOption> _options() => [
    for (final line in _text('options').split('\n'))
      if (line.trim().isNotEmpty)
        (
          id: line.split('=').first.trim(),
          label: line.contains('=')
              ? line.substring(line.indexOf('=') + 1).trim()
              : '',
        ),
  ];

  CatalogDetails _details() => switch (_kind) {
    CadastroKind.itens => const ItemDetails(),
    CadastroKind.operacoes => OperationDetails(
      nature: _nature!,
      process: switch (_record?.catalog) {
        OperationDetails(:final process) => process,
        _ => null,
      },
      standard: _standard,
      bag: _bag,
      bulk: _bulk,
      attributes: _attributes,
    ),
    CadastroKind.tolerancias => _toleranceDetails(),
    CadastroKind.complementos => _definition(_type!),
    _ => throw StateError('Cadastro fora do catálogo.'),
  };

  ToleranceDetails _toleranceDetails() {
    final original = _record?.catalog;
    final previous = original is ToleranceDetails ? original : null;
    return ToleranceDetails(
      calculates: _calculates!,
      unit: _calculates! ? _toleranceUnit : previous?.unit,
      loss: _calculates! ? _number('loss') : previous?.loss,
      yield: _calculates! ? _number('yield') : previous?.yield,
      receivingWeight: _calculates! ? _receiving : previous?.receivingWeight,
    );
  }

  AttributeDetails _definition(AttributeType type) {
    final integer = type == AttributeType.inteiro;
    final decimal = type == AttributeType.decimal || type == AttributeType.peso;
    final numeric = integer || decimal;
    return AttributeDetails(
      type: type,
      unit: type == AttributeType.peso
          ? 'kg'
          : numeric
          ? _optional('unit')
          : null,
      maxLength: type == AttributeType.texto ? _integer('max-length') : null,
      minimum: integer
          ? _integer('minimum')
          : decimal
          ? _number('minimum')
          : null,
      maximum: integer
          ? _integer('maximum')
          : decimal
          ? _number('maximum')
          : null,
      precision: decimal ? _integer('precision') : null,
      decimalPlaces: decimal ? _integer('decimal-places') : null,
      startDate: type == AttributeType.data ? _date('start-date') : null,
      endDate: type == AttributeType.data ? _date('end-date') : null,
      options: type == AttributeType.listaValores ? _options() : const [],
    );
  }

  void _save() {
    if (_readOnly || _saving || !_form.currentState!.validate()) return;
    _saving = true;
    try {
      final result = CadastroRecord(
        code: _code,
        sourceId: _record?.sourceId,
        name: _text('name'),
        active: _active,
        catalog: _details(),
        observation: _kind == CadastroKind.itens ? _text('observations') : '',
      );
      _memory.save(_kind, result, previous: _record);
      Navigator.pop(context, result);
    } on CadastroException catch (error) {
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    int lines = 1,
    bool locked = false,
    String? Function(String?)? validate,
  }) => TextFormField(
    key: ValueKey('catalog-$key'),
    controller: _input[key],
    readOnly: _readOnly || locked,
    maxLines: lines,
    decoration: InputDecoration(labelText: label, helperText: hint),
    validator: _readOnly || locked ? null : validate,
  );

  Widget _select<T>(
    String key,
    String label,
    T? value,
    Map<T, String> options,
    ValueChanged<T?> changed, {
    bool required = false,
    bool locked = false,
    String empty = 'Não informado',
  }) => DropdownButtonFormField<T>(
    key: ValueKey('catalog-$key'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      if (!required) DropdownMenuItem(child: Text(empty)),
      for (final item in options.entries)
        DropdownMenuItem(
          value: item.key,
          child: Text(item.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: _readOnly || locked ? null : changed,
    validator: required && !_readOnly
        ? (value) => value == null ? 'Selecione uma opção.' : null
        : null,
  );

  static const _yesNo = {true: 'Sim', false: 'Não'};

  Widget _section(String title, List<Widget> fields) => SettingsSection(
    title: title,
    child: SettingsFields(children: fields),
  );

  Widget _general() {
    final process = switch (_record?.catalog) {
      OperationDetails(:final process) => process,
      _ => null,
    };
    return _section('Dados gerais', [
      TextFormField(
        key: const ValueKey('catalog-code'),
        initialValue:
            _record?.displayCode(_kind, simulated: _memory.simulated) ??
            'SIM-$_code',
        readOnly: true,
        decoration: InputDecoration(
          labelText: _kind == CadastroKind.operacoes
              ? 'Código do roteiro'
              : 'Código',
        ),
      ),
      _field(
        'name',
        'Descrição',
        validate: (value) => value == null || value.trim().isEmpty
            ? 'Informe a descrição.'
            : null,
      ),
      _select(
        'active',
        'Situação',
        _active,
        const {true: 'Ativo', false: 'Inativo'},
        (active) => setState(() => _active = active!),
        required: true,
        locked:
            _record?.active == true &&
            _memory.unavailable(_kind, CadastroAction.deactivate) != null,
      ),
      if (_kind == CadastroKind.itens)
        _field('observations', 'Observações', lines: 2),
      if (_kind == CadastroKind.operacoes) ...[
        _select(
          'nature',
          'Natureza da operação',
          _nature,
          {for (final nature in OperationNature.values) nature: nature.label},
          (value) => setState(() => _nature = value),
          required: true,
        ),
        if (process != null)
          TextFormField(
            initialValue: process,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Processo corporativo',
            ),
          ),
      ],
    ]);
  }

  Widget _tolerance() {
    final locked = _calculates != true;
    final unit = _toleranceUnit?.symbol;
    return _section('Parâmetros de tolerância', [
      _select(
        'calculates',
        'Calcula tolerância',
        _calculates,
        _yesNo,
        (value) => setState(() => _calculates = value),
        required: true,
      ),
      if (_calculates == false)
        const Text(
          'Regra explícita sem cálculo. Os parâmetros ficam indisponíveis.',
        ),
      _select(
        'tolerance-unit',
        'Tipo',
        _toleranceUnit,
        {for (final value in ToleranceUnit.values) value: value.label},
        (value) => setState(() => _toleranceUnit = value),
        locked: locked,
        required: !locked,
      ),
      _field(
        'loss',
        unit == null ? 'Quebra' : 'Quebra ($unit)',
        locked: locked,
        validate: _validateNumber,
      ),
      _field(
        'yield',
        unit == null ? 'Renda' : 'Renda ($unit)',
        locked: locked,
        validate: _validateNumber,
      ),
      _select(
        'receiving-weight',
        'Usa peso da estação de recebimento',
        _receiving,
        _yesNo,
        (value) => setState(() => _receiving = value),
        locked: locked,
      ),
    ]);
  }

  Widget _attribute() {
    final type = _type;
    final integer = type == AttributeType.inteiro;
    final decimal = type == AttributeType.decimal || type == AttributeType.peso;
    return _section('Tipo e validações', [
      _select(
        'type',
        'Tipo',
        type,
        {for (final value in AttributeType.values) value: value.label},
        (value) => setState(() => _type = value),
        required: true,
      ),
      if (type == AttributeType.texto)
        _field(
          'max-length',
          'Tamanho máximo',
          validate: (v) => _validateNumber(v, integer: true),
        ),
      if (integer || decimal) ...[
        if (type == AttributeType.peso)
          const Text('Unidade: kg')
        else
          _field('unit', 'Unidade'),
        _field(
          'minimum',
          'Valor mínimo',
          validate: (v) => _validateNumber(v, integer: integer),
        ),
        _field(
          'maximum',
          'Valor máximo',
          validate: (v) => _validateNumber(v, integer: integer),
        ),
      ],
      if (decimal) ...[
        _field(
          'precision',
          'Precisão',
          validate: (v) => _validateNumber(v, integer: true),
        ),
        _field(
          'decimal-places',
          'Casas decimais',
          validate: (v) => _validateNumber(v, integer: true),
        ),
      ],
      if (type == AttributeType.listaValores)
        _field(
          'options',
          'Opções permitidas',
          hint: 'Uma por linha, no formato CÓDIGO=Descrição.',
          lines: 4,
        ),
      if (type == AttributeType.data) ...[
        _field(
          'start-date',
          'Data mínima',
          hint: 'AAAA-MM-DD',
          validate: _validateDate,
        ),
        _field(
          'end-date',
          'Data máxima',
          hint: 'AAAA-MM-DD',
          validate: _validateDate,
        ),
      ],
    ]);
  }

  String _ruleLabel(CadastroRecord record) {
    final rule = record.catalog;
    return '${record.displayCode(CadastroKind.tolerancias, simulated: _memory.simulated)} · ${record.name}'
        '${!record.active
            ? ' · Inativa'
            : rule is ToleranceDetails && !rule.calculates
            ? ' · Sem cálculo'
            : ''}';
  }

  Widget _rules() {
    final rules = _memory.records(CadastroKind.tolerancias);
    Widget selector(
      String key,
      String title,
      String? value,
      ValueChanged<String?> changed,
    ) => _select(
      key,
      title,
      value,
      {
        if (value != null && !rules.any((record) => record.id == value))
          value: 'Regra indisponível ($value)',
        for (final record in rules)
          if (record.active || record.id == value)
            record.id: _ruleLabel(record),
      },
      (value) => setState(() => changed(value)),
      empty: 'Sem referência',
    );

    final draft = OperationDetails(
      nature: _nature ?? OperationNature.outro,
      standard: _standard,
      bag: _bag,
      bulk: _bulk,
    );
    final unavailable = [_standard, _bag, _bulk].whereType<String>().any(
      (id) => !rules.any(
        (record) =>
            record.id == id &&
            record.active &&
            record.catalog is ToleranceDetails,
      ),
    );
    return SettingsSection(
      title: 'Tolerância associada',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          SettingsFields(
            children: [
              selector(
                'standard',
                'Regra padrão',
                _standard,
                (v) => _standard = v,
              ),
              selector('bag', 'Regra BAG', _bag, (v) => _bag = v),
              selector('bulk', 'Regra GRANEL', _bulk, (v) => _bulk = v),
            ],
          ),
          if (draft.incompatibleRules)
            Text(
              draft.issue!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (draft.incompleteRules || unavailable)
            const Text(
              'Pendência de tolerância: referência incompleta ou indisponível.',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_memory, _memory.permissions]),
    builder: (context, _) {
      final access = _memory.unavailable(_kind, CadastroAction.read);
      final saveReason = _memory.unavailable(_kind, widget.action);
      final error = _error ?? saveReason;
      if (access != null) {
        return AlertDialog(
          content: Text(access),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      }
      return Dialog(
        key: const ValueKey('catalog-form'),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 990),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_readOnly
                          ? 'Consultar'
                          : _record == null
                          ? 'Inserir'
                          : 'Alterar'} · ${_kind.label}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.heading,
                      ),
                    ),
                    if (_memory.simulated)
                      const Text(
                        'Modo simulado',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: [
                          _general(),
                          if (_kind == CadastroKind.tolerancias) _tolerance(),
                          if (_kind == CadastroKind.complementos) _attribute(),
                          if (_kind == CadastroKind.operacoes) ...[
                            _rules(),
                            OperationAssociations(
                              memory: _memory,
                              bindings: _attributes,
                              readOnly: _readOnly || saveReason != null,
                              onChanged: (value) =>
                                  setState(() => _attributes = value),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    if (error != null)
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(_readOnly ? 'Fechar' : 'Cancelar'),
                        ),
                        if (!_readOnly)
                          FilledButton(
                            key: const ValueKey('catalog-save'),
                            onPressed: _saving || saveReason != null
                                ? null
                                : _save,
                            child: const Text('Salvar'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
