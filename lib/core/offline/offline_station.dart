import 'package:flutter/foundation.dart';

import 'local_pesagem_store.dart';
import 'offline_models.dart';
import 'pre_ticket_source.dart';

typedef OfflineOpeningPolicy = bool Function(KnownPreTicket ticket);

/// Estado global e comandos locais. Nunca inicia HTTP, timer, retry ou background.
/// Confirmações são entradas explícitas, destinadas ao futuro adaptador Libra.
class OfflineStation extends ChangeNotifier {
  OfflineStation({
    LocalPesagemStore? store,
    OfflineOpeningPolicy? canOpenOffline,
    DateTime Function()? clock,
    this.idFactory,
  }) : _store = store ?? MemoryLocalPesagemStore(),
       _canOpenOffline = canOpenOffline ?? ((_) => false),
       _clock = clock ?? DateTime.now;

  final LocalPesagemStore _store;
  final OfflineOpeningPolicy _canOpenOffline;
  final DateTime Function() _clock;
  final String Function()? idFactory;
  final _items = <String, LocalWeighing>{};
  Future<void> _tail = Future.value();
  bool _loaded = false;
  static int _ids = 0;
  // IDs provisórios únicos nesta execução; adaptador durável definirá a fábrica.
  String _id() {
    bool exists(String id) =>
        _items.containsKey(id) || events.any((e) => e.idLocal == id);
    if (idFactory case final factory?) {
      final id = factory();
      if (id.trim().isEmpty || exists(id)) {
        throw StateError('ID local vazio ou duplicado.');
      }
      return id;
    }
    var id = 'local-${++_ids}';
    while (exists(id)) {
      id = 'local-${++_ids}';
    }
    return id;
  }

  StationConnection _connection = StationConnection.offline;
  StationConnection get connection => _connection;
  String? _activeId;
  LocalWeighing? get activeWeighing => _items[_activeId];
  List<LocalWeighing> get weighings => List.unmodifiable(_items.values);
  List<SyncEvent> get events =>
      List.unmodifiable(_items.values.expand((w) => w.events));
  int get pendingCount =>
      events.where((e) => e.status != SyncEventStatus.confirmado).length;
  Set<String> _batch = {};
  int get syncTotal => _batch.length;
  int get syncCompleted => events
      .where(
        (e) =>
            _batch.contains(e.idLocal) &&
            e.status == SyncEventStatus.confirmado,
      )
      .length;

  /// Uma fila por pesagem. Erro, envio em curso ou predecessor ausente bloqueiam
  /// os posteriores; pesagens independentes não precisam esperar umas às outras.
  List<SyncEvent> get readyEvents {
    if (_connection == StationConnection.offline) return const [];
    return List.unmodifiable(
      _items.values.expand((w) {
        final first = w.events
            .where((e) => e.status != SyncEventStatus.confirmado)
            .firstOrNull;
        if (first == null || first.status != SyncEventStatus.pendente) {
          return <SyncEvent>[];
        }
        if (_connection == StationConnection.sincronizando &&
            !_batch.contains(first.idLocal)) {
          return <SyncEvent>[];
        }
        if (!_predecessorsConfirmed(w, first)) {
          return <SyncEvent>[];
        }
        return [first];
      }),
    );
  }

  bool _predecessorsConfirmed(LocalWeighing w, SyncEvent e) {
    final index = w.events.indexWhere(
      (candidate) => candidate.idLocal == e.idLocal,
    );
    if (index < 0 || e.ordem != index + 1) return false;
    if (e.tipoEvento == SyncEventType.aberturaPesagem) {
      return index == 0 && e.dependeDe == null;
    }
    if (index == 0) return false;
    final previous = w.events[index - 1];
    final expected = switch (e.tipoEvento) {
      SyncEventType.fechamentoPesagem => SyncEventType.aberturaPesagem,
      SyncEventType.registroTicket => SyncEventType.fechamentoPesagem,
      SyncEventType.cancelamentoTicket => SyncEventType.registroTicket,
      SyncEventType.aberturaPesagem => throw StateError('Tratado acima'),
    };
    return e.dependeDe == previous.idLocal &&
        previous.tipoEvento == expected &&
        w.events
            .take(index)
            .every((p) => p.status == SyncEventStatus.confirmado);
  }

  /// Serializa mutações e só publica o estado após o store aceitar o agregado.
  Future<T> _command<T>(Future<T> Function() work) {
    final result = _tail.then((_) async {
      if (!_loaded) {
        final saved = await _store.loadAll();
        for (final w in saved) {
          _items[w.idLocal] = w;
        }
        _loaded = true;
      }
      return work();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> load() => _command(() async {
    notifyListeners();
  });

  Future<void> selectWeighing(String? id) => _command(() async {
    if (id != null) {
      _get(id);
    }
    _activeId = id;
    notifyListeners();
  });

  Future<void> _save(LocalWeighing w, {bool activate = false}) async {
    await _store.save(w);
    _items[w.idLocal] = w;
    if (activate) {
      _activeId = w.idLocal;
    }
    notifyListeners();
  }

  Future<void> setConnection(StationConnection next) => _command(() async {
    if (next == StationConnection.sincronizando) {
      if (_connection == StationConnection.offline) {
        throw StateError('Estação offline.');
      }
      if (_batch.isEmpty) {
        _batch = events
            .where((e) => e.status != SyncEventStatus.confirmado)
            .map((e) => e.idLocal)
            .toSet();
        if (_batch.isEmpty) {
          throw StateError('Não há pendências para sincronizar.');
        }
      }
    } else {
      // Cair offline não é confirmação nem retry: preserva o envio em curso
      // até o adaptador informar seu resultado explicitamente.
      _batch = {};
    }
    _connection = next;
    notifyListeners();
  });

  Future<LocalWeighing> create(KnownPreTicket ticket) => _command(() async {
    if (ticket.id.trim().isEmpty || ticket.plate.trim().isEmpty) {
      throw ArgumentError('Pré-ticket conhecido obrigatório.');
    }
    final w = LocalWeighing(
      idLocal: _id(),
      preTicketId: ticket.id,
      plate: ticket.plate,
      createdAt: _clock(),
    );
    await _save(w, activate: true);
    return w;
  });

  LocalWeighing _get(String id) =>
      _items[id] ?? (throw StateError('Pesagem local não encontrada.'));

  Future<void> open(
    String id,
    double reading, {
    required KnownPreTicket ticket,
  }) => _command(() async {
    final w = _get(id);
    if (w.phase != WeighingPhase.nova) throw StateError('Pesagem já aberta.');
    if (ticket.id != w.preTicketId || ticket.plate != w.plate) {
      throw StateError('Pré-ticket não corresponde à pesagem.');
    }
    if (_connection == StationConnection.offline && !_canOpenOffline(ticket)) {
      throw StateError(
        'Abertura offline ainda não autorizada pela política local.',
      );
    }
    _validateReading(reading);
    await _save(
      _append(
        w.copyWith(phase: WeighingPhase.aberta, firstReading: reading),
        SyncEventType.aberturaPesagem,
        {'reading': reading},
      ),
    );
  });

  Future<void> close(String id, double reading) => _command(() async {
    final w = _get(id);
    if (w.phase != WeighingPhase.aberta) {
      throw StateError('É necessária uma pesagem aberta.');
    }
    _validateReading(reading);
    await _save(
      _append(
        w.copyWith(phase: WeighingPhase.fechada, secondReading: reading),
        SyncEventType.fechamentoPesagem,
        {'reading': reading},
      ),
    );
  });

  Future<void> requestTicket(String id, Map<String, Object?> payload) =>
      _command(() async {
        final w = _get(id);
        if (w.phase != WeighingPhase.fechada) {
          throw StateError('Feche a pesagem antes de registrar ticket.');
        }
        await _save(
          _append(
            w.copyWith(phase: WeighingPhase.ticketPendente),
            SyncEventType.registroTicket,
            payload,
          ),
        );
      });

  Future<void> cancelTicket(String id, Map<String, Object?> payload) =>
      _command(() async {
        final w = _get(id);
        if (w.phase != WeighingPhase.concluida ||
            w.events.last.tipoEvento != SyncEventType.registroTicket) {
          throw StateError('Ticket confirmado obrigatório para cancelamento.');
        }
        await _save(
          _append(
            w.copyWith(phase: WeighingPhase.ticketPendente),
            SyncEventType.cancelamentoTicket,
            payload,
          ),
        );
      });

  LocalWeighing _append(
    LocalWeighing w,
    SyncEventType type,
    Map<String, Object?> payload,
  ) => w.copyWith(
    events: [
      ...w.events,
      SyncEvent(
        idLocal: _id(),
        tipoEvento: type,
        idPesagemLocal: w.idLocal,
        payload: payload,
        dataHoraCriacao: _clock(),
        ordem: w.events.length + 1,
        dependeDe: w.events.lastOrNull?.idLocal,
      ),
    ],
  );

  void _validateReading(double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError('Leitura deve ser positiva e finita.');
    }
  }

  (LocalWeighing, SyncEvent) _findEvent(String id) {
    for (final w in _items.values) {
      for (final e in w.events) {
        if (e.idLocal == id) return (w, e);
      }
    }
    throw StateError('Evento não encontrado.');
  }

  Future<void> beginEvent(String id) => _command(() async {
    if (!readyEvents.any((e) => e.idLocal == id)) {
      throw StateError('Evento não está pronto para sincronização.');
    }
    final (w, e) = _findEvent(id);
    await _replace(w, e.withStatus(SyncEventStatus.emEnvio));
  });

  Future<void> confirmEvent(String id, {required String remoteId}) => _command(
    () async {
      final (w, e) = _findEvent(id);
      // Confirmação repetida é idempotente, mas não aceita outro ID remoto.
      if (e.status == SyncEventStatus.confirmado && e.idRemoto == remoteId) {
        return;
      }
      if (e.status != SyncEventStatus.emEnvio || remoteId.trim().isEmpty) {
        throw StateError('Confirmação requer envio iniciado e ID remoto.');
      }
      if (!_predecessorsConfirmed(w, e)) {
        throw StateError('Predecessor não confirmado.');
      }
      final next = e.withStatus(SyncEventStatus.confirmado, remoteId: remoteId);
      final phase =
          e.tipoEvento == SyncEventType.registroTicket ||
              e.tipoEvento == SyncEventType.cancelamentoTicket
          ? WeighingPhase.concluida
          : w.phase;
      await _replace(w.copyWith(phase: phase), next);
    },
  );

  Future<void> failEvent(String id, String error) => _command(() async {
    final (w, e) = _findEvent(id);
    if (e.status != SyncEventStatus.emEnvio || error.trim().isEmpty) {
      throw StateError('Falha requer envio em curso e descrição.');
    }
    await _replace(w, e.withStatus(SyncEventStatus.erro, error: error));
  });

  Future<void> _replace(LocalWeighing w, SyncEvent event) => _save(
    w.copyWith(
      events: [
        for (final old in w.events) old.idLocal == event.idLocal ? event : old,
      ],
    ),
  );
}
