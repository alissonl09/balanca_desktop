import 'offline_models.dart';

enum PreTicketOrigin { remota, local }

/// Dados mínimos de domínio, não um DTO presumido do GET da Libra.
class KnownPreTicket {
  KnownPreTicket({
    required this.id,
    required this.plate,
    Iterable<String> trailers = const [],
  }) : trailers = List.unmodifiable(trailers);
  final String id, plate;
  final List<String> trailers;
}

abstract interface class PreTicketSource {
  Future<KnownPreTicket?> findByPlate(String plate);
}

class MemoryPreTicketSource implements PreTicketSource {
  MemoryPreTicketSource(Iterable<KnownPreTicket> tickets)
    : _tickets = {for (final ticket in tickets) ticket.plate: ticket};
  final Map<String, KnownPreTicket> _tickets;
  @override
  Future<KnownPreTicket?> findByPlate(String plate) async => _tickets[plate];
}

class PreTicketLookup {
  const PreTicketLookup(this.origin, this.ticket);
  final PreTicketOrigin origin;
  final KnownPreTicket? ticket;
}

/// Sem HTTP/cache automático. O adaptador remoto futuro usará somente esta rota.
/// Não usa Saturno nem modela Acessos. SGV não participa desta consulta básica.
class PreTicketResolver {
  PreTicketResolver({required this.local, this.remote});
  static const remotePath = '/api/v1/pre-tickets';
  final PreTicketSource local;
  final PreTicketSource? remote;

  Future<PreTicketLookup> lookup(
    String plate,
    StationConnection connection,
  ) async {
    if (connection != StationConnection.offline && remote != null) {
      return PreTicketLookup(
        PreTicketOrigin.remota,
        await remote!.findByPlate(plate),
      );
    }
    return PreTicketLookup(
      PreTicketOrigin.local,
      await local.findByPlate(plate),
    );
  }
}
