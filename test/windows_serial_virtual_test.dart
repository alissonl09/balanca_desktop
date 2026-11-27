import 'dart:io';

import 'package:balanca_desktop/core/indicators/indicator_driver.dart';
import 'package:balanca_desktop/core/indicators/indicator_models.dart';
import 'package:balanca_desktop/core/indicators/serial_indicator_service.dart';
import 'package:balanca_desktop/core/indicators/windows_serial_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/serial_indicator_fake.dart';

void main() {
  final receive = Platform.environment['BALANCA_SERIAL_VIRTUAL_RX'];
  final transmit = Platform.environment['BALANCA_SERIAL_VIRTUAL_TX'];

  test(
    'Win32 recebe MT Continuous 4800,E,7,2 pelo com0com e reconecta',
    skip: !Platform.isWindows || receive == null || transmit == null,
    () async {
      final rx = receive!;
      final tx = transmit!;
      await verifyVirtualPorts(rx, tx);
      final ports = await WindowsSerialTransport.availablePorts();
      expect(ports, containsAll([rx, tx]));

      final state = MemoryIndicatorState();
      addTearDown(state.dispose);
      final service = SerialIndicatorService(state);
      addTearDown(service.close);
      final item = serialInstallation(
        port: rx,
        timeout: 2500,
        retry: 500,
        checksum: true,
      );
      service.configure(
        station: 'bancada virtual',
        mode: IndicatorMode.real,
        installation: item,
      );
      await waitUntil(() => service.diagnostics?.portOpen == true, state);

      final occupied = WindowsSerialTransport();
      try {
        await expectLater(
          occupied.connect(item),
          throwsA(predicate((error) => error.toString().contains('ocupada'))),
        );
      } finally {
        await occupied.disconnect();
      }

      await send(tx, toledoFrame(check: 1), repeat: 6);
      await waitUntil(() => state.reading.connected, state);
      final capture = service.capture();
      expect(capture.reading.weight, 5700.9);
      expect(capture.reading.wholeKg, 5700);
      expect(service.diagnostics!.validFrames, greaterThanOrEqualTo(1));

      await waitUntil(
        () => state.reading.status == IndicatorConnectionStatus.noCommunication,
        state,
      );
      expect(state.reading.weight, isNull);
      expect(service.canConfirm(capture), isFalse);
      await waitUntil(() => service.diagnostics?.portOpen == true, state);
      await send(tx, toledoFrame(weight: '     0', check: 0x56), repeat: 5);
      await waitUntil(() => state.reading.connected, state);
      expect(state.reading.weight, 0);
    },
  );

  test(
    'Win32 recebe a linha do simulador legado, sem interpretá-la como peso',
    skip: !Platform.isWindows || receive == null || transmit == null,
    () async {
      final rx = receive!;
      final tx = transmit!;
      await verifyVirtualPorts(rx, tx);
      final state = MemoryIndicatorState();
      addTearDown(state.dispose);
      final service = SerialIndicatorService(state);
      addTearDown(service.close);
      final item = serialInstallation(port: rx, timeout: 2500);
      service.configure(
        station: 'bancada virtual',
        mode: IndicatorMode.real,
        installation: item,
      );
      await waitUntil(() => service.diagnostics?.portOpen == true, state);
      final testResult = service.testConnection(item);
      await send(tx, 'PB: 5700.9kg PL: 5700.9kg T:      0kg\r\n'.codeUnits);
      final result = (await testResult)!;
      expect(result.bytesReceived, greaterThan(0));
      expect(result.validFrames, 0);
      expect(result.reading.status, IndicatorConnectionStatus.noCommunication);
      expect(result.ascii, contains('PB: 5700.9kg'));
      expect(service.capture, throwsFormatException);
    },
  );
}

Future<void> verifyVirtualPorts(String rx, String tx) async {
  final comName = RegExp(r'^COM[1-9][0-9]*$');
  expect(comName.hasMatch(rx) && comName.hasMatch(tx) && rx != tx, isTrue);
  final registry = await Process.run('reg.exe', [
    'query',
    r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM',
  ]);
  expect(registry.exitCode, 0, reason: registry.stderr.toString());
  final virtual = RegExp(r'\\Device\\com0com[^\s]*\s+REG_SZ\s+(COM\d+)');
  final ports = virtual.allMatches(registry.stdout as String).map((m) => m[1]);
  expect(ports, containsAll([rx, tx]));
}

Future<void> waitUntil(
  bool Function() condition,
  MemoryIndicatorState state,
) async {
  final deadline = Stopwatch()..start();
  while (!condition() && deadline.elapsed < const Duration(seconds: 6)) {
    if (state.reading.status == IndicatorConnectionStatus.error) {
      fail(state.reading.error ?? 'Erro serial sem diagnóstico.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
  expect(
    condition(),
    isTrue,
    reason: state.reading.error ?? state.reading.status.label,
  );
}

Future<void> send(String port, List<int> bytes, {int repeat = 1}) async {
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    '''
\$ErrorActionPreference = 'Stop'
\$p = [System.IO.Ports.SerialPort]::new('$port', 4800, 'Even', 7, 'Two')
[byte[]]\$frame = @(${bytes.join(',')})
try {
  \$p.Open()
  for (\$i = 0; \$i -lt $repeat; \$i++) {
    \$p.Write(\$frame, 0, \$frame.Length)
    Start-Sleep -Milliseconds 80
  }
} finally {
  \$p.Dispose()
}
''',
  ]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
}
