import '../../core/offline/offline_models.dart';
import '../ticket/ticket_session.dart';
import 'weighing_preview.dart';

/// Edição de metadados apenas; sem captura, transição física, ticket ou HTTP.
abstract interface class PesagemEditService {
  Future<void> save(TicketSession session, Map<String, String> values);
}

class MemoryPesagemEditService implements PesagemEditService {
  @override
  Future<void> save(TicketSession session, Map<String, String> values) async {
    if (session.phase != WeighingPhase.aberta || session.current == null) {
      throw StateError('Somente uma pesagem aberta permite editar dados.');
    }
    for (final official in session.officialOperation.entries) {
      if (values[official.key] != official.value) {
        throw StateError(
          'Dados oficiais da integração não podem ser alterados.',
        );
      }
    }
    final current = session.current!;
    if ((values['Operador'] ?? '') != (current.operation['Operador'] ?? '')) {
      throw StateError('Operador é definido pela identidade do sistema.');
    }
    // Copia somente a operação. Summary, captura e fase mantêm suas identidades.
    session.current = WeighingPreview(
      plate: current.plate,
      trailer: current.trailer,
      operation: values,
      currentWeight: current.currentWeight,
      summary: current.summary,
      manualOperator: current.manualOperator,
      capturedAt: current.capturedAt,
      manualJustification: current.manualJustification,
    );
    session.draftOperation = Map.of(values);
  }
}
