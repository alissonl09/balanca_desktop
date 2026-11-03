enum ReportFilter {
  startDate('Data inicial'),
  endDate('Data final'),
  unit('Unidade'),
  status('Status'),
  plate('Placa'),
  trailer('Carreta'),
  driver('Motorista'),
  carrier('Transportadora'),
  party('Remetente / Destinatário'),
  product('Item / Produto'),
  operation('Operação'),
  documentType('Tipo de documento'),
  manual('Pesagem manual'),
  divergence('Divergência'),
  operatorName('Operador'),
  ticketNumber('Número do ticket'),
  weighingNumber('Número da pesagem'),
  ticketType('Tipo de ticket'),
  document('Documento'),
  issuer('Emissor'),
  name('Nome / Descrição');

  const ReportFilter(this.label);
  final String label;
  bool get isDate => this == startDate || this == endDate;
}

class ReportDefinition {
  const ReportDefinition(this.id, this.title, this.description, this.filters);
  final String id, title, description;
  final List<ReportFilter> filters;
}

/// Pesagens e tickets têm identidades e filtros independentes (relação 1:N).
/// Somente catálogo visual, sem pressupor contrato de API.
const reportCatalog = [
  ReportDefinition(
    'pesagens',
    'Relatório de Pesagens',
    'Consulta operacional única; as variações são filtros.',
    [
      ReportFilter.startDate,
      ReportFilter.endDate,
      ReportFilter.plate,
      ReportFilter.trailer,
      ReportFilter.driver,
      ReportFilter.carrier,
      ReportFilter.party,
      ReportFilter.product,
      ReportFilter.unit,
      ReportFilter.operation,
      ReportFilter.documentType,
      ReportFilter.status,
      ReportFilter.manual,
      ReportFilter.divergence,
      ReportFilter.operatorName,
    ],
  ),
  ReportDefinition(
    'tickets',
    'Relatório de Tickets',
    'Tickets independentes; uma pesagem pode gerar vários tickets.',
    [
      ReportFilter.ticketNumber,
      ReportFilter.weighingNumber,
      ReportFilter.plate,
      ReportFilter.startDate,
      ReportFilter.endDate,
      ReportFilter.ticketType,
      ReportFilter.document,
      ReportFilter.issuer,
      ReportFilter.status,
    ],
  ),
  ReportDefinition(
    'itens',
    'Relatório de Itens',
    'Cadastro de itens/produtos.',
    [ReportFilter.product, ReportFilter.status],
  ),
  ReportDefinition(
    'remetentes',
    'Relatório de Remetentes / Destinatários',
    'Cadastro de remetentes e destinatários.',
    [ReportFilter.party, ReportFilter.status],
  ),
  ReportDefinition(
    'transportadoras',
    'Relatório de Transportadoras',
    'Cadastro de transportadoras.',
    [ReportFilter.carrier, ReportFilter.status],
  ),
  ReportDefinition(
    'motoristas',
    'Relatório de Motoristas',
    'Cadastro de motoristas.',
    [ReportFilter.driver, ReportFilter.status],
  ),
  ReportDefinition(
    'depositos',
    'Relatório de Depósitos',
    'Cadastro de depósitos.',
    [ReportFilter.name, ReportFilter.unit, ReportFilter.status],
  ),
  ReportDefinition(
    'unidades',
    'Relatório de Unidades',
    'Cadastro de unidades.',
    [ReportFilter.unit, ReportFilter.status],
  ),
  ReportDefinition(
    'operacoes',
    'Relatório de Operações',
    'Cadastro de operações.',
    [ReportFilter.operation, ReportFilter.status],
  ),
];

/// Rascunho local, sem parâmetros HTTP ou resultados fictícios.
class ReportFilterDraft {
  final values = <ReportFilter, String>{};
}
