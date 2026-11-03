import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/visual_components.dart';
import '../configuracoes/settings_mock_data.dart';
import '../configuracoes/settings_widgets.dart';
import 'report_catalog.dart';

class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({super.key, required this.compact});
  final bool compact;
  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _RelatoriosPageState extends State<RelatoriosPage> {
  ReportDefinition? _selected;
  final _drafts = <String, ReportFilterDraft>{};
  final _detailsKey = GlobalKey();

  void _select(ReportDefinition report) {
    setState(() => _selected = report);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _detailsKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: 0,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1400),
      child: VisualCard(
        key: const ValueKey('reports-main-card'),
        radius: 14,
        shadow: true,
        padding: widget.compact
            ? const EdgeInsets.symmetric(horizontal: 20, vertical: 16)
            : EdgeInsets.all(MediaQuery.sizeOf(context).width <= 900 ? 18 : 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeading(
              title: 'Relatórios',
              subtitle:
                  'Selecione um relatório e prepare os filtros da consulta.',
              icon: Icons.assessment_outlined,
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 960
                    ? 3
                    : constraints.maxWidth >= 620
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final report in reportCatalog)
                      SizedBox(
                        width: width,
                        height: 144,
                        child: Semantics(
                          selected: _selected?.id == report.id,
                          child: Material(
                            color: _selected?.id == report.id
                                ? AppColors.paleGreen
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                              side: BorderSide(
                                color: _selected?.id == report.id
                                    ? AppColors.green
                                    : AppColors.border,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey('report-${report.id}'),
                              onTap: () => _select(report),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Tooltip(
                                      message: report.title,
                                      child: Text(
                                        report.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.heading,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      report.description,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            if (_selected case final report?)
              _filters(report)
            else
              const SettingsSection(
                title: 'Filtros e resultados',
                child: Text(
                  'Selecione um relatório acima para visualizar os filtros previstos.',
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _filters(ReportDefinition report) {
    final draft = _drafts.putIfAbsent(report.id, ReportFilterDraft.new);
    return KeyedSubtree(
      key: _detailsKey,
      child: SettingsSection(
        title: report.title,
        description: report.description,
        child: KeyedSubtree(
          key: ValueKey(report.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsFields(
                children: [
                  for (final filter in report.filters)
                    _filterField(report.id, filter, draft),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Tooltip(
                    message: 'Aguardando a futura camada de dados.',
                    child: ElevatedButton(
                      onPressed: null,
                      child: Text('Gerar relatório'),
                    ),
                  ),
                  const Tooltip(
                    message: 'Disponível após a implementação dos resultados e da impressão.',
                    child: OutlinedButton(
                      onPressed: null,
                      child: Text('Imprimir'),
                    ),
                  ),
                  const Tooltip(
                    message: 'Exportação será implementada posteriormente.',
                    child: OutlinedButton(
                      onPressed: null,
                      child: Text('Exportar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Geração, impressão e exportação aguardam a camada de dados.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const Divider(height: 28),
              const Text(
                'Resultados',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Os resultados serão exibidos aqui após a integração com a fonte de dados. Nenhuma consulta foi executada.',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterField(
    String reportId,
    ReportFilter filter,
    ReportFilterDraft draft,
  ) {
    final value = draft.values[filter] ?? '';
    final key = ValueKey('filter-$reportId-${filter.name}');
    if (filter == ReportFilter.unit) {
      return DropdownButtonFormField<String>(
        key: key,
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Unidade'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todas')),
          for (final unit in mockUnits)
            DropdownMenuItem(
              value: '${unit.code}',
              child: Text('${unit.label} (simulada)'),
            ),
        ],
        onChanged: (value) => draft.values[filter] = value ?? '',
      );
    }
    if (filter == ReportFilter.status) {
      return DropdownButtonFormField<String>(
        key: key,
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Status'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos')),
          if (reportId == 'pesagens') ...const [
            DropdownMenuItem(value: 'abertas', child: Text('Em aberto')),
            DropdownMenuItem(value: 'finalizadas', child: Text('Finalizadas')),
          ] else if (reportId == 'tickets') ...const [
            DropdownMenuItem(value: 'emitidos', child: Text('Emitido')),
            DropdownMenuItem(value: 'cancelados', child: Text('Cancelado')),
          ] else ...const [
            DropdownMenuItem(value: 'ativos', child: Text('Ativo')),
            DropdownMenuItem(value: 'inativos', child: Text('Inativo')),
          ],
        ],
        onChanged: (value) => draft.values[filter] = value ?? '',
      );
    }
    if (filter == ReportFilter.manual || filter == ReportFilter.divergence) {
      return DropdownButtonFormField<String>(
        key: key,
        initialValue: value,
        decoration: InputDecoration(labelText: filter.label),
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: '', child: Text('Todas')),
          DropdownMenuItem(value: 'sim', child: Text('Sim')),
          DropdownMenuItem(value: 'nao', child: Text('Não')),
        ],
        onChanged: (value) => draft.values[filter] = value ?? '',
      );
    }
    if (filter.isDate) {
      final date = DateTime.tryParse(value);
      return TextFormField(
        key: ValueKey('${key.value}-$value'),
        readOnly: true,
        initialValue: date == null
            ? ''
            : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
        decoration: InputDecoration(
          labelText: filter.label,
          hintText: 'dd/mm/aaaa',
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        onTap: () async {
          final selected = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime(2100),
            helpText: filter.label,
            cancelText: 'Cancelar',
            confirmText: 'Selecionar',
          );
          if (selected != null && mounted) {
            setState(() => draft.values[filter] = selected.toIso8601String());
          }
        },
      );
    }
    return TextFormField(
      key: key,
      initialValue: value,
      decoration: InputDecoration(
        labelText: filter.label,
        hintText: 'Filtro para futura consulta',
      ),
      onChanged: (value) => draft.values[filter] = value,
    );
  }
}
