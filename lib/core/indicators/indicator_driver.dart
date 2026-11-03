import 'package:flutter/foundation.dart';

import 'indicator_models.dart';

/// Contrato normalizado para a aplicação, independente de fabricante/transporte.
class IndicatorReading {
  const IndicatorReading({
    this.weight,
    this.unit = 'Kg',
    this.stable = false,
    this.status = IndicatorConnectionStatus.disconnected,
    this.readAt,
    this.error,
  });
  final double? weight;
  final String unit;
  final bool stable;
  final IndicatorConnectionStatus status;
  final DateTime? readAt;
  final String? error;
  bool get connected => status == IndicatorConnectionStatus.connected;
}

/// Futuras implementações por modelo fornecem parser e transporte.
/// Não existe implementação Serial/TCP nem parser nesta etapa.
abstract interface class IndicatorDriver {
  String get modelCode;
  Stream<IndicatorReading> get readings;
  Future<void> connect(IndicatorInstallation installation);
  Future<void> disconnect();
}

class MemoryIndicatorState extends ChangeNotifier {
  IndicatorReading _reading = const IndicatorReading();
  IndicatorReading get reading => _reading;
  void simulate(IndicatorReading value) {
    _reading = value;
    notifyListeners();
  }
}
