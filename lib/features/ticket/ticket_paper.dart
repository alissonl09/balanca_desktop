import 'package:flutter/widgets.dart';

import 'a4_ticket.dart';
import 'print_settings.dart';
import 'thermal_ticket.dart';
import 'ticket_pesagem.dart';

class TicketPaper extends StatelessWidget {
  const TicketPaper({
    super.key,
    required this.ticket,
    required this.format,
    this.standardLogo,
    this.fillSheet = true,
  });

  final TicketPesagem ticket;
  final PrinterFormat format;
  final Widget? standardLogo;
  final bool fillSheet;

  static double widthFor(PrinterFormat format) =>
      format == PrinterFormat.ticket ? 340 : 720;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widthFor(format),
    child: switch (format) {
      PrinterFormat.ticket => ThermalTicket(
        ticket: ticket,
        standardLogo: standardLogo,
      ),
      PrinterFormat.a4 => A4Ticket(
        ticket: ticket,
        standardLogo: standardLogo,
        fillSheet: fillSheet,
      ),
    },
  );
}
