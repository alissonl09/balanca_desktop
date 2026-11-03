import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'cadastro_record.dart';
import 'cadastros_memory.dart';

/// Seleção por código de uma transportadora cadastrada, nunca por texto livre.
class CarrierSelectionField extends StatelessWidget {
  const CarrierSelectionField({
    super.key,
    required this.memory,
    this.initialValue,
    required this.onChanged,
  });
  final CadastrosMemory memory;
  final int? initialValue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => FormField<int>(
    initialValue: initialValue,
    validator: (value) => memory.carrier(value) == null
        ? 'Selecione uma transportadora cadastrada.'
        : null,
    builder: (field) {
      Future<void> choose() async {
        final carrier = await showDialog<CadastroRecord>(
          context: context,
          builder: (_) => _CarrierPicker(memory: memory),
        );
        if (carrier == null || !context.mounted) return;
        field.didChange(carrier.code);
        onChanged(carrier.code);
      }

      final carrier = memory.carrier(field.value);
      return InkWell(
        key: const ValueKey('cadastro-carrier'),
        onTap: choose,
        borderRadius: BorderRadius.circular(7),
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            labelText: 'Transportadora *',
            errorText: field.errorText,
            suffixIcon: IconButton(
              tooltip: 'Selecionar transportadora',
              onPressed: choose,
              icon: const Icon(Icons.search, size: 20, color: AppColors.green),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
          ),
          child: Tooltip(
            message: carrier?.name ?? '',
            child: Text(
              carrier?.name ??
                  (field.value == null
                      ? 'Selecionar transportadora'
                      : memory.carrierName(field.value)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: carrier == null ? AppColors.muted : AppColors.text,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CarrierPicker extends StatefulWidget {
  const _CarrierPicker({required this.memory});
  final CadastrosMemory memory;
  @override
  State<_CarrierPicker> createState() => _CarrierPickerState();
}

class _CarrierPickerState extends State<_CarrierPicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _filter = '';

  void _applySearch() =>
      setState(() => _filter = _search.text.trim().toLowerCase());

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final carriers = widget.memory
        .records(CadastroKind.transportadoras)
        .where(
          (carrier) =>
              carrier.code.toString().contains(_filter) ||
              carrier.name.toLowerCase().contains(_filter),
        )
        .toList();
    return Dialog(
      key: const ValueKey('carrier-picker'),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Selecionar transportadora',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('carrier-search'),
                controller: _search,
                autofocus: true,
                onChanged: (_) => _applySearch(),
                onSubmitted: (_) => _applySearch(),
                decoration: InputDecoration(
                  hintText: 'Pesquisar por código ou nome',
                  suffixIcon: IconButton(
                    tooltip: 'Pesquisar transportadora',
                    onPressed: _applySearch,
                    icon: const Icon(
                      Icons.search,
                      color: AppColors.green,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: carriers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Nenhuma transportadora encontrada. Cadastre-a na aba Transportadoras.',
                        ),
                      )
                    : Scrollbar(
                        controller: _scroll,
                        child: ListView.builder(
                          controller: _scroll,
                          shrinkWrap: true,
                          itemCount: carriers.length,
                          itemBuilder: (context, index) => ListTile(
                            key: ValueKey(
                              'carrier-option-${carriers[index].code}',
                            ),
                            leading: Text(
                              '${carriers[index].code}',
                              style: const TextStyle(color: AppColors.green),
                            ),
                            title: Text(carriers[index].name),
                            onTap: () =>
                                Navigator.pop(context, carriers[index]),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
