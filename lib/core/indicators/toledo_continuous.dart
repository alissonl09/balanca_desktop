import 'dart:convert';

enum ToledoWeightScale {
  standard('Escala padrão Toledo'),
  comToolIntegerKg('Captura ComTool (kg inteiros)');

  const ToledoWeightScale(this.label);
  final String label;
}

/// IND560 Technical Manual, D-3–D-6, and IND570 User's Guide, C.6.1.
enum ToledoUnit {
  kg('kg', 1, 1),
  lb('lb', 45359237, 100000000),
  gram('g', 1, 1000),
  tonne('t', 1000, 1);

  const ToledoUnit(this.label, this.kgNumerator, this.kgDenominator);
  final String label;
  final int kgNumerator, kgDenominator;
}

class ToledoWeight {
  const ToledoWeight({
    required this.indicated,
    required this.tareDigits,
    required this.decimalPlaces,
    required this.unit,
    required this.gross,
    required this.stable,
  });

  final int indicated, tareDigits, decimalPlaces;
  final ToledoUnit unit;
  final bool gross, stable;
  static const _powersOfTen = [1, 10, 100, 1000, 10000, 100000];

  int get _multiplier => decimalPlaces < 0 ? _powersOfTen[-decimalPlaces] : 1;
  int get _divisor => decimalPlaces > 0 ? _powersOfTen[decimalPlaces] : 1;
  double get weight => indicated * _multiplier / _divisor;
  double get tare => tareDigits * _multiplier / _divisor;
  int get wholeKg =>
      indicated *
      _multiplier *
      unit.kgNumerator ~/
      (_divisor * unit.kgDenominator);
}

class ToledoContinuousParser {
  const ToledoContinuousParser({
    required this.checksum,
    this.weightScale = ToledoWeightScale.standard,
  });

  final bool checksum;
  final ToledoWeightScale weightScale;
  static const stx = 0x02;
  static const cr = 0x0d;
  static const baseLength = 17;
  static final _numericField = RegExp(r'^ *[0-9]+$');

  int get frameLength => baseLength + (checksum ? 1 : 0);

  static int calculateChecksum(Iterable<int> bytes) =>
      -bytes.fold<int>(0, (sum, byte) => sum + byte) & 0x7f;

  ToledoWeight parse(List<int> frame) {
    if (checksum && frame.length == baseLength) {
      throw const FormatException('Checksum ausente.');
    }
    if (frame.length != frameLength ||
        frame.first != stx ||
        frame[baseLength - 1] != cr) {
      throw const FormatException('Estrutura MT Continuous inválida.');
    }
    if (checksum && frame.last != calculateChecksum(frame.take(baseLength))) {
      throw const FormatException('Checksum inválido.');
    }
    final [a, b, c] = frame.sublist(1, 4);
    // A e C têm bits fixos 765 = 001. B permite bit 6 (zero não capturado).
    if ((a & 0xe0) != 0x20 ||
        (b & 0xa0) != 0x20 ||
        (c & 0xe0) != 0x20 ||
        (a & 0x18) == 0) {
      throw const FormatException('Palavras de status inválidas.');
    }
    if ((b & 0x04) != 0) {
      throw const FormatException('Peso fora da faixa do indicador.');
    }
    if ((b & 0x40) != 0) {
      throw const FormatException('Indicador ainda sem referência de zero.');
    }
    if ((c & 0x10) != 0) {
      throw const FormatException(
        'Modo de dados expandidos ×10 não suportado.',
      );
    }
    final unit = switch (c & 0x07) {
      0 => (b & 0x10) != 0 ? ToledoUnit.kg : ToledoUnit.lb,
      1 => ToledoUnit.gram,
      2 => ToledoUnit.tonne,
      _ => throw const FormatException('Unidade do indicador não suportada.'),
    };
    final decimalPlaces = switch (weightScale) {
      ToledoWeightScale.standard => (a & 0x07) - 2,
      // Na captura da instalação, o campo já inclui o zero das unidades.
      ToledoWeightScale.comToolIntegerKg
          when checksum && a == 0x29 && unit == ToledoUnit.kg =>
        0,
      ToledoWeightScale.comToolIntegerKg => throw const FormatException(
        'O perfil ComTool requer status A 0x29, peso em kg e checksum.',
      ),
    };
    return ToledoWeight(
      indicated: _digits(frame.sublist(4, 10)) * ((b & 0x02) != 0 ? -1 : 1),
      tareDigits: _digits(frame.sublist(10, 16)),
      decimalPlaces: decimalPlaces,
      unit: unit,
      gross: (b & 0x01) == 0,
      stable: (b & 0x08) == 0,
    );
  }

  int _digits(List<int> bytes) {
    final field = ascii.decode(bytes);
    if (!_numericField.hasMatch(field)) {
      throw const FormatException('Campo de peso ou tara inválido.');
    }
    return int.parse(field.trimLeft());
  }
}

/// Mantém no máximo um frame parcial. O checksum pode ser o próprio STX.
class ToledoContinuousFramer {
  ToledoContinuousFramer({
    required bool checksum,
    ToledoWeightScale weightScale = ToledoWeightScale.standard,
  }) : _parser = ToledoContinuousParser(
         checksum: checksum,
         weightScale: weightScale,
       );

  final ToledoContinuousParser _parser;
  final _pending = <int>[];
  bool get awaitingChecksum =>
      _parser.checksum &&
      _pending.length == ToledoContinuousParser.baseLength &&
      _pending.last == ToledoContinuousParser.cr;
  void reset() => _pending.clear();

  void add(
    List<int> bytes, {
    required void Function(ToledoWeight) onReading,
    required void Function(String) onInvalid,
  }) {
    for (final byte in bytes) {
      if (_pending.isEmpty && byte != ToledoContinuousParser.stx) continue;
      _pending.add(byte);
      if (_pending.length < _parser.frameLength) continue;
      final ToledoWeight reading;
      try {
        reading = _parser.parse(_pending);
      } on FormatException catch (error) {
        // Só procura outro STX depois de rejeitar o candidato completo.
        final next = _pending.indexOf(ToledoContinuousParser.stx, 1);
        if (next < 0) {
          reset();
        } else {
          _pending.removeRange(0, next);
        }
        onInvalid(error.message);
        continue;
      }
      reset();
      onReading(reading);
    }
  }
}
