import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import 'cadastro_record.dart';
import 'cadastros_memory.dart';
import 'carrier_selection_field.dart';

Future<CadastroRecord?> showCadastroForm(
  BuildContext context, {
  required CadastroKind kind,
  required CadastrosMemory memory,
  CadastroRecord? record,
  bool readOnly = false,
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
    builder: (_) => _CadastroForm(
      kind: kind,
      memory: memory,
      record: record,
      readOnly: readOnly,
      action: action,
    ),
  );
}

class _CadastroForm extends StatefulWidget {
  const _CadastroForm({
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
  State<_CadastroForm> createState() => _CadastroFormState();
}

class _CadastroFormState extends State<_CadastroForm> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final Map<String, TextEditingController> _fields;
  late final int? _code;
  late final String _displayCode;
  late final Map<String, String> _linkedPlates;
  PersonType? _personType;
  DriverLink? _driverLink;
  String? _uf;
  int? _carrierCode;
  bool _dirty = false;
  bool _confirmingDiscard = false;
  bool _pickingPlate = false;
  bool _saving = false;
  String? _saveError;
  CadastroKind get kind => widget.kind;
  CadastrosMemory get memory => widget.memory;
  bool get _isDriver => kind == CadastroKind.motoristas;

  static const _ufs = [
    'AC',
    'AL',
    'AP',
    'AM',
    'BA',
    'CE',
    'DF',
    'ES',
    'GO',
    'MA',
    'MT',
    'MS',
    'MG',
    'PA',
    'PB',
    'PR',
    'PE',
    'PI',
    'RJ',
    'RN',
    'RS',
    'RO',
    'RR',
    'SC',
    'SP',
    'SE',
    'TO',
  ];

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _code = record == null ? memory.nextCode(kind) : record.code;
    _displayCode =
        record?.displayCode(kind) ?? (_isDriver ? 'SIM-$_code' : '$_code');
    _linkedPlates = record == null ? {} : {...memory.linkedPlates(record)};
    _personType = record?.personType;
    _driverLink = record?.driverLink;
    _uf = record == null || record.uf.isEmpty ? null : record.uf;
    _carrierCode = record?.carrierCode;
    _fields = {
      'name': TextEditingController(text: record?.name ?? ''),
      'plate': TextEditingController(text: record?.plate ?? ''),
      'address': TextEditingController(text: record?.address ?? ''),
      'number': TextEditingController(text: record?.number ?? ''),
      'complement': TextEditingController(text: record?.complement ?? ''),
      'city': TextEditingController(text: record?.city ?? ''),
      'postalCode': TextEditingController(text: record?.postalCode ?? ''),
      if (!_isDriver) 'taxId': TextEditingController(text: record?.taxId ?? ''),
      'stateRegistration': TextEditingController(
        text: record?.stateRegistration ?? '',
      ),
      'enrollment': TextEditingController(text: record?.enrollment ?? ''),
      'observation': TextEditingController(text: record?.observation ?? ''),
    };
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  String _value(String field) => _fields[field]!.text.trim();

  void _markDirty() {
    if (_isDriver && !widget.readOnly && !_dirty) {
      setState(() => _dirty = true);
    }
  }

  Future<void> _close() async {
    if (_saving || _confirmingDiscard) return;
    if (_isDriver && _dirty) {
      _confirmingDiscard = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Descartar alterações?'),
          content: const Text(
            'As alterações do motorista e das placas vinculadas serão descartadas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Continuar editando'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );
      _confirmingDiscard = false;
      if (!mounted || discard != true) return;
    }
    Navigator.pop(context);
  }

  void _save() {
    if (widget.readOnly || _saving) return;
    if (!_form.currentState!.validate()) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final record = CadastroRecord(
      code: _code,
      sourceId: widget.record?.sourceId,
      registration: _isDriver
          ? _displayCode
          : widget.record?.registration ?? '',
      linkedVehicleIds: _linkedPlates.keys,
      name: _value('name'),
      plate: _value('plate'),
      personType: _personType,
      driverLink: _driverLink,
      carrierCode:
          kind == CadastroKind.placas ||
              _driverLink == DriverLink.transportadora
          ? _carrierCode
          : null,
      address: _value('address'),
      number: _value('number'),
      complement: _value('complement'),
      city: _value('city'),
      uf: _uf ?? '',
      postalCode: _value('postalCode'),
      taxId: _isDriver ? '' : _value('taxId'),
      stateRegistration: _value('stateRegistration'),
      enrollment: _value('enrollment'),
      observation: _fields['observation']!.text,
    );
    try {
      memory.save(kind, record, previous: widget.record);
      Navigator.pop(context, record);
    } on CadastroException catch (error) {
      setState(() {
        _saving = false;
        _saveError = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([memory, memory.permissions]),
    builder: (context, _) => _buildDialog(),
  );

  Widget _buildDialog() {
    final readReason = memory.unavailable(kind, CadastroAction.read);
    final saveReason = memory.unavailable(kind, widget.action);
    final error = _saveError ?? saveReason;
    if (readReason != null) {
      return AlertDialog(
        content: Text(readReason),
        actions: [TextButton(onPressed: _close, child: const Text('Fechar'))],
      );
    }
    final title = _isDriver
        ? widget.readOnly
              ? 'Consulta de motorista'
              : widget.record == null
              ? 'Incluindo motorista'
              : 'Alterando motorista'
        : '${widget.record == null ? 'Inserir' : 'Alterar'} — ${kind.title}';
    return PopScope(
      canPop: !_saving && (!_isDriver || !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Dialog(
        key: const ValueKey('cadastro-form'),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.heading,
                      ),
                    ),
                    if (memory.simulated)
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
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
                    child: Form(
                      key: _form,
                      onChanged: _markDirty,
                      child: _isDriver
                          ? _driverContent()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _row(
                                  [
                                    _codeField(),
                                    if (kind == CadastroKind.remetentes)
                                      _typeField(),
                                    if (kind == CadastroKind.placas)
                                      _plateField(),
                                  ],
                                  widths: [
                                    110,
                                    if (kind == CadastroKind.remetentes)
                                      200
                                    else if (kind == CadastroKind.placas)
                                      190,
                                    null,
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (kind == CadastroKind.placas)
                                  _carrierField()
                                else ...[
                                  _text('name', 'Nome *', required: true),
                                  const SizedBox(height: 16),
                                  _row(
                                    [
                                      _text('address', 'Endereço'),
                                      _text('number', 'Número'),
                                    ],
                                    widths: const [null, 100],
                                  ),
                                  const SizedBox(height: 16),
                                  _text('complement', 'Complemento'),
                                  const SizedBox(height: 16),
                                  _row(
                                    [
                                      _text('city', 'Cidade'),
                                      _ufField(),
                                      _text(
                                        'postalCode',
                                        'CEP',
                                        hint: '00000-000',
                                      ),
                                    ],
                                    widths: const [null, 90, 150],
                                  ),
                                  const SizedBox(height: 16),
                                  _row([
                                    _text(
                                      'taxId',
                                      kind == CadastroKind.transportadoras
                                          ? 'CNPJ'
                                          : 'CNPJ/CPF',
                                      hint: kind == CadastroKind.transportadoras
                                          ? '00.000.000/0000-00'
                                          : 'CPF ou CNPJ',
                                    ),
                                    _text('stateRegistration', 'IE'),
                                    if (kind == CadastroKind.remetentes)
                                      _text('enrollment', 'Matrícula'),
                                  ]),
                                  const SizedBox(height: 16),
                                  _text('observation', 'Observação', lines: 2),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              if (!widget.readOnly && error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : _close,
                      child: Text(widget.readOnly ? 'Fechar' : 'Cancelar'),
                    ),
                    if (!widget.readOnly) ...[
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _saving || saveReason != null ? null : _save,
                        child: const Text('Salvar'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeField() => TextFormField(
    key: const ValueKey('cadastro-code'),
    initialValue: _displayCode,
    readOnly: true,
    decoration: InputDecoration(
      labelText: _isDriver ? 'Matrícula' : 'Código',
      fillColor: const Color(0xfff3f5f4),
    ),
  );

  Widget _driverContent() => LayoutBuilder(
    builder: (context, constraints) {
      final personal = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _codeField(),
          const SizedBox(height: 16),
          _text('name', 'Nome completo *', required: true),
          const SizedBox(height: 16),
          _row(
            [_text('address', 'Endereço'), _text('number', 'Número')],
            widths: const [null, 90],
          ),
          const SizedBox(height: 16),
          _text('complement', 'Complemento'),
          const SizedBox(height: 16),
          _row(
            [
              _text('city', 'Cidade'),
              _ufField(),
              _text('postalCode', 'CEP', hint: '00000-000'),
            ],
            widths: const [null, 78, 114],
          ),
          const SizedBox(height: 16),
          _text('observation', 'Observações', lines: 2),
          if (!widget.readOnly || _driverLink != null) ...[
            const SizedBox(height: 16),
            _linkField(),
            if (_driverLink == DriverLink.transportadora) ...[
              const SizedBox(height: 16),
              if (widget.readOnly)
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Transportadora',
                  ),
                  child: Text(memory.carrierName(_carrierCode)),
                )
              else
                _carrierField(),
            ],
          ],
        ],
      );
      final plates = _driverPlates();
      if (constraints.maxWidth < 660) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [personal, const SizedBox(height: 24), plates],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: personal),
          const SizedBox(width: 24),
          SizedBox(width: 230, child: plates),
        ],
      );
    },
  );

  Widget _driverPlates() {
    final linkReason =
        memory.unavailable(kind, widget.action) ?? memory.linkUnavailable;
    final addReason =
        linkReason ??
        memory.unavailable(CadastroKind.placas, CadastroAction.read);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Placas vinculadas',
          style: TextStyle(
            color: AppColors.heading,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_linkedPlates.isEmpty) const Text('Nenhuma placa vinculada.'),
        for (final entry in _linkedPlates.entries)
          Row(
            children: [
              Expanded(child: Text(entry.value)),
              if (!widget.readOnly)
                IconButton(
                  key: ValueKey('driver-unlink-${entry.key}'),
                  tooltip: linkReason ?? 'Remover vínculo com ${entry.value}',
                  icon: const Icon(Icons.link_off),
                  onPressed: linkReason == null
                      ? () {
                          if (memory.unavailable(kind, widget.action) != null ||
                              memory.linkUnavailable != null) {
                            return;
                          }
                          setState(() {
                            _linkedPlates.remove(entry.key);
                            _dirty = true;
                          });
                        }
                      : null,
                ),
            ],
          ),
        if (!widget.readOnly) ...[
          const SizedBox(height: 8),
          Tooltip(
            message: addReason ?? 'Selecionar placa cadastrada',
            child: OutlinedButton.icon(
              key: const ValueKey('driver-add-plate'),
              onPressed: addReason == null ? _pickPlate : null,
              icon: const Icon(Icons.add_link, size: 18),
              label: const Text('Adicionar placa'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickPlate() async {
    if (_pickingPlate ||
        memory.unavailable(kind, widget.action) != null ||
        memory.linkUnavailable != null ||
        memory.unavailable(CadastroKind.placas, CadastroAction.read) != null) {
      return;
    }

    final linked = _linkedPlates.values.map(normalizeCadastroPlate).toSet();
    final vehicles = memory.records(CadastroKind.placas).where((vehicle) {
      final plate = normalizeCadastroPlate(vehicle.plate);
      return isCadastroPlate(plate) &&
          !linked.contains(plate) &&
          !_linkedPlates.containsKey(vehicle.id);
    }).toList();
    _pickingPlate = true;
    final vehicle = await showDialog<CadastroRecord>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Selecionar placa cadastrada'),
        children: [
          if (vehicles.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text('Nenhuma placa disponível para vincular.'),
            ),
          for (final vehicle in vehicles)
            SimpleDialogOption(
              key: ValueKey('driver-plate-option-${vehicle.id}'),
              onPressed: () => Navigator.pop(context, vehicle),
              child: Text(normalizeCadastroPlate(vehicle.plate)),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    _pickingPlate = false;
    if (!mounted ||
        vehicle == null ||
        memory.unavailable(kind, widget.action) != null ||
        memory.linkUnavailable != null ||
        !memory.records(CadastroKind.placas).contains(vehicle)) {
      return;
    }
    setState(() {
      _linkedPlates[vehicle.id] = normalizeCadastroPlate(vehicle.plate);
      _dirty = true;
    });
  }

  Widget _text(
    String field,
    String label, {
    String? hint,
    bool required = false,
    int lines = 1,
  }) => TextFormField(
    key: ValueKey('cadastro-$field'),
    controller: _fields[field],
    readOnly: widget.readOnly,
    maxLines: lines,
    style: const TextStyle(fontSize: 14),
    decoration: InputDecoration(labelText: label, hintText: hint),
    validator: required
        ? (value) =>
              value == null || value.trim().isEmpty ? 'Informe o nome.' : null
        : null,
  );

  Widget _typeField() => DropdownButtonFormField<PersonType>(
    key: const ValueKey('cadastro-type'),
    initialValue: _personType,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Tipo *'),
    items: [
      for (final type in PersonType.values)
        DropdownMenuItem(value: type, child: Text(type.label)),
    ],
    validator: (value) => value == null ? 'Selecione o tipo.' : null,
    onChanged: (value) => _personType = value,
  );

  Widget _linkField() => DropdownButtonFormField<DriverLink>(
    key: const ValueKey('cadastro-link'),
    initialValue: _driverLink,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Vínculo com transportadora'),
    items: [
      const DropdownMenuItem(value: null, child: Text('Não informado')),
      for (final link in DriverLink.values)
        DropdownMenuItem(value: link, child: Text(link.label)),
    ],
    onChanged: widget.readOnly
        ? null
        : (value) => setState(() {
            _driverLink = value;
            if (value != DriverLink.transportadora) _carrierCode = null;
          }),
  );

  Widget _ufField() => DropdownButtonFormField<String>(
    key: const ValueKey('cadastro-uf'),
    initialValue: _uf,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'UF'),
    items: [
      const DropdownMenuItem(value: '', child: Text('—')),
      if (_uf != null && _uf!.isNotEmpty && !_ufs.contains(_uf))
        DropdownMenuItem(value: _uf, child: Text(_uf!)),
      for (final uf in _ufs) DropdownMenuItem(value: uf, child: Text(uf)),
    ],
    onChanged: widget.readOnly ? null : (value) => _uf = value,
  );

  Widget _carrierField() => CarrierSelectionField(
    memory: widget.memory,
    initialValue: _carrierCode,
    onChanged: (value) => _carrierCode = value,
  );

  Widget _plateField() => TextFormField(
    key: const ValueKey('cadastro-plate'),
    controller: _fields['plate'],
    decoration: const InputDecoration(
      labelText: 'Placa *',
      hintText: 'ABC1D23',
    ),
    inputFormatters: [
      TextInputFormatter.withFunction((oldValue, newValue) {
        final normalized = normalizeCadastroPlate(newValue.text);
        final plate = normalized.length > 7
            ? normalized.substring(0, 7)
            : normalized;
        return TextEditingValue(
          text: plate,
          selection: TextSelection.collapsed(offset: plate.length),
        );
      }),
    ],
    validator: (value) => value == null || value.isEmpty
        ? 'Informe a placa.'
        : !isCadastroPlate(value)
        ? 'Informe uma placa brasileira válida.'
        : null,
  );

  Widget _row(List<Widget> children, {List<double?>? widths}) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < (_isDriver ? 370 : 560)) {
        return Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            for (var i = 0; i < children.length; i++)
              SizedBox(
                width: widths != null && i < widths.length
                    ? (widths[i] ?? constraints.maxWidth).clamp(
                        0.0,
                        constraints.maxWidth,
                      )
                    : constraints.maxWidth,
                child: children[i],
              ),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            if (widths != null && i < widths.length && widths[i] != null)
              SizedBox(width: widths[i], child: children[i])
            else
              Expanded(child: children[i]),
          ],
        ],
      );
    },
  );
}
