// Modelos de apresentação do protótipo, independentes dos contratos centrais.
sealed class CatalogDetails {
  const CatalogDetails();
}

class ItemDetails extends CatalogDetails {
  const ItemDetails();
}

enum OperationNature {
  entrada('ENTRADA'),
  saida('SAIDA'),
  interna('INTERNA'),
  outro('OUTRO');

  const OperationNature(this.label);
  final String label;
}

enum ToleranceUnit {
  kg('KG', 'kg'),
  percentual('PERCENTUAL', '%');

  const ToleranceUnit(this.label, this.symbol);
  final String label, symbol;
}

class ToleranceDetails extends CatalogDetails {
  const ToleranceDetails({
    required this.calculates,
    this.unit,
    this.loss,
    this.yield,
    this.receivingWeight,
  });
  final bool calculates;
  final ToleranceUnit? unit;
  final double? loss, yield;
  final bool? receivingWeight;
}

enum AttributeType {
  texto('TEXTO'),
  inteiro('INTEIRO'),
  decimal('DECIMAL'),
  simNao('SIM_NAO'),
  listaValores('LISTA_VALORES'),
  peso('PESO'),
  data('DATA');

  const AttributeType(this.label);
  final String label;
}

enum CollectionPhase {
  opening('Abertura'),
  closing('Fechamento'),
  both('Ambas');

  const CollectionPhase(this.label);
  final String label;
}

typedef AttributeOption = ({String id, String label});

class AttributeDetails extends CatalogDetails {
  AttributeDetails({
    required this.type,
    this.unit,
    this.maxLength,
    this.minimum,
    this.maximum,
    this.precision,
    this.decimalPlaces,
    this.startDate,
    this.endDate,
    Iterable<AttributeOption> options = const [],
  }) : options = List.unmodifiable(options);
  final AttributeType type;
  final String? unit;
  final int? maxLength, precision, decimalPlaces;
  final num? minimum, maximum;
  final DateTime? startDate, endDate;
  final List<AttributeOption> options;
  static final _alphanumeric = RegExp(r'^[\p{L}\p{M}\p{N} ]+$', unicode: true);

  String? get issue {
    if ((maxLength != null && maxLength! < 1) ||
        (precision != null && precision! < 1) ||
        (decimalPlaces != null && decimalPlaces! < 0) ||
        (precision != null &&
            decimalPlaces != null &&
            decimalPlaces! > precision!)) {
      return 'Revise tamanho, precisão ou casas decimais.';
    }
    if (minimum?.isFinite == false ||
        maximum?.isFinite == false ||
        (minimum != null && maximum != null && minimum! > maximum!)) {
      return 'Revise os limites numéricos.';
    }
    if (type == AttributeType.inteiro &&
        [
          minimum,
          maximum,
        ].whereType<num>().any((value) => value != value.round())) {
      return 'Informe limites inteiros.';
    }
    if (startDate != null && endDate != null && endDate!.isBefore(startDate!)) {
      return 'A data final deve ser igual ou posterior à inicial.';
    }
    if (type == AttributeType.listaValores &&
        (options.isEmpty ||
            options.any(
              (option) =>
                  option.id.trim().isEmpty || option.label.trim().isEmpty,
            ) ||
            options.map((option) => option.id.toUpperCase()).toSet().length !=
                options.length)) {
      return 'Informe opções com códigos únicos e descrições.';
    }
    return null;
  }

  bool accepts(Object? value) => switch (type) {
    AttributeType.texto =>
      value is String &&
          value.trim().isNotEmpty &&
          _alphanumeric.hasMatch(value) &&
          (maxLength == null || value.runes.length <= maxLength!),
    AttributeType.inteiro =>
      value is num && _withinBounds(value) && value == value.round(),
    AttributeType.decimal || AttributeType.peso =>
      value is num && _withinBounds(value) && _matchesPrecision(value),
    AttributeType.simNao => value is bool,
    AttributeType.listaValores =>
      value is String && options.any((option) => option.id == value),
    AttributeType.data =>
      value is DateTime &&
          (startDate == null || !value.isBefore(startDate!)) &&
          (endDate == null || !value.isAfter(endDate!)),
  };

  bool _withinBounds(num value) =>
      value.isFinite &&
      (minimum == null || value >= minimum!) &&
      (maximum == null || value <= maximum!);

  bool _matchesPrecision(num value) {
    final parts = value.abs().toString().split('e');
    final magnitude = parts.first.split('.');
    final exponent = parts.length == 2 ? int.parse(parts.last) : 0;
    final digits = magnitude.join().replaceFirst(RegExp(r'^0+'), '');
    final fractional =
        (magnitude.length == 2 ? magnitude.last.length : 0) - exponent;
    final trailingZeros =
        digits.length - digits.replaceFirst(RegExp(r'0+$'), '').length;
    final decimals = fractional > trailingZeros
        ? fractional - trailingZeros
        : 0;
    final integerCount = value.abs() < 1 ? 0 : digits.length - fractional;
    return (decimalPlaces == null || decimals <= decimalPlaces!) &&
        (precision == null ||
            integerCount + (decimalPlaces ?? decimals) <= precision!);
  }
}

typedef AttributeBinding = ({
  String attributeId,
  bool required,
  CollectionPhase phase,
  bool editable,
  bool printOnTicket,
  int order,
  String? productId,
  String? packaging,
});

class OperationDetails extends CatalogDetails {
  OperationDetails({
    required this.nature,
    this.process,
    this.standard,
    this.bag,
    this.bulk,
    Iterable<AttributeBinding> attributes = const [],
  }) : attributes = List.unmodifiable(attributes);

  final OperationNature nature;
  final String? process, standard, bag, bulk;
  final List<AttributeBinding> attributes;
  bool get incompatibleRules =>
      standard != null && (bag != null || bulk != null);
  bool get incompleteRules => standard == null && (bag == null || bulk == null);

  bool get hasContextConflict {
    for (final binding in attributes) {
      if (binding.productId == null || binding.packaging != null) continue;
      if (attributes.any(
        (other) =>
            other.attributeId == binding.attributeId &&
            other.productId == null &&
            other.packaging != null,
      )) {
        return true;
      }
    }
    return false;
  }

  String? get issue {
    if (incompatibleRules) {
      return 'Selecione uma regra padrão ou regras específicas BAG e GRANEL.';
    }
    final contexts = <(String, String?, String?)>{};
    for (final binding in attributes) {
      if (binding.attributeId.isEmpty || binding.order < 1) {
        return 'Informe um atributo e uma ordem de apresentação positiva.';
      }
      if (!contexts.add((
        binding.attributeId,
        binding.productId,
        binding.packaging,
      ))) {
        return 'O mesmo atributo já está associado neste contexto.';
      }
    }
    return null;
  }
}
