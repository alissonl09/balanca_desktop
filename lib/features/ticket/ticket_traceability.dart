/// Substituir pela regra oficial de rastreabilidade quando ela for definida.
/// O número atual é somente um identificador de prévia, sem garantia global.
typedef TicketIdentifierFactory = String? Function(String? ticketNumber);

String? previewTicketIdentifier(String? ticketNumber) =>
    ticketNumber == null || ticketNumber.trim().isEmpty
    ? null
    : ticketNumber.trim();

/// Codificação Code 39 (barras e espaços em módulos estreitos/largos).
/// Tabela da simbologia conferida na implementação de referência ZXing:
/// https://github.com/zxing/zxing/blob/master/core/src/main/java/com/google/zxing/oned/Code39Reader.java
/// Sem dependência nativa, checksum opcional ou regra de composição de ID.
List<bool> encodeCode39(String value) {
  const alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. \$/+%';
  const patterns = [
    0x034,
    0x121,
    0x061,
    0x160,
    0x031,
    0x130,
    0x070,
    0x025,
    0x124,
    0x064,
    0x109,
    0x049,
    0x148,
    0x019,
    0x118,
    0x058,
    0x00d,
    0x10c,
    0x04c,
    0x01c,
    0x103,
    0x043,
    0x142,
    0x013,
    0x112,
    0x052,
    0x007,
    0x106,
    0x046,
    0x016,
    0x181,
    0x0c1,
    0x1c0,
    0x091,
    0x190,
    0x0d0,
    0x085,
    0x184,
    0x0c4,
    0x0a8,
    0x0a2,
    0x08a,
    0x02a,
  ];
  if (value.isEmpty ||
      value.split('').any((char) => !alphabet.contains(char))) {
    throw const FormatException('Conteúdo não compatível com Code 39.');
  }
  final modules = <bool>[...List.filled(10, false)]; // Zona de silêncio.
  final encodings = [
    0x094,
    ...value.split('').map((char) => patterns[alphabet.indexOf(char)]),
    0x094,
  ];
  for (var index = 0; index < encodings.length; index++) {
    for (var segment = 0; segment < 9; segment++) {
      final wide = (encodings[index] & (1 << (8 - segment))) != 0;
      modules.addAll(List.filled(wide ? 3 : 1, segment.isEven));
    }
    if (index < encodings.length - 1) modules.add(false);
  }
  modules.addAll(List.filled(10, false));
  return List.unmodifiable(modules);
}
