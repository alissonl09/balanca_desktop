import 'libra_api_client.dart';

/// Campos informados pelo contrato. Não presume carreta ou pesos de pesagem.
class PreTicketDto {
  PreTicketDto.fromJson(Map<String, dynamic> json)
    : tipoDocumento = _text(json['tipoDocumento']),
      nota = _text(json['nota']),
      emissor = _text(json['emissor']),
      motorista = _text(json['motorista']),
      transportador = _text(json['transportador']),
      quantidadeTotal = _number(json['quantidadeTotal']),
      embalagem = _text(json['embalagem']),
      deposito = _text(json['deposito']),
      sequencia = _text(json['sequencia']),
      tipoOperacao = _text(json['tipoOperacao']),
      numeroTicketOrigem = _text(json['numeroTicketOrigem']),
      codigoUnidadeOrigem = _text(json['codigoUnidadeOrigem']),
      pesoLiquidoOrigem = _number(json['pesoLiquidoOrigem']);

  final String tipoDocumento,
      nota,
      emissor,
      motorista,
      transportador,
      embalagem,
      deposito,
      sequencia,
      tipoOperacao,
      numeroTicketOrigem,
      codigoUnidadeOrigem;
  final num? quantidadeTotal, pesoLiquidoOrigem;

  static String _text(Object? value) {
    if (value == null) return '';
    if (value is String || value is num) return '$value';
    if (value is List) return value.map(_text).join('; ');
    throw const LibraException(LibraFailure.response);
  }

  static num? _number(Object? value) {
    if (value == null) return null;
    final number = value is num ? value : num.tryParse('$value');
    if (number == null || !number.isFinite) {
      throw const LibraException(LibraFailure.response);
    }
    return number;
  }

  static List<PreTicketDto> decode(Object? json) {
    if (json == null) return const [];
    if (json is Map<String, dynamic> && json.isEmpty) return const [];
    final rows = json is List ? json : [json];
    return rows
        .map((row) {
          if (row is! Map<String, dynamic> ||
              !row.keys.any(
                const {
                  'tipoDocumento',
                  'nota',
                  'motorista',
                  'transportador',
                  'emissor',
                  'quantidadeTotal',
                  'sequencia',
                }.contains,
              )) {
            throw const LibraException(LibraFailure.response);
          }
          return PreTicketDto.fromJson(row);
        })
        .toList(growable: false);
  }

  static Map<String, String> operationValues(List<PreTicketDto> tickets) {
    String join(String Function(PreTicketDto) field) =>
        tickets.map(field).where((v) => v.isNotEmpty).toSet().join('; ');
    final quantities = tickets.map((t) => t.quantidadeTotal).whereType<num>();
    return <String, String>{
      'Motorista': join((t) => t.motorista),
      'Transportador': join((t) => t.transportador),
      'Emissor(es)': join((t) => t.emissor),
      'Depósito': join((t) => t.deposito),
      'Tipo do documento': join((t) => t.tipoDocumento),
      'Nº Nota(s) / Documento(s)': join((t) => t.nota),
      'Peso N.F. (Kg)': quantities.isEmpty
          ? ''
          : '${quantities.fold<num>(0, (a, b) => a + b)}',
      'Embalagem': join((t) => t.embalagem),
    }..removeWhere((_, value) => value.isEmpty);
  }
}
