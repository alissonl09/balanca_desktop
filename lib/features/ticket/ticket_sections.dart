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

List<List<(String, String)>> _ticketOperationRows(TicketPesagem ticket) {
  final rows = <List<(String, String)>>[];
  void add(String label, String? value, [(String, String?)? beside]) {
    final row = [
      for (final (label, value) in [(label, value), ?beside])
        if (value != null && value.trim().isNotEmpty) (label, value),
    ];
    if (row.isNotEmpty) rows.add(row);
  }

  add(
    'Nº Nota(s) / Documento(s)',
    ticket.documents.isEmpty ? null : ticket.documents.join('\n'),
  );
  add('Tipo do Documento', ticket.documentType);
  add('Tipo da Operação', ticket.operationType);
  add('Referência / XFER / OC', ticket.operationReference);
  add('Produto / Item', ticket.product);
  add('Embalagem / Acondicionamento', ticket.packaging, (
    'Quantidade',
    ticket.quantity == null ? null : ticketNumberFormat(ticket.quantity!),
  ));
  add('Remetente', ticket.sender);
  add('Destinatário', ticket.recipient);
  add('Placa Cavalo', ticket.tractorPlate, (
    'Placa Carreta',
    ticket.trailerPlate,
  ));
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

const _ticketRule = BorderSide(color: Colors.black, width: 0.75);
const _cellPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);

class TicketOperationSection extends StatelessWidget {
  const TicketOperationSection({
    super.key,
    required this.ticket,
    this.large = false,
  });

  final TicketPesagem ticket;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final rows = _ticketOperationRows(ticket);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dados da Operação',
          style: TextStyle(
            fontSize: large ? 17 : 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        for (final (index, row) in rows.indexed)
          Table(
            border: TableBorder(
              top: index == 0 ? _ticketRule : BorderSide.none,
              bottom: _ticketRule,
              left: _ticketRule,
              right: _ticketRule,
              verticalInside: _ticketRule,
            ),
            children: [
              TableRow(
                children: [
                  for (final (label, value) in row)
                    TicketFieldValue(label, value, padding: _cellPadding),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class TicketHeader extends StatelessWidget {
  const TicketHeader({
    super.key,
    required this.ticket,
    this.large = false,
    this.standardLogo,
  });
  final TicketPesagem ticket;
  final bool large;
  final Widget? standardLogo;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TicketPaperLogo(
            kind: ticket.branding.logo,
            size: large ? 70 : 62,
            standardLogo: standardLogo,
          ),
          const SizedBox(width: 12),
          if (ticket.branding.companyName case final company?)
            Expanded(
              child: Text(
                company,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: large ? 18 : 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Ticket Nº',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
      Text(
        ticket.printableNumber ?? '—',
        key: const ValueKey('ticket-number'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: large ? 28 : 23,
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(
        ticket.isClosing ? 'FECHAMENTO DE PESO' : 'ABERTURA DE PESO',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
      ),
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

class TicketPaperLogo extends StatelessWidget {
  const TicketPaperLogo({
    super.key,
    required this.kind,
    required this.size,
    this.standardLogo,
  });
  final TicketLogoKind kind;
  final double size;
  final Widget? standardLogo;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: kind == TicketLogoKind.standard
        ? standardLogo ?? AppAsset('logo-topo', size: size, color: Colors.black)
        : Icon(Icons.local_shipping_outlined, size: size, color: Colors.black),
  );
}

class TicketFieldValue extends StatelessWidget {
  const TicketFieldValue(
    this.label,
    this.value, {
    super.key,
    this.padding = const EdgeInsets.only(bottom: 9),
    this.labelAlign,
    this.valueAlign,
    this.valueStyle,
  });
  final String label, value;
  final EdgeInsets padding;
  final TextAlign? labelAlign, valueAlign;
  final TextStyle? valueStyle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: labelAlign,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(value, softWrap: true, textAlign: valueAlign, style: valueStyle),
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
      const SizedBox(height: 10),
      const Text(
        'Dados da Pesagem',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
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
      const SizedBox(height: 8),
      Table(
        key: const ValueKey('ticket-weighing-grid'),
        border: const TableBorder(
          top: _ticketRule,
          bottom: _ticketRule,
          left: _ticketRule,
          right: _ticketRule,
          horizontalInside: _ticketRule,
          verticalInside: _ticketRule,
        ),
        children: [
          const TableRow(
            children: [_WeighingHeading('ENTRADA'), _WeighingHeading('SAÍDA')],
          ),
          if (ticket.firstWeighedAt != null ||
              ticket.secondWeighedAt != null) ...[
            _timingRow('Data', ticketDate),
            _timingRow('Hora', ticketTime),
          ],
          TableRow(
            children: [
              _weightCell('Peso Inicial', ticket.firstWeight),
              _weightCell('Peso Final', ticket.secondWeight),
            ],
          ),
        ],
      ),
      if (ticket.netWeight case final weight?)
        Container(
          key: const ValueKey('ticket-net-weight'),
          decoration: const BoxDecoration(
            border: Border(
              left: _ticketRule,
              right: _ticketRule,
              bottom: _ticketRule,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Expanded(
                flex: 2,
                child: Text(
                  'Peso Líquido',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: FittedBox(
                  alignment: Alignment.centerRight,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    ticketWeight(weight),
                    style: TextStyle(
                      fontSize: large ? 30 : 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  TableRow _timingRow(String label, String Function(DateTime) format) =>
      TableRow(
        children: [
          for (final at in [ticket.firstWeighedAt, ticket.secondWeighedAt])
            Padding(
              padding: _cellPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      at == null ? '—' : format(at),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _weightCell(String label, double? weight) => weight == null
      ? const Padding(
          padding: _cellPadding,
          child: Text('—', textAlign: TextAlign.right),
        )
      : TicketFieldValue(
          label,
          ticketWeight(weight),
          padding: _cellPadding,
          valueAlign: TextAlign.right,
          valueStyle: TextStyle(
            fontSize: large ? 20 : 16,
            fontWeight: FontWeight.bold,
          ),
        );
}

class _WeighingHeading extends StatelessWidget {
  const _WeighingHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _cellPadding,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
    ),
  );
}

class TicketFooter extends StatelessWidget {
  const TicketFooter({super.key, required this.ticket});
  final TicketPesagem ticket;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      if (ticket.observation case final text?)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border.fromBorderSide(_ticketRule),
            ),
            child: TicketFieldValue('Observações', text, padding: _cellPadding),
          ),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ticket.operatorName case final operator?) ...[
            Expanded(child: TicketFieldValue('Operador', operator)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: TicketFieldValue(
              'Emissão do comprovante',
              '${ticketDate(ticket.issuedAt)} ${ticketTime(ticket.issuedAt)}',
              labelAlign: TextAlign.right,
              valueAlign: TextAlign.right,
            ),
          ),
        ],
      ),
      if (ticket.branding.footerLines.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          ticket.branding.footerLines.join('\n'),
          textAlign: TextAlign.center,
        ),
      ],
      if (ticket.printableNumber case final code?) ...[
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
