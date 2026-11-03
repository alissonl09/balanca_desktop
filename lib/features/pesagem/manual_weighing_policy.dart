import '../../core/indicators/indicator_driver.dart';
import '../../core/permissions/permission_models.dart';

class ManualWeighingPolicy {
  static bool available({
    required bool enabled,
    required IndicatorReading reading,
    required PermissionState permissions,
  }) =>
      (enabled || !reading.connected) &&
      permissions.allows(AppPermission.weigh) &&
      permissions.allows(AppPermission.useManual);
}

/// Autorização desta leitura; não é uma credencial persistida nem justificativa geral.
class ManualAuthorization {
  ManualAuthorization({required this.user, required String justification})
    : justification = justification.trim() {
    if (this.justification.isEmpty) {
      throw ArgumentError('Justificativa obrigatória.');
    }
  }
  final String user, justification;
}
