import 'ticket_pesagem.dart';
import 'ticket_traceability.dart';

/// Exemplos tipados, acessíveis somente pela seleção explícita de dados simulados.
/// Campos ainda sem origem (produto, partes, cidade etc.) continuam ausentes.
List<TicketPesagem> ticketPreviewExamples(
  TicketBranding branding,
  DateTime issuedAt,
) => [
  TicketPesagem(
    ticketNumber: 'DEMO-A01',
    traceabilityId: previewTicketIdentifier('DEMO-A01'),
    branding: branding,
    issuedAt: issuedAt,
    documents: const ['DOC-DEMO-A', 'DOC-DEMO-B'],
    tractorPlate: 'MCK1A23',
    packaging: 'Granel',
    firstWeight: 32000,
    firstWeighedAt: DateTime(2026, 1, 15, 9),
    captureType: TicketCaptureType.automatic,
  ),
  TicketPesagem(
    ticketNumber: 'DEMO-F01',
    traceabilityId: previewTicketIdentifier('DEMO-F01'),
    branding: branding,
    issuedAt: issuedAt,
    documents: const ['DOC-DEMO-A', 'DOC-DEMO-B'],
    tractorPlate: 'MCK1A23',
    trailerPlate: 'MCK2B34',
    firstWeight: 32000,
    secondWeight: 12500,
    netWeight: 19500,
    firstWeighedAt: DateTime(2026, 1, 15, 9),
    secondWeighedAt: DateTime(2026, 1, 15, 10, 15),
    observation: 'Observação de demonstração.\nSegunda linha.',
    captureType: TicketCaptureType.automatic,
  ),
  TicketPesagem(
    ticketNumber: 'DEMO-M01',
    traceabilityId: previewTicketIdentifier('DEMO-M01'),
    branding: branding,
    issuedAt: issuedAt,
    tractorPlate: 'MCK1A23',
    firstWeight: 12000,
    firstWeighedAt: DateTime(2026, 1, 15, 9),
    captureType: TicketCaptureType.manual,
    manualAuthorizer: 'usuário-demo',
    manualJustification: 'Exemplo tipado para conferência do layout.',
  ),
];
