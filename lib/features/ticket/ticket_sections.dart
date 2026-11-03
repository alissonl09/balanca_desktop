import 'package:flutter/material.dart';

import '../../core/widgets/visual_components.dart';
import 'ticket_pesagem.dart';
import 'ticket_traceability.dart';

String ticketNumberFormat(double value) {
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  final parts = text.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}.',
  );
  return parts.length == 1 ? whole : '$whole,${parts.last}';
}

String ticketWeight(double value) => '${ticketNumberFormat(value)} Kg';
String ticketDate(DateTime value) {
  final date = value.toLocal();
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String ticketTime(DateTime value) {
  final date = value.toLocal();
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
}

List<(String, String)> ticketOperationRows(TicketPesagem ticket) {
  final rows = <(String, String)>[];
  void add(String label, String? value) {
    if (value != null && value.trim().isNotEmpty) rows.add((label, value));
  }

  add(
    'Nº Nota(s) / Documento(s)',
    ticket.documents.isEmpty ? null : ticket.documents.join('\n'),
  );
  add('Tipo do Documento', ticket.documentType);
  add('Tipo da Operação', ticket.operationType);
  add('Referência / XFER / OC', ticket.operationReference);
  add('Produto / Item', ticket.product);
  add('Embalagem / Acondicionamento', ticket.packaging);
  add(
    'Quantidade',
    ticket.quantity == null ? null : ticketNumberFormat(ticket.quantity!),
  );
  add('Remetente', ticket.sender);
  add('Destinatário', ticket.recipient);
  add('Placa Cavalo', ticket.tractorPlate);
  add('Placa Carreta', ticket.trailerPlate);
  add('Transportador', ticket.carrier);
  add('Motorista', ticket.driver);
  add(
    'Cidade / UF',
    [
      ticket.city,
      ticket.uf,
    ].whereType<String>().where((text) => text.isNotEmpty).join(' / '),
  );
  add('Emissor(es)', ticket.issuers.isEmpty ? null : ticket.issuers.join('\n'));
  add('Depósito', ticket.depot);
  add(
    'Peso N.F.',
    ticket.invoiceWeight == null ? null : ticketWeight(ticket.invoiceWeight!),
  );
  return rows;
}

class TicketHeader extends StatelessWidget {
  const TicketHeader({super.key, required this.ticket, this.large = false});
  final TicketPesagem ticket;
  final bool large;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ticket.branding.logo == TicketLogoKind.standard)
            AppAsset('logo-topo', size: large ? 90 : 62, color: Colors.black)
          else
            Icon(
              Icons.local_shipping_outlined,
              size: large ? 90 : 62,
              color: Colors.black,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Ticket Nº',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  ticket.ticketNumber ?? '—',
                  key: const ValueKey('ticket-number'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: large ? 28 : 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  ticket.isClosing ? 'FECHAMENTO DE PESO' : 'ABERTURA DE PESO',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (ticket.branding.companyName case final company?) ...[
        const SizedBox(height: 8),
        Text(
          company,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: large ? 18 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
      if (ticket.branding.unitLabel case final unit?) ...[
        const SizedBox(height: 6),
        Text('Unidade $unit', textAlign: TextAlign.center),
      ],
      if (ticket.branding.headerLines.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          ticket.branding.headerLines.join('\n'),
          textAlign: TextAlign.center,
        ),
      ],
      const Divider(color: Colors.black, height: 24),
    ],
  );
}

class TicketFieldValue extends StatelessWidget {
  const TicketFieldValue(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(value, softWrap: true),
      ],
    ),
  );
}

class TicketWeighingSection extends StatelessWidget {
  const TicketWeighingSection({
    super.key,
    required this.ticket,
    this.large = false,
  });
  final TicketPesagem ticket;
  final bool large;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(color: Colors.black, height: 24),
      const Text(
        'Dados da Pesagem',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      if (ticket.captureType == TicketCaptureType.manual)
        Container(
          key: const ValueKey('ticket-manual-notice'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pesagem Manual',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (ticket.manualAuthorizer case final authorizer?) ...[
                const SizedBox(height: 4),
                Text('Autorizado por: $authorizer'),
              ],
              if (ticket.manualJustification case final reason?) ...[
                const SizedBox(height: 4),
                Text('Justificativa: $reason'),
              ],
            ],
          ),
        )
      else
        const Text(
          'BALANÇA / AUTOMÁTICA',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _column(
              'ENTRADA',
              ticket.firstWeighedAt,
              ticket.firstWeight,
              'Peso Inicial',
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _column(
              'SAÍDA',
              ticket.secondWeighedAt,
              ticket.secondWeight,
              'Peso Final',
            ),
          ),
        ],
      ),
      if (ticket.netWeight case final weight?) ...[
        const Divider(color: Colors.black, height: 24),
        Container(
          key: const ValueKey('ticket-net-weight'),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Peso Líquido',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                ticketWeight(weight),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: large ? 30 : 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
      if (ticket.dryWeight case final weight?)
        TicketFieldValue('Peso Seco', ticketWeight(weight)),
    ],
  );

  Widget _column(
    String label,
    DateTime? at,
    double? weight,
    String weightLabel,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      if (at != null) ...[
        TicketFieldValue('Data', ticketDate(at)),
        TicketFieldValue('Hora', ticketTime(at)),
      ],
      if (weight != null)
        TicketFieldValue(weightLabel, ticketWeight(weight))
      else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('—'),
        ),
    ],
  );
}

class TicketFooter extends StatelessWidget {
  const TicketFooter({super.key, required this.ticket});
  final TicketPesagem ticket;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(color: Colors.black, height: 24),
      if (ticket.observation case final text?)
        TicketFieldValue('Observações', text),
      if (ticket.operatorName case final operator?)
        TicketFieldValue('Operador', operator),
      TicketFieldValue(
        'Emissão do comprovante',
        '${ticketDate(ticket.issuedAt)} ${ticketTime(ticket.issuedAt)}',
      ),
      if (ticket.branding.footerLines.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          ticket.branding.footerLines.join('\n'),
          textAlign: TextAlign.center,
        ),
      ],
      if (ticket.traceabilityId case final code?) ...[
        const SizedBox(height: 16),
        TicketBarcode(value: code),
      ],
    ],
  );
}

class TicketBarcode extends StatelessWidget {
  const TicketBarcode({super.key, required this.value});
  final String value;
  @override
  Widget build(BuildContext context) {
    List<bool>? modules;
    try {
      modules = encodeCode39(value);
    } on FormatException {
      modules = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (modules != null)
          Semantics(
            label: 'Código de barras: $value',
            child: SizedBox(
              height: 56,
              child: CustomPaint(
                key: const ValueKey('ticket-barcode'),
                painter: _BarcodePainter(modules),
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.modules);
  final List<bool> modules;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    final unit = size.width / modules.length;
    for (var index = 0; index < modules.length; index++) {
      if (modules[index]) {
        canvas.drawRect(
          Rect.fromLTWH(index * unit, 0, unit, size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter oldDelegate) =>
      oldDelegate.modules != modules;
}
