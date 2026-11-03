import '../../core/offline/offline_models.dart';
import '../../core/offline/pre_ticket_source.dart';
import 'operation_preview.dart';
import 'weighing_preview.dart';

enum OperationMode { manual, integrada }

/// Resultado local tipado de apresentação, sem presumir DTO ou endpoint novo.
class OperationLookup {
  OperationLookup({
    required Map<String, String> values,
    required List<String> trailers,
    this.summary = const WeighingSummary(),
    this.phase = WeighingPhase.nova,
    this.origin = PreTicketOrigin.local,
  }) : values = Map.unmodifiable(values),
       trailers = List.unmodifiable(trailers);
  final Map<String, String> values;
  final List<String> trailers;
  final WeighingSummary summary;
  final WeighingPhase phase;
  final PreTicketOrigin origin;
}

abstract interface class OperationLookupService {
  Future<OperationLookup?> lookup(String plate, StationConnection connection);
}

/// Fixtures já existentes, explicitamente disponíveis localmente nesta demo.
/// Placa desconhecida retorna null, nunca cria dados de operação fictícios.
class DemoOperationLookupService implements OperationLookupService {
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
