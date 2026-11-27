/// Dados do ticket compartilhados pela prévia e pela impressão.
enum TicketCaptureType { automatic, manual }

enum TicketLogoKind { standard, demonstration }

class TicketBranding {
  static const defaultCompanyName =
      'Cooperativa Regional de Cafeicultores em Guaxupé Ltda - COOXUPÉ';

  TicketBranding({
    this.logo = TicketLogoKind.standard,
    this.companyName = defaultCompanyName,
    this.unitLabel,
    List<String> headerLines = const [],
    List<String> footerLines = const [],
  }) : headerLines = List.unmodifiable(headerLines.take(3)),
       footerLines = List.unmodifiable(footerLines.take(3));
  final TicketLogoKind logo;
  final String? companyName, unitLabel;
  final List<String> headerLines, footerLines;

  factory TicketBranding.fromJson(Map<String, dynamic> json) => TicketBranding(
    logo: TicketLogoKind.values.byName(json['logo'] as String),
    companyName: json['companyName'] as String?,
    unitLabel: json['unitLabel'] as String?,
    headerLines: List<String>.from(json['headerLines'] as List),
    footerLines: List<String>.from(json['footerLines'] as List),
  );

  Map<String, Object?> toJson() => {
    'logo': logo.name,
    'companyName': companyName,
    'unitLabel': unitLabel,
    'headerLines': headerLines,
    'footerLines': footerLines,
  };
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

  String? get printableNumber {
    final value = ticketNumber?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  factory TicketPesagem.fromJson(Map<String, dynamic> json) {
    DateTime? readDate(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return TicketPesagem(
      ticketNumber: json['ticketNumber'] as String?,
      documents: List<String>.from(json['documents'] as List),
      documentType: json['documentType'] as String?,
      operationType: json['operationType'] as String?,
      operationReference: json['operationReference'] as String?,
      product: json['product'] as String?,
      packaging: json['packaging'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble(),
      sender: json['sender'] as String?,
      recipient: json['recipient'] as String?,
      tractorPlate: json['tractorPlate'] as String?,
      trailerPlate: json['trailerPlate'] as String?,
      carrier: json['carrier'] as String?,
      driver: json['driver'] as String?,
      city: json['city'] as String?,
      uf: json['uf'] as String?,
      issuers: List<String>.from(json['issuers'] as List),
      depot: json['depot'] as String?,
      invoiceWeight: (json['invoiceWeight'] as num?)?.toDouble(),
      firstWeighedAt: readDate('firstWeighedAt'),
      firstWeight: (json['firstWeight'] as num?)?.toDouble(),
      secondWeighedAt: readDate('secondWeighedAt'),
      secondWeight: (json['secondWeight'] as num?)?.toDouble(),
      netWeight: (json['netWeight'] as num?)?.toDouble(),
      dryWeight: (json['dryWeight'] as num?)?.toDouble(),
      observation: json['observation'] as String?,
      operatorName: json['operatorName'] as String?,
      issuedAt: readDate('issuedAt')!,
      captureType: TicketCaptureType.values.byName(
        json['captureType'] as String,
      ),
      manualAuthorizer: json['manualAuthorizer'] as String?,
      manualJustification: json['manualJustification'] as String?,
      traceabilityId: json['traceabilityId'] as String?,
      branding: TicketBranding.fromJson(
        json['branding'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'ticketNumber': ticketNumber,
    'documents': documents,
    'documentType': documentType,
    'operationType': operationType,
    'operationReference': operationReference,
    'product': product,
    'packaging': packaging,
    'quantity': quantity,
    'sender': sender,
    'recipient': recipient,
    'tractorPlate': tractorPlate,
    'trailerPlate': trailerPlate,
    'carrier': carrier,
    'driver': driver,
    'city': city,
    'uf': uf,
    'issuers': issuers,
    'depot': depot,
    'invoiceWeight': invoiceWeight,
    'firstWeighedAt': firstWeighedAt?.toIso8601String(),
    'firstWeight': firstWeight,
    'secondWeighedAt': secondWeighedAt?.toIso8601String(),
    'secondWeight': secondWeight,
    'netWeight': netWeight,
    'dryWeight': dryWeight,
    'observation': observation,
    'operatorName': operatorName,
    'issuedAt': issuedAt.toIso8601String(),
    'captureType': captureType.name,
    'manualAuthorizer': manualAuthorizer,
    'manualJustification': manualJustification,
    'traceabilityId': traceabilityId,
    'branding': branding.toJson(),
  };

  /// Reflete a existência de uma segunda captura, sem criar peso de saída.
  bool get isClosing => secondWeight != null;
}
