import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'indicator_models.dart';

/// Estado normalizado para a aplicação: zero é um valor válido e independente
/// do estado de conexão. Estabilidade desconhecida permanece nula.
class IndicatorReading {
  const IndicatorReading({
    this.weight,
    this.unit = 'kg',
    this.stable,
    this.status = IndicatorConnectionStatus.disconnected,
    this.readAt,
    this.error,
    this.gross,
    this.wholeKg,
    this.decimalPlaces,
    this.physical = false,
    this.source,
    this.recovering = false,
  });
  final double? weight;
  final String unit;
  final bool? stable;
  final IndicatorConnectionStatus status;
  final DateTime? readAt;
  final String? error;
  final bool? gross;
  final int? wholeKg, decimalPlaces;
  final bool physical;
  final bool recovering;
  final String? source;
  bool get connected => status == IndicatorConnectionStatus.connected;
  bool get allowsManualContingency =>
      !connected &&
      (!physical ||
          recovering ||
          (status != IndicatorConnectionStatus.connecting &&
              status != IndicatorConnectionStatus.awaitingData));
}

abstract interface class IndicatorTransport {
  Stream<List<int>> get bytes;
  Future<void> connect(IndicatorInstallation installation);
  Future<void> disconnect();
}

/// Socket assíncrono. Não interpreta bytes e não presume um protocolo.
class TcpIndicatorTransport implements IndicatorTransport {
  Socket? _socket;
  final _bytes = StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? _subscription;
  @override
  Stream<List<int>> get bytes => _bytes.stream;

  @override
  Future<void> connect(IndicatorInstallation installation) async {
    final host = installation.host;
    final port = installation.tcpPort;
    if (host == null || port == null) {
      throw const FormatException('Endereço/porta TCP ausente.');
    }
    debugPrint('Indicador: conectando TCP $host:$port');
    final socket = await Socket.connect(
      host,
      port,
      timeout: Duration(milliseconds: installation.timeoutMs),
    );
    _socket = socket;
    _subscription = socket.listen(
      (data) => _bytes.add(List<int>.from(data)),
      onError: (Object error) {
        debugPrint('Indicador: erro TCP $error');
      },
      onDone: () => debugPrint('Indicador: socket TCP desconectado'),
    );
    debugPrint('Indicador: conexão TCP estabelecida');
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
  }
}

abstract interface class IndicatorDriver {
  String get modelCode;
  Stream<IndicatorReading> get readings;
  Future<void> connect(IndicatorInstallation installation);
  Future<void> disconnect();
}

/// Transporte e parser são injetados separadamente. Sem parser documentado,
/// bytes recebidos não são convertidos em peso.
class UnconfiguredIndicatorDriver implements IndicatorDriver {
  UnconfiguredIndicatorDriver({
    required this.modelCode,
    required this.transport,
  });
  @override
  final String modelCode;
  final IndicatorTransport transport;
  final _readings = StreamController<IndicatorReading>.broadcast();
  StreamSubscription<List<int>>? _subscription;
  Timer? _healthTimer;
  DateTime? _lastRead;
  @override
  Stream<IndicatorReading> get readings => _readings.stream;

  @override
  Future<void> connect(IndicatorInstallation installation) async {
    _readings.add(
      const IndicatorReading(status: IndicatorConnectionStatus.connecting),
    );
    try {
      await transport.connect(installation);
      _lastRead = null;
      _subscription = transport.bytes.listen((_) {
        // Sem formato de protocolo declarado, não fabricamos uma leitura.
      });
      _healthTimer?.cancel();
      _healthTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        final last = _lastRead;
        if (last == null ||
            DateTime.now().difference(last).inMilliseconds >
                installation.timeoutMs) {
          _readings.add(
            const IndicatorReading(
              status: IndicatorConnectionStatus.noCommunication,
              error: 'Nenhuma leitura válida recebida.',
            ),
          );
        }
      });
    } catch (error) {
      _readings.add(
        IndicatorReading(
          status: IndicatorConnectionStatus.error,
          error: error is SocketException
              ? 'Host inacessível ou porta indisponível.'
              : 'Falha ao conectar.',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _healthTimer?.cancel();
    await _subscription?.cancel();
    await transport.disconnect();
    _readings.add(
      const IndicatorReading(status: IndicatorConnectionStatus.disconnected),
    );
  }
}

class MockIndicatorDriver implements IndicatorDriver {
  MockIndicatorDriver({this.modelCode = 'mock'});
  @override
  final String modelCode;
  final _readings = StreamController<IndicatorReading>.broadcast();
  @override
  Stream<IndicatorReading> get readings => _readings.stream;
  void simulate(IndicatorReading reading) => _readings.add(reading);
  @override
  Future<void> connect(IndicatorInstallation installation) async => simulate(
    IndicatorReading(
      status: IndicatorConnectionStatus.connected,
      readAt: DateTime.now(),
    ),
  );
  @override
  Future<void> disconnect() async => simulate(const IndicatorReading());
}

class MemoryIndicatorState extends ChangeNotifier {
  IndicatorReading _reading = const IndicatorReading();
  IndicatorReading get reading => _reading;
  void simulate(IndicatorReading value) => publish(value);

  void publish(IndicatorReading value) {
    final previous = _reading;
    _reading = value;
    if ((
          previous.weight,
          previous.unit,
          previous.stable,
          previous.status,
          previous.error,
          previous.gross,
          previous.physical,
          previous.source,
          previous.decimalPlaces,
          previous.recovering,
        ) !=
        (
          value.weight,
          value.unit,
          value.stable,
          value.status,
          value.error,
          value.gross,
          value.physical,
          value.source,
          value.decimalPlaces,
          value.recovering,
        )) {
      notifyListeners();
    }
  }
}
