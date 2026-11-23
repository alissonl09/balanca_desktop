import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/database/database_retention_policy.dart';
import 'package:balanca_desktop/core/offline/offline_models.dart';

void main() {
  test('expurgo futuro exige conclusão, confirmação, retenção e ausência de acesso ativo', () {
    final now = DateTime.utc(2026, 11, 23);
    final policy = DatabaseRetentionPolicy(
      operationRetention: const Duration(days: 30),
    );
    final event = SyncEvent(
      idLocal: 'event',
      tipoEvento: SyncEventType.registroTicket,
      idPesagemLocal: 'w',
      payload: {},
      dataHoraCriacao: now,
      ordem: 1,
      status: SyncEventStatus.confirmado,
    );
    final w = LocalWeighing(
      idLocal: 'w',
      preTicketId: 'p',
      plate: 'ABC1D23',
      createdAt: now,
      phase: WeighingPhase.concluida,
      events: [event],
    );
    bool eligible(LocalWeighing value, {bool access = false, DateTime? at}) =>
        policy.canPurge(
          weighing: value,
          completedAt: at ?? now.subtract(const Duration(days: 31)),
          hasActiveAccess: access,
          now: now,
        );
    expect(eligible(w), isTrue);
    expect(eligible(w, access: true), isFalse);
    expect(eligible(w, at: now), isFalse);
    for (final phase in WeighingPhase.values.where(
      (p) => p != WeighingPhase.concluida,
    )) {
      expect(eligible(w.copyWith(phase: phase)), isFalse);
    }
    for (final status in SyncEventStatus.values.where(
      (s) => s != SyncEventStatus.confirmado,
    )) {
      expect(eligible(w.copyWith(events: [event.withStatus(status)])), isFalse);
    }
    expect(eligible(w.copyWith(events: [])), isFalse);
    expect(
      policy.canPurge(
        weighing: w,
        completedAt: null,
        hasActiveAccess: false,
        now: now,
      ),
      isFalse,
    );
  });
}
