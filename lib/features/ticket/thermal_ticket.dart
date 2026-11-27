import 'package:flutter/material.dart';

import 'ticket_pesagem.dart';
import 'ticket_sections.dart';

/// Cupom estreito, altura livre e texto integral, sem truncar informações.
class ThermalTicket extends StatelessWidget {
  const ThermalTicket({super.key, required this.ticket, this.standardLogo});
  final TicketPesagem ticket;
  final Widget? standardLogo;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('thermal-ticket-paper'),
    color: Colors.white,
    padding: const EdgeInsets.all(20),
    child: DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'Arial',
        fontSize: 13,
        height: 1.3,
        color: Colors.black,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TicketHeader(ticket: ticket, standardLogo: standardLogo),
          TicketOperationSection(ticket: ticket),
          TicketWeighingSection(ticket: ticket),
          TicketFooter(ticket: ticket),
        ],
      ),
    ),
  );
}
