import '../../core/libra/libra_api_client.dart';
import '../../core/libra/libra_configuration.dart';
import '../../core/libra/pre_ticket_dto.dart';
import '../../core/offline/offline_models.dart';
import '../../core/offline/pre_ticket_source.dart';
import '../configuracoes/settings_models.dart';
import 'operation_lookup.dart';
import 'operation_preview.dart';

class PreTicketService implements OperationLookupService {
  PreTicketService({
    required this.settings,
    LibraConfiguration? configuration,
    LibraApiClient? client,
  }) : configuration = configuration ?? LibraConfiguration(),
       client = client ?? LibraApiClient();

  final SettingsState settings;
  final LibraConfiguration configuration;
  final LibraApiClient client;

  @override
  Future<OperationLookup?> lookup(
    String plate,
    StationConnection connection,
  ) async {
    final json = await _request(plate, connection);
    final tickets = PreTicketDto.decode(json);
    if (tickets.isEmpty) return null;
    return OperationLookup(
      values: PreTicketDto.operationValues(tickets),
      trailers: const [],
      origin: PreTicketOrigin.remota,
      preTickets: tickets,
    );
  }

  Future<void> testConnection(String plate) async {
    await _request(plate, StationConnection.online, notFoundIsEmpty: false);
  }

  Future<Object?> _request(
    String plate,
    StationConnection connection, {
    bool notFoundIsEmpty = true,
  }) async {
    if (configuration.offline || connection == StationConnection.offline) {
      throw const LibraException(LibraFailure.offline);
    }
    final environment = settings.environment;
    final unit = settings.unitCode;
    final baseUrl = configuration.baseUrl(environment, local: settings.libra);
    final authentication = configuration.authentication(
      environment,
      local: settings.libra,
    );
    if (baseUrl == null) throw const LibraException(LibraFailure.configuration);
    return client.getPreTickets(
      baseUrl: baseUrl,
      apiKey: authentication.value,
      authKey: authentication.key,
      notFoundIsEmpty: notFoundIsEmpty,
      unitCode: unit,
      plate: normalizePlate(plate),
    );
  }
}
