import 'dart:io';
import 'dart:math' as math;

import 'package:balanca_desktop/core/indicators/toledo_continuous.dart';
import 'package:flutter_test/flutter_test.dart';

// Apenas os cinco exemplos transcritos no anexo PRJ2524_AJUSTE_SERIAL_TOLEDO.md.
const _examples = [
  '\x02)0     30    00\r5',
  '\x02)0     40    00\r4',
  "\x02)0    100    00\r'",
  '\x02)0    110    00\r&',
  '\x02)0     00    00\r8',
];

void main() {
  const parser = ToledoContinuousParser(
    checksum: true,
    weightScale: ToledoWeightScale.comToolIntegerKg,
  );
  const standard = ToledoContinuousParser(checksum: true);
  test('cinco frames transcritos do ComTool preservam o campo de peso', () {
    expect(_examples.first.codeUnits, [
      0x02,
      0x29,
      0x30,
      0x20,
      0x20,
      0x20,
      0x20,
      0x20,
      0x33,
      0x30,
      0x20,
      0x20,
      0x20,
      0x20,
      0x30,
      0x30,
      0x0d,
      0x35,
    ]);
    final readings = _replay(_examples.join().codeUnits, chunkSize: 29);
    expect(readings.map((reading) => reading.wholeKg), [30, 40, 100, 110, 0]);
    expect(readings.every((reading) => reading.tare == 0), isTrue);
    expect(
      readings.every((reading) => reading.stable && reading.gross),
      isTrue,
    );
    expect(standard.parse(_examples.first.codeUnits).wholeKg, 300);
  });

  test('perfil da instalação aplica os bits documentados e exige a escala da captura', () {
    final moving = _examples.first.codeUnits.toList()..[2] = 0x38;
    moving[17] = ToledoContinuousParser.calculateChecksum(moving.take(17));
    expect(parser.parse(moving).wholeKg, 30);
    expect(parser.parse(moving).stable, isFalse);
    for (final (index, replacement) in [(1, 0x2a), (2, 0x20), (2, 0x34)]) {
      final incompatible = _examples.first.codeUnits.toList()
        ..[index] = replacement;
      incompatible[17] = ToledoContinuousParser.calculateChecksum(
        incompatible.take(17),
      );
      expect(() => parser.parse(incompatible), throwsFormatException);
    }
  });

  final fixture = File(
    Platform.environment['TOLEDO_COMTOOL_FIXTURE'] ?? 'leitura_peso.txt',
  );
  test(
    'replay do arquivo binário original do ComTool',
    skip: fixture.existsSync() ? false : 'leitura_peso.txt indisponível',
    () {
      final bytes = fixture.readAsBytesSync();
      expect(bytes, hasLength(18918));
      final frames = _replay(bytes, chunkSize: 257);
      expect(frames, hasLength(1051));
      expect(frames.any((reading) => reading.stable), isTrue);
      expect(frames.any((reading) => !reading.stable), isTrue);
      expect(frames.every((reading) => reading.unit == ToledoUnit.kg), isTrue);
      final distribution = <int, int>{};
      for (final reading in frames) {
        distribution.update(reading.wholeKg, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(distribution, {
        0: 547,
        10: 81,
        20: 7,
        30: 23,
        40: 4,
        100: 299,
        110: 90,
      });
      final weights = frames.map((reading) => reading.wholeKg).toList();
      expect(weights.first, 30);
      final first40 = weights.indexOf(40);
      expect(first40, greaterThan(0));
      expect(weights.indexOf(30, first40 + 1), greaterThan(first40));
    },
  );
}

List<ToledoWeight> _replay(List<int> bytes, {required int chunkSize}) {
  final framer = ToledoContinuousFramer(
    checksum: true,
    weightScale: ToledoWeightScale.comToolIntegerKg,
  );
  final readings = <ToledoWeight>[];
  final errors = <String>[];
  for (var start = 0; start < bytes.length; start += chunkSize) {
    framer.add(
      bytes.sublist(start, math.min(start + chunkSize, bytes.length)),
      onReading: readings.add,
      onInvalid: errors.add,
    );
  }
  expect(errors, isEmpty);
  return readings;
}
