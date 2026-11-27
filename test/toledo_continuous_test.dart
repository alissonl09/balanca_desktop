import 'package:balanca_desktop/core/indicators/toledo_continuous.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/serial_indicator_fake.dart';

void main() {
  const parser = ToledoContinuousParser(checksum: false);

  test('peso e tara em campos independentes e escala de 10² a 10⁻⁵', () {
    const values = [
      1234500,
      123450,
      12345,
      1234.5,
      123.45,
      12.345,
      1.2345,
      0.12345,
    ];
    for (var scale = 0; scale < values.length; scale++) {
      final decoded = parser.parse(
        toledoFrame(a: 0x28 | scale, weight: ' 12345', tare: ' 10000'),
      );
      expect(decoded.weight, values[scale]);
      expect(decoded.indicated, 12345);
      expect(decoded.tareDigits, 10000);
    }
    final decimal = parser.parse(toledoFrame(tare: ' 01235'));
    expect(decimal.weight, 5700.9);
    expect(decimal.wholeKg, 5700);
    expect(decimal.tare, 123.5);
    expect(decimal.gross, isTrue);
    expect(decimal.stable, isTrue);
    final zero = parser.parse(toledoFrame(weight: '     0'));
    expect(zero.weight, 0);
    expect(zero.stable, isTrue);
  });

  test('sinal, movimento, peso líquido, unidade e truncamento exato em kg', () {
    final net = parser.parse(toledoFrame(b: 0x3b));
    expect(net.gross, isFalse);
    expect(net.stable, isFalse);
    expect(net.weight, -5700.9);
    expect(net.wholeKg, -5700);
    final lb = parser.parse(toledoFrame(b: 0x20, c: 0x28));
    expect(lb.unit, ToledoUnit.lb);
    expect(lb.wholeKg, 2585);
    final grams = parser.parse(toledoFrame(c: 0x21, a: 0x2a, weight: '  1000'));
    expect(grams.unit, ToledoUnit.gram);
    expect(grams.wholeKg, 1);
    final tonnes = parser.parse(
      toledoFrame(a: 0x2f, c: 0x22, weight: '   100'),
    );
    expect(tonnes.unit, ToledoUnit.tonne);
    expect(tonnes.weight, .001);
    expect(tonnes.wholeKg, 1);
  });

  test(
    'rejeita status, faixa, unidade ou conteúdo sem interpretação segura',
    () {
      for (final frame in [
        toledoFrame(a: 0),
        toledoFrame(a: 0x22),
        toledoFrame(b: 0x34),
        toledoFrame(b: 0x70),
        toledoFrame(b: 0xb0),
        toledoFrame(c: 0),
        toledoFrame(c: 0x30),
        for (final unit in [3, 4, 5, 6, 7]) toledoFrame(c: 0x20 | unit),
        toledoFrame(weight: '1 2345'),
        toledoFrame(weight: '      '),
        toledoFrame(weight: ' 1234\n'),
        toledoFrame(tare: '    -1'),
        toledoFrame(tare: '  12.0'),
        toledoFrame()..last = 0x0a,
      ]) {
        expect(() => parser.parse(frame), throwsFormatException);
      }
    },
  );

  test(
    'checksum de 7 bits distingue ausência, valor incorreto e valor correto',
    () {
      const withChecksum = ToledoContinuousParser(checksum: true);
      final base = toledoFrame();
      // Soma 639 (0x27F), complemento de dois em sete bits 0x01.
      const expected = 0x01;
      expect(ToledoContinuousParser.calculateChecksum(base), expected);
      expect(withChecksum.parse([...base, expected]).weight, 5700.9);
      expect(() => withChecksum.parse(base), throwsFormatException);
      expect(
        () => withChecksum.parse([...base, expected ^ 1]),
        throwsFormatException,
      );
      expect(() => parser.parse([...base, expected]), throwsFormatException);
    },
  );

  test(
    'fragmentação em cada posição, ruído e múltiplos frames no mesmo evento',
    () {
      for (final checksum in [false, true]) {
        final base = toledoFrame();
        final frame = [...base, if (checksum) 0x01];
        for (var i = 0; i <= frame.length; i++) {
          final framer = ToledoContinuousFramer(checksum: checksum);
          final weights = <ToledoWeight>[];
          final invalid = <String>[];
          void add(List<int> bytes) =>
              framer.add(bytes, onReading: weights.add, onInvalid: invalid.add);
          add([...List.filled(10000, 0xff), ...frame.take(i)]);
          add([...frame.skip(i), 0xff, ...frame, ...frame]);
          expect(invalid, isEmpty, reason: 'checksum=$checksum, corte=$i');
          expect(weights.map((weight) => weight.weight), [
            5700.9,
            5700.9,
            5700.9,
          ]);
        }
      }
    },
  );

  test('ressincroniza após STX prematuro, CR inválido e checksum faltante', () {
    final good = toledoFrame(check: 0x01);
    final framer = ToledoContinuousFramer(checksum: true);
    final valid = <ToledoWeight>[];
    final invalid = <String>[];
    framer.add(
      [2, 0x2b, ...toledoFrame(), ...good, ...toledoFrame(check: 3), ...good],
      onReading: valid.add,
      onInvalid: invalid.add,
    );
    expect(valid, hasLength(2));
    expect(invalid, hasLength(3));
    expect(invalid[1], 'Checksum inválido.');
    expect(invalid[2], 'Checksum inválido.');

    invalid.clear();
    final standalone = ToledoContinuousFramer(checksum: false);
    standalone.add(
      [...(toledoFrame()..last = 10), ...toledoFrame()],
      onReading: valid.add,
      onInvalid: invalid.add,
    );
    expect(valid, hasLength(3));
    expect(invalid, hasLength(1));
  });

  test('0x02 é aceito quando é o checksum calculado', () {
    const parser = ToledoContinuousParser(checksum: true);
    final base = toledoFrame(weight: '965555', tare: '980000');
    final crc = ToledoContinuousParser.calculateChecksum(base);
    expect(crc, 2);
    final frame = [...base, crc];
    final framer = ToledoContinuousFramer(checksum: true);
    final weights = <ToledoWeight>[];
    framer.add([...frame, ...frame], onReading: weights.add, onInvalid: fail);
    expect(weights, hasLength(2));
    expect(parser.parse(frame).weight, 96555.5);
  });

  test('0x0D após o CR estrutural também pode ser checksum', () {
    final frame = toledoFrame(weight: '  7990', check: 0x0d);
    final framer = ToledoContinuousFramer(checksum: true);
    final weights = <ToledoWeight>[];
    for (final byte in [...frame, ...toledoFrame(check: 1)]) {
      framer.add([byte], onReading: weights.add, onInvalid: fail);
    }
    expect(weights.map((weight) => weight.weight), [799, 5700.9]);
  });
}
