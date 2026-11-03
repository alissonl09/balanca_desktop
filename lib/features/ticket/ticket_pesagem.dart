/// Modelo reutilizável pela impressão futura, sem dependência de Flutter.
enum TicketCaptureType { automatic, manual }

enum TicketLogoKind { standard, demonstration }

class TicketBranding {
  TicketBranding({
    this.logo = TicketLogoKind.standard,
    this.companyName,
    this.unitLabel,
    List<String> headerLines = const [],
    List<String> footerLines = const [],
  }) : headerLines = List.unmodifiable(headerLines.take(3)),
       footerLines = List.unmodifiable(footerLines.take(3));
  final TicketLogoKind logo;
  final String? companyName, unitLabel;
  final List<String> headerLines, footerLines;
}

class TicketPesagem {
  TicketPesagem({
    this.ticketNumber,
    List<String> documents = const [],
    this.documentType,
    this.operationType,
    this.operationReference,
    this.product,
    this.packaging,
    this.quantity,
    this.sender,
    this.recipient,
    this.tractorPlate,
    this.trailerPlate,
    this.carrier,
    this.driver,
    this.city,
    this.uf,
    List<String> issuers = const [],
    this.depot,
    this.invoiceWeight,
    this.firstWeighedAt,
    this.firstWeight,
    this.secondWeighedAt,
    this.secondWeight,
    this.netWeight,
    this.dryWeight,
    this.observation,
    this.operatorName,
    required this.issuedAt,
    required this.captureType,
    this.manualAuthorizer,
    this.manualJustification,
    this.traceabilityId,
    required this.branding,
  }) : documents = List.unmodifiable(documents),
       issuers = List.unmodifiable(issuers);

  final String? ticketNumber,
      documentType,
      operationType,
      operationReference,
      product,
      packaging,
      sender,
      recipient,
      tractorPlate,
      trailerPlate,
      carrier,
      driver,
      city,
      uf,
      depot,
      observation,
      operatorName,
      manualAuthorizer,
      manualJustification,
      traceabilityId;
  final List<String> documents, issuers;
  final double? quantity,
      invoiceWeight,
      firstWeight,
      secondWeight,
      netWeight,
      dryWeight;
  final DateTime? firstWeighedAt, secondWeighedAt;
  final DateTime issuedAt;
  final TicketCaptureType captureType;
  final TicketBranding branding;

  /// Reflete a existência de uma segunda captura, sem criar peso de saída.
  bool get isClosing => secondWeight != null;
}
