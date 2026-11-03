import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import 'print_layout_preview.dart';
import 'settings_mock_data.dart';
import 'settings_models.dart';
import 'settings_widgets.dart';
import '../ticket/ticket_mapper.dart';
import '../ticket/ticket_preview.dart';
import '../ticket/ticket_session.dart';

class PrintingSettings extends StatelessWidget {
  const PrintingSettings({
    super.key,
    required this.settings,
    required this.ticketSession,
  });
  final SettingsState settings;
  final TicketSession ticketSession;

  Future<void> _changeLogo(BuildContext context) async {
    final logo = await showDialog<TicketLogo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Imagem do ticket'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Opções de demonstração. A seleção de arquivo local será conectada posteriormente.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, TicketLogo.standard),
            child: const Text('Logomarca padrão'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, TicketLogo.demonstration),
            child: const Text('Imagem de demonstração'),
          ),
        ],
      ),
    );
    if (logo != null) settings.update(() => settings.printing.logo = logo);
  }

  @override
  Widget build(BuildContext context) {
    final printing = settings.printing;
    final printer = mockPrinters.firstWhere(
      (printer) => printer.id == printing.printerId,
    );
    final paper = printing.paperByPrinter.putIfAbsent(
      printer.id,
      printer.defaultPaper,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Logomarca / imagem do ticket',
          child: Wrap(
            spacing: 20,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TicketLogoPreview(logo: printing.logo),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _changeLogo(context),
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('Alterar imagem'),
                  ),
                  TextButton(
                    onPressed: printing.logo == TicketLogo.standard
                        ? null
                        : () => settings.update(
                            () => printing.logo = TicketLogo.standard,
                          ),
                    child: const Text('Restaurar padrão'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Layouts de impressão',
          description: 'Confira os mesmos dados do ticket em cupom térmico ou A4 de contingência. Sem impressão física ou troca automática.',
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => showTicketPreview(
                  context,
                  ticket: ticketFromSession(ticketSession, settings),
                  format: PrinterFormat.ticket,
                ),
                icon: const Icon(Icons.receipt_long_outlined, size: 20),
                label: const Text('Visualizar Ticket'),
              ),
              OutlinedButton.icon(
                onPressed: () => showTicketPreview(
                  context,
                  ticket: ticketFromSession(ticketSession, settings),
                  format: PrinterFormat.a4,
                ),
                icon: const Icon(Icons.description_outlined, size: 20),
                label: const Text('Visualizar A4'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Configurar impressora',
          description: 'Impressoras e status simulados. Sem descoberta ou conexão com o Windows.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsFields(
                children: [
                  DropdownButtonFormField<String>(
                    key: const ValueKey('printer-selection'),
                    initialValue: printer.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Selecionar impressora',
                    ),
                    items: [
                      for (final option in mockPrinters)
                        DropdownMenuItem(
                          value: option.id,
                          child: Text(option.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        settings.update(() => printing.printerId = value);
                      }
                    },
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('fallback-printer'),
                    initialValue: printing.fallbackPrinterId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Impressora A4 de contingência',
                    ),
                    items: [
                      for (final option in mockPrinters.where(
                        (printer) => printer.format == PrinterFormat.a4,
                      ))
                        DropdownMenuItem(
                          value: option.id,
                          child: Text(option.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        settings.update(
                          () => printing.fallbackPrinterId = value,
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 28,
                runSpacing: 12,
                children: [
                  _summary('Status', '${printer.status.label} (simulado)'),
                  _summary(
                    'Tipo',
                    '${printer.format.label} • ${printer.connectionType}',
                  ),
                  _summary('Conexão', printer.connection),
                ],
              ),
              const Divider(height: 28),
              Text(
                'Papel • ${printer.name}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Valores padrão simulados da impressora selecionada.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              SettingsFields(
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('paper-size-${printer.id}'),
                    initialValue: paper.size,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tamanho'),
                    items: [
                      for (final size in printer.sizes)
                        DropdownMenuItem(value: size, child: Text(size)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        settings.update(() => paper.size = value);
                      }
                    },
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('paper-source-${printer.id}'),
                    initialValue: paper.source,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Origem'),
                    items: [
                      for (final source in printer.sources)
                        DropdownMenuItem(value: source, child: Text(source)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        settings.update(() => paper.source = value);
                      }
                    },
                  ),
                  DropdownButtonFormField<PaperOrientation>(
                    key: ValueKey('paper-orientation-${printer.id}'),
                    initialValue: paper.orientation,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Orientação'),
                    items: [
                      for (final orientation in PaperOrientation.values)
                        DropdownMenuItem(
                          value: orientation,
                          child: Text(orientation.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        settings.update(() => paper.orientation = value);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Emite ticket',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsFields(
                children: [
                  SettingsToggle(
                    label: 'Entrada',
                    value: printing.emitEntry,
                    onChanged: (value) =>
                        settings.update(() => printing.emitEntry = value),
                  ),
                  SettingsToggle(
                    label: 'Saída',
                    value: printing.emitExit,
                    onChanged: (value) =>
                        settings.update(() => printing.emitExit = value),
                  ),
                  TextFormField(
                    key: const ValueKey('ticket-copies'),
                    initialValue: '${printing.copies}',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Número de cópias',
                      helperText: 'De 1 a 10 cópias.',
                    ),
                    validator: (value) {
                      final copies = int.tryParse(value ?? '');
                      return copies == null || copies < 1 || copies > 10
                          ? 'Informe de 1 a 10 cópias.'
                          : null;
                    },
                    onChanged: (value) => settings.update(
                      () => printing.copies = int.tryParse(value) ?? 0,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsToggle(
                        label: 'Ticket Windows',
                        value: printing.windowsTicket,
                        onChanged: (value) => settings.update(
                          () => printing.windowsTicket = value,
                        ),
                      ),
                      const Text(
                        'Opção reservada; comportamento a definir.',
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Cabeçalho e rodapé do ticket',
          description: 'Até 3 linhas de texto em cada campo, compartilhadas por Ticket e A4.',
          child: SettingsFields(
            children: [
              TicketTextField(
                label: 'Texto do Cabeçalho',
                fieldKey: 'ticket-header',
                initialValue: printing.header,
                onChanged: (value) =>
                    settings.update(() => printing.header = value),
              ),
              TicketTextField(
                label: 'Texto do Rodapé',
                fieldKey: 'ticket-footer',
                initialValue: printing.footer,
                onChanged: (value) =>
                    settings.update(() => printing.footer = value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summary(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      const SizedBox(height: 3),
      SelectableText(
        value,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ],
  );
}
