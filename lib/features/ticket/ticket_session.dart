import '../pesagem/weighing_preview.dart';
import '../pesagem/operation_lookup.dart';
import '../../core/offline/offline_models.dart';
import '../../core/libra/pre_ticket_dto.dart';
import '../configuracoes/settings_models.dart';
import 'ticket_pesagem.dart';

/// Ponte de memória entre Pesagem e Configurações. Sem persistência ou API.
class TicketSession {
  TicketSession({String? ticketNumber}) : officialTicketNumber = ticketNumber;
  final String? officialTicketNumber;
  String get ticketNumber => officialTicketNumber ?? '318875';
  TicketPesagem? printableTicket;
  String? printableStation;
  WeighingPreview? current;
  WeighingPreview? confirmed;
  String? consultedPlate;
  int? consultedUnitCode;
  StationEnvironment? consultedEnvironment;
  List<String> trailerOptions = [];
  OperationMode operationMode = OperationMode.manual;
  Map<String, String> officialOperation = const {};
  List<PreTicketDto> preTickets = const [];
  bool get invoiceWeightUsesDecimalPoint =>
      preTickets.isNotEmpty &&
      officialOperation.containsKey(invoiceWeightField);
  Map<String, String> draftOperation = {};
  WeighingPhase phase = WeighingPhase.nova;
  String? openWeighingPlate;
  final _manualReadings = <ManualReadingRecord>[];
  List<ManualReadingRecord> get manualReadings =>
      List.unmodifiable(_manualReadings);
  void recordManualReading(WeighingPreview preview) =>
      _manualReadings.add(ManualReadingRecord.fromPreview(preview));

  void clearConfirmation() {
    confirmed = null;
    printableTicket = null;
    printableStation = null;
  }
}
