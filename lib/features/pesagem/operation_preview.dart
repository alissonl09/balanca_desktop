import 'weighing_preview.dart';

/// Dados exclusivamente simulados da interface, sem contrato de API.
/// Cada linha representa uma operação aberta de uma carreta.
const operationPreview = <({String plate, String trailer, String time})>[
  (plate: 'ABC1D23', trailer: 'DEF4G56', time: '09:12'),
  (plate: 'ABC1D23', trailer: 'XYZ9H87', time: '09:14'),
  (plate: 'DEF2E34', trailer: 'GHI5J67', time: '09:18'),
  (plate: 'GHI3F45', trailer: 'JKL6M78', time: '09:25'),
  (plate: 'JKL4G56', trailer: 'MNO7P89', time: '09:31'),
  (plate: 'MNO5H67', trailer: 'PQR8S90', time: '09:40'),
  (plate: 'PQR6J78', trailer: 'STU9V01', time: '09:45'),
];

/// Exemplos visuais para validar valores extensos e múltiplos documentos.
const operationDetailsPreview = {
  'Motorista': 'José Antônio dos Santos Oliveira',
  'Transportador':
      'Transportadora Motoristas Autônomos de Cargas do Sul de Minas Gerais',
  'Emissor(es)': 'Cooperativa Regional de Cafeicultores • Unidade Guaxupé; Produtores Associados • Unidade São Sebastião do Paraíso',
  'Depósito': 'Armazém de Recebimento e Distribuição de Café • Unidade Guaxupé',
  'Tipo do documento': 'Nota Fiscal',
  'Nº Nota(s) / Documento(s)':
      'NF-e 000123456 / Série 001; NF-e 000123457 / Série 002',
  'Peso N.F. (Kg)': '28450',
  'Embalagem': 'Granel',
};

/// Somente esta amostra inicia com peso anterior, para demonstrar fechamento.
const operationSummariesPreview = {'DEF2E34': WeighingSummary(first: 28450)};

String normalizePlate(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

/// Amostras da fila lateral; não alteram as opções da consulta de placa.
const operationQueuePreview = <({String plate, String? trailer, String time})>[
  (plate: 'ABC1D23', trailer: null, time: '09:12'),
  (plate: 'ABC1D23', trailer: 'XYZ9H87', time: '09:14'),
  (plate: 'DEF2E34', trailer: null, time: '09:18'),
  (plate: 'GHI3F45', trailer: 'JKL6M78', time: '09:25'),
  (plate: 'JKL4G56', trailer: null, time: '09:31'),
  (plate: 'MNO5H67', trailer: null, time: '09:40'),
  (plate: 'PQR6J78', trailer: null, time: '09:45'),
];

/// Veículos aguardando no pátio; dados apenas para a interface.
const yardQueuePreview = <({String plate, String? trailer, String time})>[
  (plate: 'RST7K89', trailer: null, time: '08:35'),
  (plate: 'UVW8L90', trailer: null, time: '08:42'),
  (plate: 'XYZ9M01', trailer: 'ABC2N34', time: '08:50'),
  (plate: 'BCD1P23', trailer: null, time: '08:58'),
  (plate: 'EFG2Q34', trailer: null, time: '09:03'),
  (plate: 'HIJ3R45', trailer: 'KLM4S56', time: '09:07'),
];
