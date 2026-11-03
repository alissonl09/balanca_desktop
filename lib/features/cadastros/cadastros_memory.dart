import 'package:flutter/foundation.dart';

import 'cadastro_record.dart';

/// Estado temporário da demonstração, restrito à sessão da aplicação.
/// Não acessa banco, arquivos, API ou infraestrutura de persistência.
class CadastrosMemory extends ChangeNotifier {
  CadastrosMemory.mock() {
    _records = {
      CadastroKind.remetentes: [
        const CadastroRecord(
          code: 1,
          name: 'Fazenda Boa Vista',
          personType: PersonType.fornecedor,
          address: 'Estrada Rural',
          number: 'S/N',
          city: 'Guaxupé',
          uf: 'MG',
          observation: 'Exemplo temporário.',
        ),
        const CadastroRecord(
          code: 2,
          name: 'Comercial de Café Horizonte',
          personType: PersonType.cliente,
          city: 'Campinas',
          uf: 'SP',
        ),
      ],
      CadastroKind.transportadoras: [
        const CadastroRecord(
          code: 1,
          name: 'Transportadora Horizonte',
          city: 'Guaxupé',
          uf: 'MG',
        ),
        const CadastroRecord(
          code: 2,
          name: 'Cargas Serra Azul',
          city: 'Campinas',
          uf: 'SP',
        ),
        const CadastroRecord(
          code: 3,
          name: 'Transportes Vale do Café',
          city: 'Varginha',
          uf: 'MG',
        ),
      ],
      CadastroKind.motoristas: [
        const CadastroRecord(
          code: 1,
          name: 'João da Silva',
          driverLink: DriverLink.autonomo,
          city: 'Guaxupé',
          uf: 'MG',
        ),
        const CadastroRecord(
          code: 2,
          name: 'Maria Oliveira',
          driverLink: DriverLink.transportadora,
          carrierCode: 1,
        ),
      ],
      CadastroKind.placas: [
        const CadastroRecord(code: 1, plate: 'ABC1D23', carrierCode: 1),
        const CadastroRecord(code: 2, plate: 'DEF4G56', carrierCode: 2),
      ],
    };
    for (final kind in CadastroKind.values) {
      _nextCodes[kind] =
          records(kind).fold(
            0,
            (value, record) => record.code > value ? record.code : value,
          ) +
          1;
    }
  }

  late final Map<CadastroKind, List<CadastroRecord>> _records;
  final _nextCodes = <CadastroKind, int>{};

  List<CadastroRecord> records(CadastroKind kind) =>
      List.unmodifiable(_records[kind]!);
  int nextCode(CadastroKind kind) => _nextCodes[kind]!;

  CadastroRecord? carrier(int? code) {
    for (final record in _records[CadastroKind.transportadoras]!) {
      if (record.code == code) return record;
    }
    return null;
  }

  String carrierName(int? code) =>
      carrier(code)?.name ??
      (code == null
          ? 'Não informada'
          : 'Transportadora indisponível (cód. $code)');

  void save(CadastroKind kind, CadastroRecord record) {
    final records = _records[kind]!;
    final index = records.indexWhere(
      (existing) => existing.code == record.code,
    );
    if (index < 0) {
      records.add(record);
    } else {
      records[index] = record;
    }
    // Reserva definitiva apenas na simulação após Salvar, nunca ao abrir/cancelar.
    if (record.code >= nextCode(kind)) _nextCodes[kind] = record.code + 1;
    notifyListeners();
  }

  void remove(CadastroKind kind, int code) {
    _records[kind]!.removeWhere((record) => record.code == code);
    // Sem exclusão em cascata ou regras definitivas de integridade nesta etapa.
    notifyListeners();
  }
}
