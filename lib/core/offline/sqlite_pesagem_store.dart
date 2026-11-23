import 'dart:convert';

import '../database/database_manager.dart';
import 'local_pesagem_store.dart';
import 'offline_models.dart';

/// Preserva o agregado atual; pesagem e outbox são gravados na mesma transação.
class SqlitePesagemStore implements LocalPesagemStore {
  const SqlitePesagemStore(this.database);
  final DatabaseManager database;
  @override
  Future<void> save(LocalWeighing w) => database.saveWeighing({
    'id': w.idLocal,
    'pre_ticket_id': w.preTicketId,
    'plate': w.plate,
    'created_at': w.createdAt.toUtc().toIso8601String(),
    'phase': w.phase.name,
    'first_reading': w.firstReading,
    'second_reading': w.secondReading,
    'events': w.events
        .map(
          (e) => {
            'id': e.idLocal,
            'weighing_id': e.idPesagemLocal,
            'type': e.tipoEvento.name,
            'payload': jsonEncode(e.payload),
            'created_at': e.dataHoraCriacao.toUtc().toIso8601String(),
            'sequence': e.ordem,
            'depends_on': e.dependeDe,
            'status': e.status.name,
            'attempts': e.tentativas,
            'last_error': e.ultimoErro,
            'remote_id': e.idRemoto,
          },
        )
        .toList(),
  });
  @override
  Future<List<LocalWeighing>> loadAll() async =>
      (await database.loadWeighings())
          .map(
            (w) => LocalWeighing(
              idLocal: w['id'] as String,
              preTicketId: w['pre_ticket_id'] as String,
              plate: w['plate'] as String,
              createdAt: DateTime.parse(w['created_at'] as String),
              phase: WeighingPhase.values.byName(w['phase'] as String),
              firstReading: (w['first_reading'] as num?)?.toDouble(),
              secondReading: (w['second_reading'] as num?)?.toDouble(),
              events: (w['events'] as List).map(
                (dynamic e) => SyncEvent(
                  idLocal: e['id'] as String,
                  idPesagemLocal: e['weighing_id'] as String,
                  tipoEvento: SyncEventType.values.byName(e['type'] as String),
                  payload: (jsonDecode(e['payload'] as String) as Map)
                      .cast<String, Object?>(),
                  dataHoraCriacao: DateTime.parse(e['created_at'] as String),
                  ordem: e['sequence'] as int,
                  dependeDe: e['depends_on'] as String?,
                  status: SyncEventStatus.values.byName(e['status'] as String),
                  tentativas: e['attempts'] as int,
                  ultimoErro: e['last_error'] as String?,
                  idRemoto: e['remote_id'] as String?,
                ),
              ),
            ),
          )
          .toList();
}
