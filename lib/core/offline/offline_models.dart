/// Estado da estação, independente do estado físico de cada pesagem.
enum StationConnection { online, offline, sincronizando }

/// Fase física local. Uma falha de envio nunca desfaz uma captura ou fechamento.
enum WeighingPhase {
  /// Rascunho sem leitura inicial.
  nova,

  /// Primeira leitura registrada; aceita segunda leitura mesmo offline.
  aberta,

  /// Duas leituras locais; o fechamento pode ainda aguardar envio.
  fechada,

  /// Registro/cancelamento de ticket solicitado e ainda sem confirmação.
  ticketPendente,

  /// Última operação de ticket explicitamente confirmada pelo servidor.
  concluida,
}

/// Dimensão de envio, separada de [WeighingPhase].
enum WeighingSyncStatus {
  semEventos,
  pendente,
  sincronizando,
  sincronizada,
  erro,
}

/// Projeção para apresentação; erro é WeighingSyncStatus.erro, sem apagar a fase.
enum LocalWeighingState {
  /// Sem captura inicial ou evento de envio.
  nova,

  /// Primeira leitura; abertura ainda sem confirmação remota.
  abertaLocal,

  /// Abertura confirmada; aceita fechamento offline.
  abertaSincronizada,

  /// Segunda leitura local; fechamento sem confirmação remota.
  fechadaLocal,

  /// Fechamento confirmado, antes da solicitação de ticket.
  fechadaSincronizada,

  /// Registro/cancelamento de ticket aguarda confirmação.
  ticketPendente,

  /// Última solicitação de ticket explicitamente confirmada.
  concluida,
}

enum SyncEventType {
  aberturaPesagem,
  fechamentoPesagem,
  registroTicket,
  cancelamentoTicket,
}

enum SyncEventStatus { pendente, emEnvio, confirmado, erro }

/// Snapshot JSON profundamente imutável; não é um contrato HTTP da Libra.
Object? _freeze(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(
      value.map((k, v) => MapEntry(k, _freeze(v))),
    );
  }
  throw ArgumentError('O payload deve conter apenas valores JSON finitos.');
}

class SyncEvent {
  SyncEvent({
    required this.idLocal,
    required this.tipoEvento,
    required this.idPesagemLocal,
    required Map<String, Object?> payload,
    required this.dataHoraCriacao,
    required this.ordem,
    this.dependeDe,
    this.status = SyncEventStatus.pendente,
    this.tentativas = 0,
    this.ultimoErro,
    this.idRemoto,
  }) : payload = _freeze(payload)! as Map<String, Object?>;

  final String idLocal, idPesagemLocal;
  final SyncEventType tipoEvento;
  final Map<String, Object?> payload;
  final DateTime dataHoraCriacao;

  /// Sequência local da pesagem; não depende da ordenação do relógio.
  final int ordem;
  final String? dependeDe, ultimoErro, idRemoto;
  final SyncEventStatus status;
  final int tentativas;

  SyncEvent withStatus(
    SyncEventStatus next, {
    String? error,
    String? remoteId,
  }) => SyncEvent(
    idLocal: idLocal,
    tipoEvento: tipoEvento,
    idPesagemLocal: idPesagemLocal,
    payload: payload,
    dataHoraCriacao: dataHoraCriacao,
    ordem: ordem,
    dependeDe: dependeDe,
    status: next,
    tentativas: tentativas + (next == SyncEventStatus.emEnvio ? 1 : 0),
    ultimoErro: error,
    idRemoto: remoteId ?? idRemoto,
  );
}

/// Agregado persistível em uma transação futura: leituras + outbox da pesagem.
/// Os IDs locais são estáveis durante a sessão, nunca substituídos pelos remotos.
class LocalWeighing {
  LocalWeighing({
    required this.idLocal,
    required this.preTicketId,
    required this.plate,
    required this.createdAt,
    this.phase = WeighingPhase.nova,
    this.firstReading,
    this.secondReading,
    Iterable<SyncEvent> events = const [],
  }) : events = List.unmodifiable(events);

  final String idLocal, preTicketId, plate;
  final DateTime createdAt;
  final WeighingPhase phase;
  final double? firstReading, secondReading;
  final List<SyncEvent> events;

  WeighingSyncStatus get syncStatus {
    if (events.isEmpty) return WeighingSyncStatus.semEventos;
    if (events.any((e) => e.status == SyncEventStatus.erro)) {
      return WeighingSyncStatus.erro;
    }
    if (events.any((e) => e.status == SyncEventStatus.emEnvio)) {
      return WeighingSyncStatus.sincronizando;
    }
    if (events.any((e) => e.status == SyncEventStatus.pendente)) {
      return WeighingSyncStatus.pendente;
    }
    return WeighingSyncStatus.sincronizada;
  }

  LocalWeighingState get state => switch (phase) {
    WeighingPhase.nova => LocalWeighingState.nova,
    WeighingPhase.aberta =>
      syncStatus == WeighingSyncStatus.sincronizada
          ? LocalWeighingState.abertaSincronizada
          : LocalWeighingState.abertaLocal,
    WeighingPhase.fechada =>
      syncStatus == WeighingSyncStatus.sincronizada
          ? LocalWeighingState.fechadaSincronizada
          : LocalWeighingState.fechadaLocal,
    WeighingPhase.ticketPendente => LocalWeighingState.ticketPendente,
    WeighingPhase.concluida => LocalWeighingState.concluida,
  };

  String? get idRemoto => events
      .where((e) => e.tipoEvento == SyncEventType.aberturaPesagem)
      .firstOrNull
      ?.idRemoto;

  LocalWeighing copyWith({
    WeighingPhase? phase,
    double? firstReading,
    double? secondReading,
    Iterable<SyncEvent>? events,
  }) => LocalWeighing(
    idLocal: idLocal,
    preTicketId: preTicketId,
    plate: plate,
    createdAt: createdAt,
    phase: phase ?? this.phase,
    firstReading: firstReading ?? this.firstReading,
    secondReading: secondReading ?? this.secondReading,
    events: events ?? this.events,
  );
}
