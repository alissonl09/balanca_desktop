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
}) {
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
    ticketNumber: session.ticketNumber,
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
    invoiceWeight: _number(operation['Peso N.F. (Kg)']),
    firstWeight: first,
    secondWeight: second,
    firstWeighedAt: firstAt,
    secondWeighedAt: secondAt,
    // Zero inicial sem cálculo e sem segunda pesagem não é um líquido apurado.
    netWeight:
        summary.net > 0 || summary.second > 0 || summary.secondWeighedAt != null
        ? summary.net
        : null,
    dryWeight: summary.dry > 0 ? summary.dry : null,
    observation: _text(operation['Observação']),
    operatorName: _text(operation['Operador']),
    issuedAt: issuedAt ?? DateTime.now(),
    captureType: manual
        ? TicketCaptureType.manual
        : TicketCaptureType.automatic,
    manualAuthorizer: manual ? matchingCapture?.manualOperator : null,
    manualJustification: manual ? matchingCapture?.manualJustification : null,
    traceabilityId: identifierFactory(session.ticketNumber),
    branding: TicketBranding(
      logo: settings.printing.logo == TicketLogo.demonstration
          ? TicketLogoKind.demonstration
          : TicketLogoKind.standard,
      unitLabel: unit?.label,
      headerLines: _lines(settings.printing.header),
      footerLines: _lines(settings.printing.footer),
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
double? _number(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  var normalized = value.trim().replaceAll(' ', '');
  if (normalized.contains(',')) {
    normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(normalized)) {
    normalized = normalized.replaceAll('.', '');
  }
  final number = double.tryParse(normalized);
  return number != null && number.isFinite ? number : null;
}
