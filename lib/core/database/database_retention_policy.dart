import '../offline/offline_models.dart';

/// Somente elegibilidade futura; esta etapa não remove dados operacionais.
class DatabaseRetentionPolicy {
  DatabaseRetentionPolicy({required this.operationRetention}) {
    if (operationRetention <= Duration.zero) {
      throw ArgumentError('A retenção operacional deve ser positiva.');
    }
  }
  final Duration operationRetention;

  bool canPurge({
    required LocalWeighing weighing,
    required DateTime? completedAt,
    required bool hasActiveAccess,
    required DateTime now,
  }) =>
      !hasActiveAccess &&
      completedAt != null &&
      weighing.phase == WeighingPhase.concluida &&
      weighing.events.isNotEmpty &&
      weighing.syncStatus == WeighingSyncStatus.sincronizada &&
      !completedAt.isAfter(now.subtract(operationRetention));
}
