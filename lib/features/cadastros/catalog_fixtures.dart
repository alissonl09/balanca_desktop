import 'cadastro_record.dart';
import 'catalog_details.dart';

Map<CadastroKind, List<CadastroRecord>> catalogFixtures() => {
  CadastroKind.itens: [
    for (final (index, name) in ['Café', 'Milho', 'Soja', 'Sacaria'].indexed)
      CadastroRecord(code: index + 1, name: name, catalog: const ItemDetails()),
  ],
  CadastroKind.tolerancias: [
    CadastroRecord(
      code: 1,
      name: 'Tolerância de exemplo',
      catalog: const ToleranceDetails(
        calculates: true,
        unit: ToleranceUnit.percentual,
        loss: 0,
        yield: 1,
        receivingWeight: false,
      ),
    ),
    CadastroRecord(
      code: 2,
      name: 'Limites para BAG',
      catalog: const ToleranceDetails(
        calculates: true,
        unit: ToleranceUnit.kg,
        loss: 15,
        receivingWeight: true,
      ),
    ),
    CadastroRecord(
      code: 3,
      name: 'Dispensa explícita',
      catalog: const ToleranceDetails(calculates: false),
    ),
  ],
  CadastroKind.complementos: [
    CadastroRecord(
      code: 1,
      name: 'Referência do lote',
      catalog: AttributeDetails(type: AttributeType.texto, maxLength: 40),
    ),
    CadastroRecord(
      code: 2,
      name: 'Quantidade de volumes',
      catalog: AttributeDetails(type: AttributeType.inteiro, minimum: 0),
    ),
    CadastroRecord(
      code: 3,
      name: 'Umidade informada',
      catalog: AttributeDetails(
        type: AttributeType.decimal,
        unit: '%',
        precision: 5,
        decimalPlaces: 2,
        minimum: 0,
        maximum: 100,
      ),
    ),
    CadastroRecord(
      code: 4,
      name: 'Conferência efetuada',
      catalog: AttributeDetails(type: AttributeType.simNao),
    ),
    CadastroRecord(
      code: 5,
      name: 'Classificação visual',
      catalog: AttributeDetails(
        type: AttributeType.listaValores,
        options: [
          (id: 'REG', label: 'Regular'),
          (id: 'REV', label: 'Em revisão'),
        ],
      ),
    ),
    CadastroRecord(
      code: 6,
      name: 'Peso informado',
      catalog: AttributeDetails(type: AttributeType.peso, minimum: 0),
    ),
    CadastroRecord(
      code: 7,
      name: 'Data da conferência',
      catalog: AttributeDetails(type: AttributeType.data),
    ),
  ],
  CadastroKind.operacoes: [
    CadastroRecord(
      code: 1,
      name: 'Recebimento de demonstração',
      catalog: OperationDetails(
        nature: OperationNature.entrada,
        standard: '1',
        attributes: [
          (
            attributeId: '1',
            required: true,
            phase: CollectionPhase.opening,
            editable: true,
            printOnTicket: true,
            order: 1,
            productId: null,
            packaging: null,
          ),
          (
            attributeId: '2',
            required: false,
            phase: CollectionPhase.closing,
            editable: false,
            printOnTicket: false,
            order: 2,
            productId: '4',
            packaging: null,
          ),
        ],
      ),
    ),
    CadastroRecord(
      code: 2,
      name: 'Movimentação interna de demonstração',
      catalog: OperationDetails(nature: OperationNature.interna, standard: '3'),
    ),
    CadastroRecord(
      code: 3,
      name: 'Expedição de demonstração',
      catalog: OperationDetails(nature: OperationNature.saida, bag: '2'),
    ),
    CadastroRecord(
      code: 4,
      name: 'Outra operação de demonstração',
      catalog: OperationDetails(nature: OperationNature.outro),
    ),
  ],
};
