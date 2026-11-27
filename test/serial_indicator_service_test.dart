import 'dart:async';

import 'package:balanca_desktop/core/indicators/indicator_driver.dart';
import 'package:balanca_desktop/core/indicators/indicator_models.dart';
import 'package:balanca_desktop/core/indicators/serial_indicator_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/serial_indicator_fake.dart';

void main() {
  test('publica zero, distingue movimento e exige leitura bruta recente', () async {
    final state = MemoryIndicatorState();
    addTearDown(state.dispose);
    final bus = FakeSerialBus();
    final clock = Stopwatch()..start();
    var offset = Duration.zero;
    final service = SerialIndicatorService(
      state,
      transportFactory: bus.create,
      monotonicNow: () => clock.elapsed + offset,
    );
    addTearDown(service.close);
    service.configure(
      station: 'A',
      mode: IndicatorMode.real,
      installation: serialInstallation(timeout: 100, retry: 300),
    );
    await flushSerial();
    expect(state.reading.status, IndicatorConnectionStatus.awaitingData);
    expect(state.reading.allowsManualContingency, isFalse);
    expect(service.diagnostics!.portOpen, isTrue);
    expect(service.capture, throwsFormatException);

    bus.current.send(toledoFrame(weight: '     0'));
    expect(state.reading.weight, 0);
    expect(state.reading.connected, isTrue);
    expect(service.capture, throwsFormatException);
    bus.current.send(toledoFrame(b: 0x38));
    expect(state.reading.stable, isFalse);
    expect(state.reading.allowsManualContingency, isFalse);
    expect(service.capture, throwsFormatException);
    bus.current.send(toledoFrame(b: 0x31));
    expect(state.reading.gross, isFalse);
    expect(service.capture, throwsFormatException);
    bus.current.send(toledoFrame());
    final capture = service.capture();
    expect(capture.reading.wholeKg, 5700);
    final readAt = capture.reading.readAt;
    bus.current.send(toledoFrame(weight: ' 98105'));
    expect(state.reading.wholeKg, 9810);
    expect(capture.reading.readAt, readAt);
    expect(service.canConfirm(capture), isTrue);

    // Mesmo antes do disparo do timer, o relógio monotônico invalida a captura.
    offset = const Duration(milliseconds: 100);
    expect(service.capture, throwsFormatException);
    expect(service.canConfirm(capture), isFalse);
    await flushSerial(130);
    expect(state.reading.status, IndicatorConnectionStatus.noCommunication);
    expect(state.reading.weight, isNull);
    expect(state.reading.allowsManualContingency, isTrue);
    expect(bus.openPorts, isEmpty);
    await flushSerial(300);
    expect(bus.attempts, hasLength(2));
    expect(state.reading.allowsManualContingency, isTrue);
    expect(state.reading.status, IndicatorConnectionStatus.awaitingData);
    bus.current.send(toledoFrame());
    expect(service.canConfirm(capture), isFalse);
    expect(service.capture().reading.weight, 5700.9);
    await service.close();
    expect(bus.openPorts, isEmpty);
    expect(bus.attempts.every((attempt) => attempt.released), isTrue);
  });

  test('diagnóstico diferencia ausência de dados, rejeição, porta e erro de driver', () async {
    final state = MemoryIndicatorState();
    addTearDown(state.dispose);
    final bus = FakeSerialBus();
    final service = SerialIndicatorService(state, transportFactory: bus.create);
    addTearDown(service.close);
    final parameters = serialInstallation(timeout: 150);
    var result = service.testConnection(parameters);
    var diagnostic = (await result)!;
    expect(diagnostic.portOpen, isTrue);
    expect(diagnostic.bytesReceived, 0);
    expect(diagnostic.reading.error, 'Porta aberta, nenhum byte recebido.');

    result = service.testConnection(parameters..checksum = true);
    await flushSerial();
    bus.current.send(toledoFrame());
    diagnostic = (await result)!;
    expect(diagnostic.bytesReceived, 17);
    expect(diagnostic.invalidFrames, 1);
    expect(diagnostic.lastInvalid, 'Checksum ausente no prazo.');
    expect(diagnostic.hex, startsWith('02 2B 30 20'));
    expect(diagnostic.ascii, startsWith('<STX>'));
    expect(diagnostic.ascii, endsWith('<CR>'));

    result = service.testConnection(parameters);
    await flushSerial();
    final zero = toledoFrame(weight: '     0', check: 0x56);
    bus.current.send([...zero, ...(zero.toList()..last = 0)]);
    diagnostic = (await result)!;
    expect(
      diagnostic.reading.status,
      IndicatorConnectionStatus.noCommunication,
    );
    expect(diagnostic.reading.weight, isNull);
    expect(diagnostic.lastValidReading?.weight, 0);
    expect(diagnostic.lastValidReading?.readAt, diagnostic.lastValidAt);
    expect(diagnostic.lastInvalid, 'Checksum inválido.');

    for (final reason in [
      'Porta inexistente',
      'Porta ocupada',
      'Acesso negado',
      'Falha no driver',
    ]) {
      bus.errors['COM99'] = reason;
      result = service.testConnection(serialInstallation(port: 'COM99'));
      diagnostic = (await result)!;
      expect(diagnostic.portOpen, isFalse);
      expect(diagnostic.reading.status, IndicatorConnectionStatus.error);
      expect(diagnostic.reading.error, contains(reason));
    }
    expect(state.reading.physical, isFalse);
    expect(bus.openPorts, isEmpty);
    await service.close();
  });

  test(
    'reutiliza sessão equivalente e suspende/restaura para outro teste',
    () async {
      final state = MemoryIndicatorState();
      addTearDown(state.dispose);
      final bus = FakeSerialBus();
      final service = SerialIndicatorService(
        state,
        transportFactory: bus.create,
      );
      addTearDown(service.close);
      final operating = serialInstallation();
      service.configure(
        station: 'A',
        mode: IndicatorMode.real,
        installation: operating,
      );
      await flushSerial();
      final reused = service.testConnection(operating);
      await flushSerial();
      bus.current.send([...List.filled(1024, 65), ...toledoFrame()]);
      final first = (await reused)!;
      expect(first.validFrames, 1);
      expect(first.bytesReceived, 1041);
      expect(first.sample, hasLength(96));
      expect(bus.attempts, hasLength(1));
      final capture = service.capture();

      final other = service.testConnection(
        serialInstallation()
          ..baudRate = 9600
          ..checksum = true,
      );
      await flushSerial();
      expect(service.canConfirm(capture), isFalse);
      expect(bus.current.parameters!.baudRate, 9600);
      bus.current.send(toledoFrame(check: 1));
      expect((await other)!.validFrames, 1);
      await flushSerial();
      expect(bus.events, [
        'open COM12',
        'close COM12',
        'open COM12',
        'close COM12',
        'open COM12',
      ]);
      expect(bus.current.parameters!.baudRate, 4800);
      expect(state.reading.weight, isNull);
      await service.close();
    },
  );

  test('troca de estação durante abertura, cancelamento e descarte', () async {
    final state = MemoryIndicatorState();
    addTearDown(state.dispose);
    final bus = FakeSerialBus()..allowOpening = Completer<void>();
    final service = SerialIndicatorService(state, transportFactory: bus.create);
    addTearDown(() async {
      if (!bus.allowOpening!.isCompleted) bus.allowOpening!.complete();
      await service.close();
    });
    service.configure(
      station: 'A',
      mode: IndicatorMode.real,
      installation: serialInstallation(),
    );
    await flushSerial();
    service.configure(
      station: 'B',
      mode: IndicatorMode.real,
      installation: serialInstallation(port: 'COM13'),
    );
    bus.allowOpening!.complete();
    await flushSerial();
    expect(bus.events, ['open COM12', 'close COM12', 'open COM13']);
    expect(state.reading.source, contains('COM13'));

    final result = service.testConnection(serialInstallation(port: 'COM88'));
    await flushSerial();
    service.configure(station: 'C', mode: IndicatorMode.real);
    expect(await result, isNull);
    await flushSerial();
    expect(bus.openPorts, isEmpty);
    expect(state.reading.status, IndicatorConnectionStatus.disabled);
    await service.close();
    expect(bus.attempts.every((attempt) => attempt.released), isTrue);
  });

  test(
    'erro do leitor libera a porta e descarta frame parcial antes da reconexão',
    () async {
      final state = MemoryIndicatorState();
      addTearDown(state.dispose);
      final bus = FakeSerialBus();
      final service = SerialIndicatorService(
        state,
        transportFactory: bus.create,
      );
      addTearDown(service.close);
      service.configure(
        station: 'A',
        mode: IndicatorMode.real,
        installation: serialInstallation(timeout: 500, retry: 300),
      );
      await flushSerial();
      final frame = toledoFrame();
      bus.current.send(frame.take(10).toList());
      bus.current.fail('Conversor removido');
      expect(state.reading.error, contains('Conversor removido'));
      await flushSerial();
      expect(bus.openPorts, isEmpty);
      await flushSerial(330);
      bus.current.send(frame.skip(10).toList());
      expect(state.reading.connected, isFalse);
      bus.current.send(frame);
      expect(state.reading.connected, isTrue);
      await service.close();
    },
  );
}

Future<void> flushSerial([int milliseconds = 0]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));
