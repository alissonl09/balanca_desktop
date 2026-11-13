import '../../core/offline/offline_models.dart';
import '../../core/libra/pre_ticket_dto.dart';
import '../../core/offline/pre_ticket_source.dart';
import 'operation_preview.dart';
import 'weighing_preview.dart';

enum OperationMode { manual, integrada }

/// Resultado de apresentação, com documentos remotos quando disponíveis.
class OperationLookup {
  OperationLookup({
    required Map<String, String> values,
    required List<String> trailers,
    this.summary = const WeighingSummary(),
    this.phase = WeighingPhase.nova,
    this.origin = PreTicketOrigin.local,
    List<PreTicketDto> preTickets = const [],
  }) : values = Map.unmodifiable(values),
       trailers = List.unmodifiable(trailers),
       preTickets = List.unmodifiable(preTickets);
  final Map<String, String> values;
  final List<String> trailers;
  final WeighingSummary summary;
  final WeighingPhase phase;
  final PreTicketOrigin origin;
  final List<PreTicketDto> preTickets;
}

abstract interface class OperationLookupService {
  Future<OperationLookup?> lookup(String plate, StationConnection connection);
}

/// Fixtures já existentes, explicitamente disponíveis localmente nesta demo.
/// Placa desconhecida retorna null, nunca cria dados de operação fictícios.
class DemoOperationLookupService implements OperationLookupService {
  const DemoOperationLookupService();
  @override
  Future<OperationLookup?> lookup(
    String plate,
    StationConnection connection,
  ) async {
    final trailers = operationPreview
        .where((o) => o.plate == plate)
        .map((o) => o.trailer)
        .toSet()
        .toList();
    if (trailers.isEmpty) return null;
    return OperationLookup(
      values: operationDetailsPreview,
      trailers: trailers,
      summary: operationSummariesPreview[plate] ?? const WeighingSummary(),
      phase: operationSummariesPreview.containsKey(plate)
          ? WeighingPhase.aberta
          : WeighingPhase.nova,
    );
  }
}
