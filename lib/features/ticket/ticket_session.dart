import '../pesagem/weighing_preview.dart';
import '../pesagem/operation_lookup.dart';
import '../../core/offline/offline_models.dart';

/// Ponte de memória entre Pesagem e Configurações. Sem persistência ou API.
class TicketSession {
  TicketSession({this.ticketNumber = '318875'});
  final String ticketNumber;
  WeighingPreview? current;
  WeighingPreview? confirmed;
  String? consultedPlate;
  List<String> trailerOptions = [];
  OperationMode operationMode = OperationMode.manual;
  Map<String, String> officialOperation = const {};
  Map<String, String> draftOperation = {};
  WeighingPhase phase = WeighingPhase.nova;
  final _manualReadings = <ManualReadingRecord>[];
  List<ManualReadingRecord> get manualReadings =>
      List.unmodifiable(_manualReadings);
  void recordManualReading(WeighingPreview preview) =>
      _manualReadings.add(ManualReadingRecord.fromPreview(preview));

  void clearConfirmation() => confirmed = null;
}
