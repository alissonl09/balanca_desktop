import 'dart:async';
import 'dart:math' as math;

import 'indicator_driver.dart';
import 'indicator_models.dart';
import 'toledo_continuous.dart';
import 'windows_serial_transport.dart';

class SerialDiagnostics {
  const SerialDiagnostics({
    required this.reading,
    required this.portOpen,
    required this.bytesReceived,
    required this.validFrames,
    required this.invalidFrames,
    required this.sample,
    required this.lastValidAt,
    required this.lastValidReading,
    required this.lastInvalid,
    required this.observedAt,
  });

  final IndicatorReading reading;
  final bool portOpen;
  final int bytesReceived, validFrames, invalidFrames;
  final List<int> sample;
  final DateTime? lastValidAt;
  final IndicatorReading? lastValidReading;
  final String? lastInvalid;
  final DateTime observedAt;

  String get hex => sample.map(_hexByte).join(' ');
  String get ascii => sample
      .map(
        (byte) => switch (byte) {
          0x02 => '<STX>',
          0x0d => '<CR>',
          0x0a => '<LF>',
          0x5c => r'\\',
          >= 0x20 && <= 0x7e => String.fromCharCode(byte),
          _ => r'\x' + _hexByte(byte),
        },
      )
      .join();

  static String _hexByte(int byte) =>
      byte.toRadixString(16).padLeft(2, '0').toUpperCase();
}

class SerialCapture {
  const SerialCapture._(this.reading, this._session, this._generation);

  final IndicatorReading reading;
  final _SerialSession _session;
  final int _generation;
}

/// Único dono da sessão operacional ou de diagnóstico da estação.
class SerialIndicatorService {
  SerialIndicatorService(
    this.state, {
    IndicatorTransport Function()? transportFactory,
    Future<List<String>> Function()? portList,
    Duration Function()? monotonicNow,
  }) : _transportFactory = transportFactory ?? WindowsSerialTransport.new,
       availablePorts = portList ?? WindowsSerialTransport.availablePorts,
       _now =
           monotonicNow ??
           (() {
             final clock = Stopwatch()..start();
             return () => clock.elapsed;
           })();

  final MemoryIndicatorState state;
  final IndicatorTransport Function() _transportFactory;
  final Future<List<String>> Function() availablePorts;
  final Duration Function() _now;
  Future<void> _queue = Future.value();
  _SerialSession? _session;
  IndicatorInstallation? _target;
  Object? _configurationKey;
  IndicatorMode _mode = IndicatorMode.simulated;
  Completer<SerialDiagnostics?>? _cancelTest;
  bool _disposed = false;

  bool get realMode => _mode == IndicatorMode.real;
  SerialDiagnostics? get diagnostics => _session?.diagnostics;

  void configure({
    required String station,
    required IndicatorMode mode,
    IndicatorInstallation? installation,
    String? issue,
  }) {
    if (_disposed) return;
    final key = (
      station,
      mode,
      installation?.id,
      installation?.name,
      installation?.serialParameters,
      issue,
    );
    if (key == _configurationKey) return;
    final previousMode = _mode;
    final hadConfiguration = _configurationKey != null;
    _configurationKey = key;
    _mode = mode;
    _target =
        mode == IndicatorMode.real && issue == null && installation != null
        ? IndicatorInstallation.fromJson(installation.toJson())
        : null;
    _cancelDiagnostic();
    final previous = _session;
    _session = null;
    if (realMode) {
      state.publish(
        IndicatorReading(
          physical: true,
          status: _target != null
              ? IndicatorConnectionStatus.connecting
              : issue == null
              ? IndicatorConnectionStatus.disabled
              : IndicatorConnectionStatus.error,
          error: issue,
        ),
      );
    } else if (previousMode == IndicatorMode.real || hadConfiguration) {
      state.publish(const IndicatorReading());
    }
    unawaited(
      _enqueue(() async {
        await previous?.stop();
        if (_configurationKey == key) _startOperational();
      }),
    );
  }

  SerialCapture capture() {
    final session = _session;
    final reading = session?.freshReading;
    if (session == null || reading == null) {
      throw FormatException(
        state.reading.error ?? 'Aguarde uma leitura recente do indicador.',
      );
    }
    if (reading.gross != true) {
      throw const FormatException(
        'O indicador está em peso líquido. Capture em peso bruto.',
      );
    }
    if (reading.stable != true) {
      throw const FormatException('Aguarde o peso estabilizar.');
    }
    if (reading.wholeKg! <= 0) {
      throw const FormatException('A pesagem exige peso bruto positivo em kg.');
    }
    return SerialCapture._(reading, session, session.generation);
  }

  bool canConfirm(SerialCapture capture) {
    final session = _session;
    return session != null &&
        identical(session, capture._session) &&
        session.generation == capture._generation &&
        session.freshReading != null;
  }

  Future<SerialDiagnostics?> testConnection(
    IndicatorInstallation installation,
  ) {
    if (_disposed || _cancelTest != null) return Future.value(null);
    final target = IndicatorInstallation.fromJson(installation.toJson());
    final cancellation = _cancelTest = Completer<SerialDiagnostics?>();
    return _enqueue(() async {
      _SerialSession? temporary;
      try {
        if (_disposed || cancellation.isCompleted) return null;
        final current = _session;
        if (current != null &&
            current.installation.serialParameters == target.serialParameters &&
            current.acceptsDiagnostic) {
          return await current.waitForDiagnostic(cancellation.future);
        }
        if (current != null) {
          _session = null;
          state.publish(
            const IndicatorReading(
              physical: true,
              status: IndicatorConnectionStatus.connecting,
              error: 'Sessão operacional pausada para teste de conexão.',
            ),
          );
          await current.stop();
        }
        if (_disposed || cancellation.isCompleted) return null;
        temporary = _SerialSession(
          target,
          _transportFactory,
          _now,
          retry: false,
        );
        temporary.start();
        return await temporary.waitForDiagnostic(cancellation.future);
      } finally {
        await temporary?.stop();
        _cancelTest = null;
        if (!cancellation.isCompleted) _startOperational();
      }
    });
  }

  void _startOperational() {
    final target = _target;
    if (_disposed || _session != null || target == null) return;
    final session = _SerialSession(
      target,
      _transportFactory,
      _now,
      retry: true,
    );
    _session = session;
    session.onReading = (reading) {
      if (!_disposed && identical(_session, session)) state.publish(reading);
    };
    session.start();
  }

  void _cancelDiagnostic() {
    final test = _cancelTest;
    if (test != null && !test.isCompleted) test.complete(null);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> close() {
    _disposed = true;
    _cancelDiagnostic();
    final previous = _session;
    _session = null;
    return _enqueue(() async => previous?.stop());
  }
}

class _SerialSession {
  _SerialSession(
    this.installation,
    this._factory,
    this._now, {
    required this.retry,
  }) : _framer = ToledoContinuousFramer(
         checksum: installation.checksum,
         weightScale: installation.toledoWeightScale,
       );

  final IndicatorInstallation installation;
  final IndicatorTransport Function() _factory;
  final Duration Function() _now;
  final bool retry;
  final ToledoContinuousFramer _framer;
  void Function(IndicatorReading)? onReading;
  final _updates = StreamController<SerialDiagnostics>.broadcast();
  final _stopping = Completer<void>();
  Completer<void>? _attemptDone;
  Timer? _timeout, _retryDelay;
  Future<void>? _running;
  bool _portOpen = false;
  int _generation = 0, _bytes = 0, _valid = 0, _invalid = 0;
  int _attemptBytes = 0;
  String? _attemptRejection;
  bool _recovering = false;
  static const _sampleLimit = 96;
  List<int> _sample = [];
  String? _lastInvalid;
  Duration? _lastValidTick;
  IndicatorReading? _lastValidReading;
  IndicatorReading _reading = const IndicatorReading();

  int get generation => _generation;
  bool get acceptsDiagnostic =>
      _reading.status == IndicatorConnectionStatus.awaitingData ||
      _reading.status == IndicatorConnectionStatus.connecting ||
      freshReading != null;
  Duration get _frameTimeout => Duration(milliseconds: installation.timeoutMs);
  IndicatorReading? get freshReading {
    final tick = _lastValidTick;
    return !_stopping.isCompleted &&
            _reading.connected &&
            _reading.weight != null &&
            tick != null &&
            _now() - tick < _frameTimeout
        ? _reading
        : null;
  }

  SerialDiagnostics get diagnostics => SerialDiagnostics(
    reading: _reading,
    portOpen: _portOpen,
    bytesReceived: _bytes,
    validFrames: _valid,
    invalidFrames: _invalid,
    sample: List.unmodifiable(_sample),
    lastValidAt: _lastValidReading?.readAt,
    lastValidReading: _lastValidReading,
    lastInvalid: _lastInvalid,
    observedAt: DateTime.now(),
  );

  void start() => _running = _run();

  Future<void> stop() async {
    if (!_stopping.isCompleted) {
      _stopping.complete();
      _completeAttempt();
      _timeout?.cancel();
      _retryDelay?.cancel();
    }
    await _running;
    await _updates.close();
  }

  Future<SerialDiagnostics?> waitForDiagnostic(
    Future<SerialDiagnostics?> cancel,
  ) async {
    bool ready(SerialDiagnostics data) => switch (data.reading.status) {
      IndicatorConnectionStatus.error ||
      IndicatorConnectionStatus.noCommunication => true,
      IndicatorConnectionStatus.connected =>
        data.reading.weight != null && freshReading != null,
      _ => false,
    };
    final current = diagnostics;
    if (ready(current)) return current;
    final result = Completer<SerialDiagnostics>();
    final subscription = _updates.stream.listen((value) {
      if (ready(value) && !result.isCompleted) result.complete(value);
    });
    try {
      return await Future.any<SerialDiagnostics?>([result.future, cancel]);
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _run() async {
    while (!_stopping.isCompleted) {
      _attemptDone = Completer<void>();
      _framer.reset();
      _lastValidTick = null;
      _attemptBytes = 0;
      _attemptRejection = null;
      IndicatorTransport? transport;
      StreamSubscription<List<int>>? subscription;
      try {
        _status(IndicatorConnectionStatus.connecting);
        transport = _factory();
        await transport.connect(installation);
        if (_stopping.isCompleted) break;
        _portOpen = true;
        _status(IndicatorConnectionStatus.awaitingData);
        _watchTimeout();
        subscription = transport.bytes.listen(
          _onBytes,
          onError: (Object error) =>
              _fail(IndicatorConnectionStatus.error, error.toString()),
          onDone: () => _fail(
            IndicatorConnectionStatus.noCommunication,
            'Leitor serial desconectado.',
          ),
        );
        await _attemptDone!.future;
      } catch (error) {
        _fail(IndicatorConnectionStatus.error, error.toString());
      } finally {
        _timeout?.cancel();
        await subscription?.cancel();
        try {
          await transport?.disconnect();
        } finally {
          _portOpen = false;
        }
      }
      if (!retry || _stopping.isCompleted) return;
      final delay = Completer<void>();
      _retryDelay = Timer(
        Duration(milliseconds: math.max(250, installation.reconnectIntervalMs)),
        delay.complete,
      );
      await Future.any([delay.future, _stopping.future]);
    }
  }

  void _onBytes(List<int> bytes) {
    if (_stopping.isCompleted || _attemptDone!.isCompleted) return;
    // Um frame que chegou depois do prazo começa outra sessão de comunicação.
    final tick = _lastValidTick;
    if (tick != null && _now() - tick >= _frameTimeout) {
      _onTimeout();
      return;
    }
    _bytes += bytes.length;
    _attemptBytes += bytes.length;
    _sample = [
      ..._sample,
      ...bytes.skip(math.max(0, bytes.length - _sampleLimit)),
    ];
    _sample = _sample.skip(math.max(0, _sample.length - _sampleLimit)).toList();
    var next = _reading;
    _framer.add(
      bytes,
      onReading: (value) {
        _valid++;
        _lastValidTick = _now();
        _recovering = false;
        _watchTimeout();
        next = _lastValidReading = IndicatorReading(
          physical: true,
          source: _source,
          status: IndicatorConnectionStatus.connected,
          weight: value.weight,
          unit: value.unit.label,
          gross: value.gross,
          stable: value.stable,
          wholeKg: value.wholeKg,
          decimalPlaces: value.decimalPlaces,
          readAt: DateTime.now(),
        );
      },
      onInvalid: (error) {
        _invalid++;
        _lastInvalid = error;
        _attemptRejection = error;
        next = IndicatorReading(
          physical: true,
          source: _source,
          status: next.status,
          error: error,
          recovering: _recovering,
        );
      },
    );
    _publish(next);
  }

  String get _source => '${installation.modelCode} · ${installation.comPort}';

  void _watchTimeout() {
    _timeout?.cancel();
    _timeout = Timer(_frameTimeout, _onTimeout);
  }

  void _onTimeout() {
    if (_framer.awaitingChecksum) {
      _invalid++;
      _lastInvalid = _attemptRejection = 'Checksum ausente no prazo.';
    }
    final error = _attemptRejection;
    _fail(
      IndicatorConnectionStatus.noCommunication,
      _attemptBytes == 0
          ? 'Porta aberta, nenhum byte recebido.'
          : error == null
          ? 'Nenhum frame MT Continuous válido no prazo. Confira o formato e o checksum.'
          : 'Nenhum frame válido no prazo. Última rejeição: $error',
    );
  }

  void _fail(IndicatorConnectionStatus status, String error) {
    if (_stopping.isCompleted || _attemptDone!.isCompleted) return;
    _generation++;
    _recovering = true;
    _status(status, error);
    _completeAttempt();
  }

  void _completeAttempt() {
    final attempt = _attemptDone;
    if (attempt != null && !attempt.isCompleted) attempt.complete();
  }

  void _status(IndicatorConnectionStatus status, [String? error]) => _publish(
    IndicatorReading(
      physical: true,
      source: _source,
      status: status,
      error: error,
      recovering: _recovering,
    ),
  );

  void _publish(IndicatorReading reading) {
    _reading = reading;
    onReading?.call(reading);
    if (_updates.hasListener) _updates.add(diagnostics);
  }
}
