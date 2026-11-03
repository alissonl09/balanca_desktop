import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/offline/local_pesagem_store.dart';
import 'package:balanca_desktop/core/offline/offline_models.dart';
import 'package:balanca_desktop/core/offline/offline_station.dart';
import 'package:balanca_desktop/core/offline/pre_ticket_source.dart';

void main() {
  late OfflineStation station;
  late KnownPreTicket ticket;
  setUp(() {
    ticket = KnownPreTicket(id: 'pre-1', plate: 'ABC1D23');
    // Política explícita de teste, não decisão de autorização para o piloto.
    station = OfflineStation(
      canOpenOffline: (_) => true,
      clock: () => DateTime.utc(2026, 11, 2),
    );
  });
  tearDown(() => station.dispose());

  Future<String> open() async {
    final w = await station.create(ticket);
    await station.open(w.idLocal, 20000, ticket: ticket);
    return w.idLocal;
  }

  Future<void> confirmNext() async {
    final e = station.readyEvents.first;
    await station.beginEvent(e.idLocal);
    await station.confirmEvent(e.idLocal, remoteId: 'remote-${e.idLocal}');
  }

  test('nova pesagem local sem evento e sem ID remoto', () async {
    final w = await station.create(ticket);
    expect(w.phase, WeighingPhase.nova);
    expect(w.state, LocalWeighingState.nova);
    expect(w.syncStatus, WeighingSyncStatus.semEventos);
    expect(w.idRemoto, isNull);
    expect(station.pendingCount, 0);
  });

  test('abertura local pendente, mesmo estando online', () async {
    await station.setConnection(StationConnection.online);
    await open();
    final w = station.activeWeighing!;
    expect(w.state, LocalWeighingState.abertaLocal);
    expect(w.syncStatus, WeighingSyncStatus.pendente);
    expect(w.events.single.tipoEvento, SyncEventType.aberturaPesagem);
    expect(w.events.single.tentativas, 0);
    expect(station.pendingCount, 1);
  });

  test('abertura sincronizada somente após confirmação explícita', () async {
    await open();
    expect(station.readyEvents, isEmpty);
    await station.setConnection(StationConnection.online);
    await confirmNext();
    expect(
      station.activeWeighing!.state,
      LocalWeighingState.abertaSincronizada,
    );
    expect(station.activeWeighing!.idRemoto, isNotEmpty);
    expect(station.pendingCount, 0);
  });

  test('pesagem aberta sincronizada pode fechar offline', () async {
    final id = await open();
    await station.setConnection(StationConnection.online);
    await confirmNext();
    await station.setConnection(StationConnection.offline);
    await station.close(id, 8000);
    final w = station.activeWeighing!;
    expect(w.state, LocalWeighingState.fechadaLocal);
    expect(w.firstReading, 20000);
    expect(w.secondReading, 8000);
    expect(w.syncStatus, WeighingSyncStatus.pendente);
    expect(station.pendingCount, 1);
    expect(station.readyEvents, isEmpty);
  });

  test('fechamento sincronizado sem apagar as duas leituras', () async {
    final id = await open();
    await station.close(id, 8000);
    await station.setConnection(StationConnection.online);
    await confirmNext();
    // Confirmar abertura atrasada não regride fechamento local para aberta.
    expect(station.activeWeighing!.state, LocalWeighingState.fechadaLocal);
    await confirmNext();
    expect(
      station.activeWeighing!.state,
      LocalWeighingState.fechadaSincronizada,
    );
    expect(station.activeWeighing!.secondReading, 8000);
  });

  test(
    'ticket pendente pode ser enfileirado offline, mas não confirmado',
    () async {
      final id = await open();
      await station.close(id, 8000);
      await station.requestTicket(id, {'format': 'pilot'});
      expect(station.activeWeighing!.phase, WeighingPhase.ticketPendente);
      expect(station.activeWeighing!.state, LocalWeighingState.ticketPendente);
      expect(station.pendingCount, 3);
      expect(station.readyEvents, isEmpty);
    },
  );

  test(
    'erro de envio preserva fase física, leituras, payload e dependentes',
    () async {
      final id = await open();
      await station.close(id, 8000);
      await station.setConnection(StationConnection.online);
      await confirmNext();
      final e = station.readyEvents.single;
      await station.beginEvent(e.idLocal);
      await station.failEvent(e.idLocal, 'Falha simulada');
      final w = station.activeWeighing!;
      expect(w.phase, WeighingPhase.fechada);
      expect(w.syncStatus, WeighingSyncStatus.erro);
      expect(w.secondReading, 8000);
      expect(w.events.last.ultimoErro, 'Falha simulada');
      expect(w.events.last.tentativas, 1);
      expect(w.events.last.payload['reading'], 8000);
      expect(station.readyEvents, isEmpty); // Nenhum retry automático.
    },
  );

  test('fechamento não pode iniciar ou confirmar antes da abertura', () async {
    final id = await open();
    await station.close(id, 8000);
    await station.setConnection(StationConnection.online);
    final opening = station.events.first;
    final closing = station.events.last;
    expect(station.readyEvents.map((e) => e.idLocal), [opening.idLocal]);
    await expectLater(station.beginEvent(closing.idLocal), throwsStateError);
    await expectLater(
      station.confirmEvent(closing.idLocal, remoteId: 'remote'),
      throwsStateError,
    );
    await station.beginEvent(opening.idLocal);
    expect(station.readyEvents, isEmpty); // Envio não é confirmação.
    await station.confirmEvent(opening.idLocal, remoteId: 'remote-opening');
    expect(station.readyEvents.single.idLocal, closing.idLocal);
  });

  test(
    'ticket depende da confirmação de fechamento, com ordem mesmo relógio',
    () async {
      final id = await open();
      await station.close(id, 8000);
      await station.requestTicket(id, {});
      await station.setConnection(StationConnection.online);
      final e = station.events.last;
      expect(station.events.map((e) => e.ordem), [1, 2, 3]);
      await expectLater(station.beginEvent(e.idLocal), throwsStateError);
      await confirmNext();
      await expectLater(station.beginEvent(e.idLocal), throwsStateError);
      await confirmNext();
      expect(
        station.readyEvents.single.tipoEvento,
        SyncEventType.registroTicket,
      );
      await confirmNext();
      expect(station.activeWeighing!.state, LocalWeighingState.concluida);
      expect(
        station.activeWeighing!.syncStatus,
        WeighingSyncStatus.sincronizada,
      );
      expect(station.pendingCount, 0);
    },
  );

  test('cancelamento de ticket depende do registro confirmado', () async {
    final id = await open();
    await station.close(id, 8000);
    await station.requestTicket(id, {});
    await expectLater(station.cancelTicket(id, {}), throwsStateError);
    await station.setConnection(StationConnection.online);
    for (var i = 0; i < 3; i++) {
      await confirmNext();
    }
    final registered = station.events.last;
    await station.setConnection(StationConnection.offline);
    await station.cancelTicket(id, {'reason': 'Teste'});
    expect(station.activeWeighing!.phase, WeighingPhase.ticketPendente);
    expect(station.events.last.dependeDe, registered.idLocal);
    expect(station.events.last.tipoEvento, SyncEventType.cancelamentoTicket);
    await station.setConnection(StationConnection.online);
    await confirmNext();
    await expectLater(station.cancelTicket(id, {}), throwsStateError);
  });

  test(
    'progresso global é um lote fixo e pendências incluem bloqueados/erro',
    () async {
      final id = await open();
      await station.close(id, 8000);
      await station.requestTicket(id, {});
      await station.setConnection(StationConnection.online);
      await station.setConnection(StationConnection.sincronizando);
      expect(station.syncTotal, 3);
      expect(station.syncCompleted, 0);
      await confirmNext();
      await confirmNext();
      expect(station.syncCompleted, 2);
      expect(station.syncTotal, 3);
      expect(station.pendingCount, 1);
      await confirmNext();
      expect(station.syncCompleted, 3);
      await station.setConnection(StationConnection.online);
      expect(station.syncTotal, 0);
    },
  );

  test(
    'cair offline com envio em curso não perde evento nem libera sucessor',
    () async {
      final id = await open();
      await station.close(id, 8000);
      await station.setConnection(StationConnection.online);
      final e = station.readyEvents.first;
      await station.beginEvent(e.idLocal);
      await station.setConnection(StationConnection.offline);
      expect(station.connection, StationConnection.offline);
      expect(station.pendingCount, 2);
      expect(station.readyEvents, isEmpty);
      await station.failEvent(e.idLocal, 'Rede interrompida');
      await station.setConnection(StationConnection.online);
      expect(station.readyEvents, isEmpty);
    },
  );

  test(
    'pesagens independentes e chamadas concorrentes não perdem eventos',
    () async {
      final ids = await Future.wait([
        station.create(ticket),
        station.create(ticket),
      ]);
      await Future.wait([
        for (final w in ids) station.open(w.idLocal, 100, ticket: ticket),
      ]);
      await station.setConnection(StationConnection.online);
      expect(station.readyEvents, hasLength(2));
      expect(station.events.map((e) => e.idLocal).toSet(), hasLength(2));
      final id = ids.first.idLocal;
      final results = await Future.wait([
        station.close(id, 50).then((_) => true, onError: (Object _) => false),
        station.close(id, 40).then((_) => true, onError: (Object _) => false),
      ]);
      expect(results.where((ok) => ok), hasLength(1));
      expect(station.pendingCount, 3);
    },
  );

  test(
    'snapshot de payload é profundamente imutável e confirmação idempotente',
    () async {
      final id = await open();
      await station.close(id, 8000);
      final docs = <Object?>['NF1'];
      await station.requestTicket(id, {'docs': docs});
      docs.add('NF2');
      final e = station.events.last;
      expect(e.payload['docs'], ['NF1']);
      expect(
        () => (e.payload['docs'] as List).add('NF3'),
        throwsUnsupportedError,
      );
      await station.setConnection(StationConnection.online);
      final opening = station.readyEvents.first;
      await station.beginEvent(opening.idLocal);
      await station.confirmEvent(opening.idLocal, remoteId: 'remote');
      await station.confirmEvent(opening.idLocal, remoteId: 'remote');
      await expectLater(
        station.confirmEvent(opening.idLocal, remoteId: 'other'),
        throwsStateError,
      );
      expect(station.events.first.tentativas, 1);
    },
  );

  test(
    'abertura offline exige política explícita, fechamento não a reavalia',
    () async {
      final restricted = OfflineStation();
      addTearDown(restricted.dispose);
      final w = await restricted.create(ticket);
      await expectLater(
        restricted.open(w.idLocal, 100, ticket: ticket),
        throwsStateError,
      );
      expect(restricted.pendingCount, 0);
      await restricted.setConnection(StationConnection.online);
      await restricted.open(w.idLocal, 100, ticket: ticket);
      await restricted.setConnection(StationConnection.offline);
      await restricted.close(w.idLocal, 50);
      expect(restricted.activeWeighing!.state, LocalWeighingState.fechadaLocal);
    },
  );

  test(
    'leituras inválidas e transições fora de ordem não entram na fila',
    () async {
      final w = await station.create(ticket);
      await expectLater(station.close(w.idLocal, 10), throwsStateError);
      await expectLater(station.requestTicket(w.idLocal, {}), throwsStateError);
      for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
        await expectLater(
          station.open(w.idLocal, invalid, ticket: ticket),
          throwsArgumentError,
        );
      }
      expect(station.pendingCount, 0);
      expect(station.activeWeighing!.phase, WeighingPhase.nova);
    },
  );

  test(
    'store pode ser substituído e agregado reaberto sem perder ordem',
    () async {
      final store = MemoryLocalPesagemStore();
      final first = OfflineStation(store: store, canOpenOffline: (_) => true);
      final w = await first.create(ticket);
      await first.open(w.idLocal, 100, ticket: ticket);
      await first.close(w.idLocal, 50);
      first.dispose();
      final restored = OfflineStation(store: store);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.weighings.single.state, LocalWeighingState.fechadaLocal);
      expect(restored.pendingCount, 2);
      await restored.setConnection(StationConnection.online);
      expect(
        restored.readyEvents.single.tipoEvento,
        SyncEventType.aberturaPesagem,
      );
    },
  );

  test('store que recusa gravação não publica leitura sem outbox', () async {
    final store = RejectingStore();
    final s = OfflineStation(store: store, canOpenOffline: (_) => true);
    addTearDown(s.dispose);
    final w = await s.create(ticket);
    store.reject = true;
    await expectLater(s.open(w.idLocal, 100, ticket: ticket), throwsStateError);
    expect(s.activeWeighing!.phase, WeighingPhase.nova);
    expect(s.pendingCount, 0);
  });

  test(
    'pré-ticket offline usa somente local; desconhecido não é inventado',
    () async {
      final local = MemoryPreTicketSource([ticket]);
      final remote = CountingSource(ticket);
      final resolver = PreTicketResolver(local: local, remote: remote);
      final known = await resolver.lookup(
        ticket.plate,
        StationConnection.offline,
      );
      expect(known.origin, PreTicketOrigin.local);
      expect(known.ticket, same(ticket));
      final unknown = await resolver.lookup(
        'ZZZ9Z99',
        StationConnection.offline,
      );
      expect(unknown.ticket, isNull);
      expect(remote.calls, 0);
      final online = await resolver.lookup(
        ticket.plate,
        StationConnection.online,
      );
      expect(online.origin, PreTicketOrigin.remota);
      expect(remote.calls, 1);
      expect(PreTicketResolver.remotePath, '/api/v1/pre-tickets');
    },
  );

  test(
    'lote não incorpora eventos novos e confirmação não muda a seleção',
    () async {
      final first = await open();
      await station.setConnection(StationConnection.online);
      await station.setConnection(StationConnection.sincronizando);
      final e = station.readyEvents.single;
      final second = await station.create(ticket);
      await station.open(second.idLocal, 100, ticket: ticket);
      expect(station.syncTotal, 1);
      expect(station.readyEvents.map((e) => e.idPesagemLocal), [first]);
      await station.beginEvent(e.idLocal);
      await station.confirmEvent(e.idLocal, remoteId: 'first');
      expect(station.activeWeighing!.idLocal, second.idLocal);
      expect(station.syncCompleted, 1);
      expect(station.pendingCount, 1);
      expect(station.readyEvents, isEmpty);
      await station.setConnection(StationConnection.online);
      expect(station.readyEvents.single.idPesagemLocal, second.idLocal);
    },
  );

  test(
    'evento restaurado sem abertura ou com dependência inválida não é pronto',
    () async {
      final store = MemoryLocalPesagemStore();
      await store.save(
        LocalWeighing(
          idLocal: 'broken',
          preTicketId: 'pre',
          plate: 'ABC1D23',
          createdAt: DateTime.utc(2026),
          phase: WeighingPhase.fechada,
          events: [
            SyncEvent(
              idLocal: 'closing',
              tipoEvento: SyncEventType.fechamentoPesagem,
              idPesagemLocal: 'broken',
              payload: {},
              dataHoraCriacao: DateTime.utc(2026),
              ordem: 1,
            ),
          ],
        ),
      );
      final restored = OfflineStation(store: store);
      addTearDown(restored.dispose);
      await restored.load();
      await restored.setConnection(StationConnection.online);
      expect(restored.pendingCount, 1);
      expect(restored.readyEvents, isEmpty);
      await expectLater(restored.beginEvent('closing'), throwsStateError);
    },
  );

  test('fábrica com ID duplicado não sobrescreve pesagem', () async {
    final fixed = OfflineStation(idFactory: () => 'same');
    addTearDown(fixed.dispose);
    await fixed.create(ticket);
    await expectLater(fixed.create(ticket), throwsStateError);
    expect(fixed.weighings, hasLength(1));
  });
}

class RejectingStore extends MemoryLocalPesagemStore {
  bool reject = false;
  @override
  Future<void> save(LocalWeighing weighing) async {
    if (reject) throw StateError('Falha simulada no armazenamento');
    await super.save(weighing);
  }
}

class CountingSource implements PreTicketSource {
  CountingSource(this.ticket);
  final KnownPreTicket ticket;
  int calls = 0;
  @override
  Future<KnownPreTicket?> findByPlate(String plate) async {
    calls++;
    return ticket;
  }
}
