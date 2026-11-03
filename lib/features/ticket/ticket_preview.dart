import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../configuracoes/settings_models.dart';
import 'a4_ticket.dart';
import 'thermal_ticket.dart';
import 'ticket_mock_data.dart';
import 'ticket_pesagem.dart';

Future<void> showTicketPreview(
  BuildContext context, {
  required TicketPesagem ticket,
  required PrinterFormat format,
}) => showDialog<void>(
  context: context,
  builder: (_) => _TicketPreview(ticket: ticket, initialFormat: format),
);

class _TicketPreview extends StatefulWidget {
  const _TicketPreview({required this.ticket, required this.initialFormat});
  final TicketPesagem ticket;
  final PrinterFormat initialFormat;
  @override
  State<_TicketPreview> createState() => _TicketPreviewState();
}

class _TicketPreviewState extends State<_TicketPreview> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  late PrinterFormat _format = widget.initialFormat;
  late final _examples = ticketPreviewExamples(
    widget.ticket.branding,
    widget.ticket.issuedAt,
  );
  int _source = 0;
  TicketPesagem get _ticket =>
      _source == 0 ? widget.ticket : _examples[_source - 1];

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('print-layout-preview'),
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ticket de Pesagem',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Fechar prévia',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 620
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<PrinterFormat>(
                        key: const ValueKey('ticket-preview-format'),
                        initialValue: _format,
                        decoration: const InputDecoration(labelText: 'Formato'),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: PrinterFormat.ticket,
                            child: Text('Ticket térmico'),
                          ),
                          DropdownMenuItem(
                            value: PrinterFormat.a4,
                            child: Text('A4'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _format = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<int>(
                        key: const ValueKey('ticket-preview-source'),
                        initialValue: _source,
                        decoration: const InputDecoration(
                          labelText: 'Dados da prévia',
                        ),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('Estado atual da aplicação'),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Text('Exemplo simulado • Abertura'),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text('Exemplo simulado • Fechamento'),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text('Exemplo simulado • Manual'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _source = value);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              _source == 0
                  ? 'Prévia do estado local da aplicação • sem envio à impressora.'
                  : 'EXEMPLO SIMULADO • somente demonstração de layout.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
          Flexible(
            child: ColoredBox(
              color: const Color(0xffe5e7e7),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final paperWidth = _format == PrinterFormat.ticket
                      ? 340.0
                      : 720.0;
                  return Scrollbar(
                    controller: _vertical,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _vertical,
                      child: Scrollbar(
                        controller: _horizontal,
                        thumbVisibility: paperWidth + 40 > constraints.maxWidth,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: math.max(
                              constraints.maxWidth,
                              paperWidth + 40,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: paperWidth,
                                  child: _format == PrinterFormat.ticket
                                      ? ThermalTicket(ticket: _ticket)
                                      : A4Ticket(ticket: _ticket),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
