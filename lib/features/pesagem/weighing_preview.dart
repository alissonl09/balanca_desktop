/// Estado de apresentação. Não representa um contrato da Libra-API.
class WeighingSummary {
  const WeighingSummary({
    this.first = 0,
    this.second = 0,
    this.net = 0,
    this.dry = 0,
    this.firstWeighedAt,
    this.secondWeighedAt,
  });

  final double first, second, net, dry;
  final DateTime? firstWeighedAt, secondWeighedAt;

  /// Heurística provisória apenas para identificar a confirmação na interface.
  /// A classificação definitiva será fornecida pela regra real da operação.
  bool get isClosing => [first, second, net, dry].any((weight) => weight > 0);

  Map<String, double> get values => {
    'Pesagem 1': first,
    'Pesagem 2': second,
    'Peso Líquido': net,
    'Peso Seco': dry,
  };
}

class WeighingPreview {
  WeighingPreview({
    required this.plate,
    required this.trailer,
    required Map<String, String> operation,
    required this.currentWeight,
    required this.summary,
    this.manualOperator,
    this.capturedAt,
    this.manualJustification,
  }) : operation = Map.unmodifiable(operation);

  final String plate, trailer;
  final Map<String, String> operation;
  final double currentWeight;
  final WeighingSummary summary;
  final String? manualOperator;
  final String? manualJustification;
  final DateTime? capturedAt;
  bool get isManual => manualOperator != null;
}

/// Auditoria local de cada leitura manual confirmada, sem senha ou tolerância.
/// Mantém a justificativa da primeira leitura mesmo após confirmar a segunda.
class ManualReadingRecord {
  ManualReadingRecord.fromPreview(WeighingPreview preview)
    : plate = preview.plate,
      weight = preview.currentWeight,
      authorizer = preview.manualOperator ?? '',
      justification = preview.manualJustification?.trim() ?? '',
      readAt = preview.capturedAt {
    if (!preview.isManual || justification.isEmpty || readAt == null) {
      throw ArgumentError(
        'Leitura manual exige autorização, justificativa e instante.',
      );
    }
  }
  final String plate, authorizer, justification;
  final double weight;
  final DateTime? readAt;
}

String formatWeight(double weight) => weight == weight.roundToDouble()
    ? weight.toStringAsFixed(0)
    : weight
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceAll('.', ',');
