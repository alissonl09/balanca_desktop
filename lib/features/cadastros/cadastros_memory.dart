import 'package:flutter/foundation.dart';

import '../../core/permissions/permission_models.dart';
import 'cadastro_record.dart';
import 'catalog_details.dart';
import 'catalog_fixtures.dart';

class CadastroException implements Exception {
  const CadastroException(this.message);
  final String message;
}

/// Mantém a consulta a registros oficiais disponíveis em memória e isola a
/// manutenção de demonstração em outra instância.
class CadastrosMemory extends ChangeNotifier {
  CadastrosMemory.real(
    this.permissions, {
    Map<CadastroKind, List<CadastroRecord>> available = const {},
  }) : simulated = false,
       _records = {
         for (final kind in CadastroKind.values)
           kind: List.unmodifiable(available[kind] ?? const []),
       };

  CadastrosMemory.mock(this.permissions) : simulated = true {
    _records = {
      CadastroKind.remetentes: [
        CadastroRecord(
          code: 1,
          name: 'Fazenda Boa Vista',
          personType: PersonType.fornecedor,
          address: 'Estrada Rural',
          number: 'S/N',
          city: 'Guaxupé',
          uf: 'MG',
          observation: 'Exemplo temporário.',
        ),
        CadastroRecord(
          code: 2,
          name: 'Comercial de Café Horizonte',
          personType: PersonType.cliente,
          city: 'Campinas',
          uf: 'SP',
        ),
      ],
      CadastroKind.transportadoras: [
        CadastroRecord(
          code: 1,
          name: 'Transportadora Horizonte',
          city: 'Guaxupé',
          uf: 'MG',
        ),
        CadastroRecord(
          code: 2,
          name: 'Cargas Serra Azul',
          city: 'Campinas',
          uf: 'SP',
        ),
        CadastroRecord(
          code: 3,
          name: 'Transportes Vale do Café',
          city: 'Varginha',
          uf: 'MG',
        ),
      ],
      CadastroKind.motoristas: [
        CadastroRecord(
          code: 1,
          registration: 'SIM-1',
          linkedVehicleIds: ['1'],
          name: 'João da Silva',
          driverLink: DriverLink.autonomo,
          city: 'Guaxupé',
          uf: 'MG',
        ),
        CadastroRecord(
          code: 2,
          registration: 'SIM-2',
          name: 'Maria Oliveira',
          driverLink: DriverLink.transportadora,
          carrierCode: 1,
        ),
      ],
      CadastroKind.placas: [
        CadastroRecord(code: 1, plate: 'ABC1D23', carrierCode: 1),
        CadastroRecord(code: 2, plate: 'DEF4G56', carrierCode: 2),
      ],
      ...catalogFixtures(),
    };
    for (final kind in CadastroKind.values) {
      _nextCodes[kind] =
          _records[kind]!.fold<int>(
            0,
            (value, record) => record.code! > value ? record.code! : value,
          ) +
          1;
    }
  }

  late final Map<CadastroKind, List<CadastroRecord>> _records;
  final _nextCodes = <CadastroKind, int>{};
  final PermissionState permissions;
  final bool simulated;

  bool _allows(CadastroKind kind, CadastroAction action) =>
      permissions.allows(action.generalPermission) &&
      permissions.allows(kind.permissions[action]!);

  String? unavailable(CadastroKind kind, CadastroAction action) {
    if (!_allows(kind, CadastroAction.read) || !_allows(kind, action)) {
      return 'Sem permissão';
    }
    if (action != CadastroAction.read && !simulated) {
      return 'Integração de manutenção indisponível';
    }
    return null;
  }

  String? get linkUnavailable =>
      !_allows(CadastroKind.motoristas, CadastroAction.read) ||
          !permissions.allows(AppPermission.manageDriverPlates)
      ? 'Sem permissão para manter vínculos'
      : simulated
      ? null
      : 'Integração de manutenção indisponível';

  List<CadastroRecord> records(CadastroKind kind) =>
      _allows(kind, CadastroAction.read)
      ? List.unmodifiable(_records[kind]!)
      : const [];

  int nextCode(CadastroKind kind) => _nextCodes[kind]!;

  CadastroRecord? carrier(int? code) => code == null
      ? null
      : records(CadastroKind.transportadoras)
            .where((record) => record.code == code)
            .firstOrNull;

  String carrierName(int? code) =>
      carrier(code)?.name ??
      (code == null
          ? 'Não informada'
          : 'Transportadora indisponível (cód. $code)');

  Map<String, String> linkedPlates(CadastroRecord driver) {
    if (!records(CadastroKind.motoristas).contains(driver)) return const {};
    final plates = {
      for (final vehicle in _records[CadastroKind.placas]!)
        vehicle.id: vehicle.plate,
    };
    return {
      for (final id in driver.linkedVehicleIds)
        id: plates[id] ?? 'Placa indisponível (ID $id)',
    };
  }

  void _require(CadastroKind kind, CadastroAction action) {
    final reason = unavailable(kind, action);
    if (reason != null) throw CadastroException(reason);
  }

  void save(
    CadastroKind kind,
    CadastroRecord record, {
    CadastroRecord? previous,
  }) {
    _require(
      kind,
      previous == null ? CadastroAction.insert : CadastroAction.edit,
    );
    final entries = _records[kind]!;
    final index = previous == null ? -1 : entries.indexOf(previous);
    if (previous == null
        ? record.sourceId != null || record.code != nextCode(kind)
        : index < 0 ||
              record.id != previous.id ||
              record.code != previous.code ||
              record.registration != previous.registration) {
      throw const CadastroException(
        'O cadastro foi atualizado. Reabra o formulário para continuar.',
      );
    }
    if (kind == CadastroKind.motoristas) _validateDriver(record, previous);
    if (kind.isCatalog) {
      if (previous?.active == true && !record.active) {
        _require(kind, CadastroAction.deactivate);
      }
      _validateCatalog(kind, record, previous?.catalog);
    }

    if (previous == null) {
      entries.add(record);
      _nextCodes[kind] = record.code! + 1;
    } else {
      entries[index] = record;
    }
    notifyListeners();
  }

  void _validateDriver(CadastroRecord driver, CadastroRecord? previous) {
    if (driver.name.trim().isEmpty) {
      throw const CadastroException('Informe o nome.');
    }
    if (previous == null && driver.registration != 'SIM-${driver.code}') {
      throw const CadastroException('Matrícula de simulação inválida.');
    }
    final original = previous?.linkedVehicleIds ?? const <String>{};
    final updated = driver.linkedVehicleIds;
    if (setEquals(original, updated)) return;
    final reason = linkUnavailable;
    if (reason != null) throw CadastroException(reason);

    final added = updated.difference(original);
    if (added.isEmpty) return;
    if (!_allows(CadastroKind.placas, CadastroAction.read)) {
      throw const CadastroException('Sem permissão para consultar placas');
    }
    final plates = {
      for (final vehicle in _records[CadastroKind.placas]!)
        vehicle.id: normalizeCadastroPlate(vehicle.plate),
    };
    final inUse = {
      for (final id in updated.intersection(original)) ?plates[id],
    };
    for (final id in added) {
      final plate = plates[id];
      if (plate == null || !isCadastroPlate(plate)) {
        throw const CadastroException('Selecione uma placa cadastrada válida.');
      }
      if (!inUse.add(plate)) {
        throw const CadastroException('Esta placa já está vinculada.');
      }
    }
  }

  void _validateCatalog(
    CadastroKind kind,
    CadastroRecord record,
    CatalogDetails? previous,
  ) {
    if (record.name.trim().isEmpty) {
      throw const CadastroException('Informe a descrição.');
    }
    final details = record.catalog;
    final issue = switch ((kind, details)) {
      (CadastroKind.itens, ItemDetails()) => null,
      (CadastroKind.tolerancias, ToleranceDetails rule) =>
        rule.calculates && rule.unit == null
            ? 'Informe o tipo de tolerância.'
            : rule.loss?.isFinite == false || rule.yield?.isFinite == false
            ? 'Informe valores numéricos válidos.'
            : null,
      (CadastroKind.complementos, AttributeDetails attribute) =>
        attribute.issue,
      (CadastroKind.operacoes, OperationDetails operation) => operation.issue,
      _ => 'Informe os dados do cadastro.',
    };
    if (issue != null) throw CadastroException(issue);
    if (details is OperationDetails) {
      final original = previous is OperationDetails ? previous : null;
      void validateReference(CadastroKind target, String? id, String? old) {
        if (id != null &&
            id != old &&
            !records(target)
                .any((record) => record.id == id && record.active)) {
          throw CadastroException(
            'Selecione um registro ativo em ${target.label}.',
          );
        }
      }

      validateReference(
        CadastroKind.tolerancias,
        details.standard,
        original?.standard,
      );
      validateReference(CadastroKind.tolerancias, details.bag, original?.bag);
      validateReference(CadastroKind.tolerancias, details.bulk, original?.bulk);
      for (final binding in details.attributes) {
        final existing = original?.attributes
            .where((entry) => entry == binding)
            .firstOrNull;
        validateReference(
          CadastroKind.complementos,
          binding.attributeId,
          existing?.attributeId,
        );
        validateReference(
          CadastroKind.itens,
          binding.productId,
          existing?.productId,
        );
      }
    }
  }

  void remove(CadastroKind kind, CadastroRecord record) {
    _require(kind, CadastroAction.deactivate);
    final entries = _records[kind]!;
    final index = entries.indexOf(record);
    if (index < 0) {
      throw const CadastroException('O registro foi atualizado ou excluído.');
    }
    if (kind.isCatalog) {
      entries[index] = CadastroRecord(
        code: record.code,
        sourceId: record.sourceId,
        name: record.name,
        observation: record.observation,
        catalog: record.catalog,
        active: false,
      );
    } else {
      entries.removeAt(index);
    }
    notifyListeners();
  }
}
