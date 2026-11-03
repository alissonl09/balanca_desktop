enum CadastroKind {
  remetentes('Remetentes / Destinatários'),
  transportadoras('Transportadoras'),
  motoristas('Motoristas'),
  placas('Placas');

  const CadastroKind(this.label);
  final String label;
  String get title => 'Cadastro de $label';
}

enum PersonType {
  cliente('Cliente'),
  fornecedor('Fornecedor');

  const PersonType(this.label);
  final String label;
}

enum DriverLink {
  autonomo('Autônomo'),
  transportadora('Transportadora');

  const DriverLink(this.label);
  final String label;
}

/// Dados de apresentação dos cadastros. Não é um contrato de API ou tabela.
class CadastroRecord {
  const CadastroRecord({
    required this.code,
    this.name = '',
    this.personType,
    this.driverLink,
    this.carrierCode,
    this.plate = '',
    this.address = '',
    this.number = '',
    this.complement = '',
    this.city = '',
    this.uf = '',
    this.postalCode = '',
    this.taxId = '',
    this.stateRegistration = '',
    this.enrollment = '',
    this.observation = '',
  });

  final int code;
  final String name,
      plate,
      address,
      number,
      complement,
      city,
      uf,
      postalCode,
      taxId,
      stateRegistration,
      enrollment,
      observation;
  final PersonType? personType;
  final DriverLink? driverLink;
  final int? carrierCode;

  String get identification => plate.isEmpty ? name : plate;
}
