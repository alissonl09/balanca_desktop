import '../../core/permissions/permission_models.dart';
import 'catalog_details.dart';

enum CadastroAction {
  read(AppPermission.readRegistry),
  insert(AppPermission.insertRegistry),
  edit(AppPermission.editRegistry),
  deactivate(AppPermission.deactivateRegistry);

  const CadastroAction(this.generalPermission);
  final AppPermission generalPermission;
}

enum CadastroKind {
  remetentes('Remetentes / Destinatários', {
    CadastroAction.read: AppPermission.readParties,
    CadastroAction.insert: AppPermission.insertParties,
    CadastroAction.edit: AppPermission.editParties,
    CadastroAction.deactivate: AppPermission.deactivateParties,
  }),
  transportadoras('Transportadoras', {
    CadastroAction.read: AppPermission.readCarriers,
    CadastroAction.insert: AppPermission.insertCarriers,
    CadastroAction.edit: AppPermission.editCarriers,
    CadastroAction.deactivate: AppPermission.deactivateCarriers,
  }),
  motoristas('Motoristas', {
    CadastroAction.read: AppPermission.readDrivers,
    CadastroAction.insert: AppPermission.insertDrivers,
    CadastroAction.edit: AppPermission.editDrivers,
    CadastroAction.deactivate: AppPermission.deactivateDrivers,
  }),
  placas('Placas', {
    CadastroAction.read: AppPermission.readPlates,
    CadastroAction.insert: AppPermission.insertPlates,
    CadastroAction.edit: AppPermission.editPlates,
    CadastroAction.deactivate: AppPermission.deactivatePlates,
  }),
  itens('Itens / Produtos', {
    CadastroAction.read: AppPermission.readItems,
    CadastroAction.insert: AppPermission.insertItems,
    CadastroAction.edit: AppPermission.editItems,
    CadastroAction.deactivate: AppPermission.deactivateItems,
  }),
  operacoes('Operações', {
    CadastroAction.read: AppPermission.readOperations,
    CadastroAction.insert: AppPermission.insertOperations,
    CadastroAction.edit: AppPermission.editOperations,
    CadastroAction.deactivate: AppPermission.deactivateOperations,
  }),
  tolerancias('Regras de Tolerância', {
    CadastroAction.read: AppPermission.readTolerances,
    CadastroAction.insert: AppPermission.insertTolerances,
    CadastroAction.edit: AppPermission.editTolerances,
    CadastroAction.deactivate: AppPermission.deactivateTolerances,
  }),
  complementos('Informações Complementares', {
    CadastroAction.read: AppPermission.readAttributes,
    CadastroAction.insert: AppPermission.insertAttributes,
    CadastroAction.edit: AppPermission.editAttributes,
    CadastroAction.deactivate: AppPermission.deactivateAttributes,
  });

  const CadastroKind(this.label, this.permissions);
  final String label;
  final Map<CadastroAction, AppPermission> permissions;
  String get title => 'Cadastro de $label';
  bool get isCatalog => index >= itens.index;
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
  CadastroRecord({
    this.code,
    this.sourceId,
    this.registration = '',
    Iterable<String> linkedVehicleIds = const [],
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
    this.active = true,
    this.catalog,
  }) : assert(code != null || (sourceId != null && sourceId != '')),
       linkedVehicleIds = Set.unmodifiable(linkedVehicleIds);

  final int? code;
  final String? sourceId;
  final String registration;
  final Set<String> linkedVehicleIds;
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
  final bool active;
  final CatalogDetails? catalog;

  String get id => sourceId ?? '$code';
  String get identification => plate.isEmpty ? name : plate;
  String displayCode(CadastroKind kind, {bool simulated = false}) =>
      kind == CadastroKind.motoristas
      ? registration
      : kind.isCatalog && simulated
      ? 'SIM-$id'
      : code?.toString() ?? id;
}

String normalizeCadastroPlate(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

bool isCadastroPlate(String value) =>
    RegExp(r'^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$').hasMatch(value);
