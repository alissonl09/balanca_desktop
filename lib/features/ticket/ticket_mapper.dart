import '../configuracoes/settings_mock_data.dart';
import '../configuracoes/settings_models.dart';
import '../pesagem/weighing_preview.dart';
import 'ticket_pesagem.dart';
import 'ticket_session.dart';
import 'ticket_traceability.dart';

/// Adaptação da interface atual. Não calcula pesos ou aplica regras de pesagem.
TicketPesagem ticketFromSession(
  TicketSession session,
  SettingsState settings, {
  DateTime? issuedAt,
  TicketIdentifierFactory identifierFactory = previewTicketIdentifier,
  PrintSettings? savedPrinting,
}) {
  final printing = savedPrinting ?? settings.printing;
  final number = savedPrinting == null
      ? session.ticketNumber
      : session.officialTicketNumber;
  final current = session.current;
  final operation = current?.operation ?? const <String, String>{};
  final summary = current?.summary ?? const WeighingSummary();
  final confirmed = session.confirmed;
  final matchingCapture =
      confirmed != null &&
          current != null &&
          confirmed.plate == current.plate &&
          confirmed.trailer == current.trailer
      ? confirmed
      : null;
  double? first = summary.first > 0 || summary.firstWeighedAt != null
      ? summary.first
      : null;
  double? second = summary.second > 0 || summary.secondWeighedAt != null
      ? summary.second
      : null;
  DateTime? firstAt = summary.firstWeighedAt,
      secondAt = summary.secondWeighedAt;
  if (matchingCapture?.capturedAt != null &&
      matchingCapture!.capturedAt != firstAt &&
      matchingCapture.capturedAt != secondAt) {
    if (first == null) {
      first = matchingCapture.currentWeight;
      firstAt = matchingCapture.capturedAt;
    } else if (second == null) {
      second = matchingCapture.currentWeight;
      secondAt = matchingCapture.capturedAt;
    }
  }
  final manual = matchingCapture?.isManual ?? false;
  final unit = mockUnits
      .where((unit) => unit.code == settings.unitCode)
      .firstOrNull;
  return TicketPesagem(
    ticketNumber: number,
    documents: _multiple(operation['Nº Nota(s) / Documento(s)']),
    documentType: _text(operation['Tipo do documento']),
    // Os campos sem fonte definida são deliberadamente deixados nulos.
    packaging: _text(operation['Embalagem']),
    tractorPlate: _text(current?.plate),
    trailerPlate: _text(current?.trailer),
    carrier: _text(operation['Transportador']),
    driver: _text(operation['Motorista']),
    issuers: _multiple(operation['Emissor(es)']),
    depot: _text(operation['Depósito']),
    invoiceWeight: parseInvoiceWeight(
      operation[invoiceWeightField],
      decimalPoint: session.invoiceWeightUsesDecimalPoint,
    ),
    firstWeight: first,
    secondWeight: second,
    firstWeighedAt: firstAt,
    secondWeighedAt: secondAt,
    netWeight: summary.netWeight,
    observation: _text(operation['Observação']),
    operatorName: _text(operation['Operador']),
    issuedAt: issuedAt ?? DateTime.now(),
    captureType: manual
        ? TicketCaptureType.manual
        : TicketCaptureType.automatic,
    manualAuthorizer: manual ? matchingCapture?.manualOperator : null,
    manualJustification: manual ? matchingCapture?.manualJustification : null,
    traceabilityId: identifierFactory(number),
    branding: TicketBranding(
      logo: printing.logo == TicketLogo.demonstration
          ? TicketLogoKind.demonstration
          : TicketLogoKind.standard,
      companyName:
          _text(printing.companyName) ?? TicketBranding.defaultCompanyName,
      unitLabel: unit?.label,
      headerLines: _lines(printing.header),
      footerLines: _lines(printing.footer),
    ),
  );
}

String? _text(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
List<String> _multiple(String? value) => value == null
    ? []
    : value
          .split(RegExp(r'[;\n]+'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
List<String> _lines(String value) => value.isEmpty
    ? []
    : value
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n')
          .take(3)
          .toList();
