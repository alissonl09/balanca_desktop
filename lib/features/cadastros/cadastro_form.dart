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
}) => showDialog<CadastroRecord>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _CadastroForm(kind: kind, memory: memory, record: record),
);

class _CadastroForm extends StatefulWidget {
  const _CadastroForm({required this.kind, required this.memory, this.record});
  final CadastroKind kind;
  final CadastrosMemory memory;
  final CadastroRecord? record;
  @override
  State<_CadastroForm> createState() => _CadastroFormState();
}

class _CadastroFormState extends State<_CadastroForm> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final Map<String, TextEditingController> _fields;
  late final int _code;
  PersonType? _personType;
  DriverLink? _driverLink;
  String? _uf;
  int? _carrierCode;
  CadastroKind get kind => widget.kind;

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
    _code = record?.code ?? widget.memory.nextCode(kind);
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
      'taxId': TextEditingController(text: record?.taxId ?? ''),
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

  void _save() {
    if (!_form.currentState!.validate()) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return;
    }
    Navigator.pop(
      context,
      CadastroRecord(
        code: _code,
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
        taxId: _value('taxId'),
        stateRegistration: _value('stateRegistration'),
        enrollment: _value('enrollment'),
        observation: _fields['observation']!.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
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
            child: Text(
              '${widget.record == null ? 'Inserir' : 'Alterar'} — ${kind.title}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.heading,
              ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row(
                        [
                          TextFormField(
                            key: const ValueKey('cadastro-code'),
                            initialValue: '$_code',
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Código',
                              fillColor: Color(0xfff3f5f4),
                            ),
                          ),
                          if (kind == CadastroKind.remetentes) _typeField(),
                          if (kind == CadastroKind.placas) _plateField(),
                          if (kind == CadastroKind.motoristas) _linkField(),
                          if (kind == CadastroKind.motoristas &&
                              _driverLink == DriverLink.transportadora)
                            _carrierField(),
                        ],
                        widths: [
                          110,
                          if (kind == CadastroKind.remetentes)
                            200
                          else if (kind == CadastroKind.placas)
                            190
                          else if (kind == CadastroKind.motoristas)
                            200,
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
                            _text('postalCode', 'CEP', hint: '00000-000'),
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
                          if (kind != CadastroKind.motoristas)
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _save,
                  child: const Text('Salvar'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _text(
    String field,
    String label, {
    String? hint,
    bool required = false,
    int lines = 1,
  }) => TextFormField(
    key: ValueKey('cadastro-$field'),
    controller: _fields[field],
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
    decoration: const InputDecoration(labelText: 'Vínculo *'),
    items: [
      for (final link in DriverLink.values)
        DropdownMenuItem(value: link, child: Text(link.label)),
    ],
    validator: (value) => value == null ? 'Selecione o vínculo.' : null,
    onChanged: (value) => setState(() {
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
      for (final uf in _ufs) DropdownMenuItem(value: uf, child: Text(uf)),
    ],
    onChanged: (value) => _uf = value,
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
        final normalized = newValue.text.toUpperCase().replaceAll(
          RegExp(r'[^A-Z0-9]'),
          '',
        );
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
        : !RegExp(r'^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$').hasMatch(value)
        ? 'Informe uma placa brasileira válida.'
        : null,
  );

  Widget _row(List<Widget> children, {List<double?>? widths}) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 560) {
        return Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            for (var i = 0; i < children.length; i++)
              SizedBox(
                width: widths != null && i < widths.length
                    ? widths[i] ?? constraints.maxWidth
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
