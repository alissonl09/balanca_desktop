import 'package:flutter/material.dart';

import 'ticket_pesagem.dart';
import 'ticket_sections.dart';

/// Mesmos dados e seções do cupom, reorganizados em uma folha convencional.
class A4Ticket extends StatelessWidget {
  const A4Ticket({
    super.key,
    required this.ticket,
    this.standardLogo,
    this.fillSheet = true,
  });
  final TicketPesagem ticket;
  final Widget? standardLogo;
  final bool fillSheet;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('a4-ticket-paper'),
    color: Colors.white,
    constraints: fillSheet ? const BoxConstraints(minHeight: 1018) : null,
    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
          TicketHeader(ticket: ticket, large: true, standardLogo: standardLogo),
          TicketOperationSection(ticket: ticket, large: true),
          TicketWeighingSection(ticket: ticket, large: true),
          TicketFooter(ticket: ticket),
        ],
      ),
    ),
  );
}
