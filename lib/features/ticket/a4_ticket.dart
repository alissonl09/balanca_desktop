import 'package:flutter/material.dart';

import 'ticket_pesagem.dart';
import 'ticket_sections.dart';

/// Mesmos dados e seções do cupom, reorganizados em uma folha convencional.
class A4Ticket extends StatelessWidget {
  const A4Ticket({super.key, required this.ticket});
  final TicketPesagem ticket;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('a4-ticket-paper'),
    color: Colors.white,
    constraints: const BoxConstraints(minHeight: 1018),
    padding: const EdgeInsets.all(40),
    child: DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'Arial',
        fontSize: 14,
        height: 1.35,
        color: Colors.black,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TicketHeader(ticket: ticket, large: true),
          const Text(
            'Dados da Operação',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 24,
              runSpacing: 4,
              children: [
                for (final (label, value) in ticketOperationRows(ticket))
                  SizedBox(
                    width: (constraints.maxWidth - 24) / 2,
                    child: TicketFieldValue(label, value),
                  ),
              ],
            ),
          ),
          TicketWeighingSection(ticket: ticket, large: true),
          TicketFooter(ticket: ticket),
        ],
      ),
    ),
  );
}
