import 'package:flutter/foundation.dart';

import '../../core/indicators/indicator_models.dart';
import '../../core/indicators/indicator_driver.dart';
import '../../core/permissions/permission_models.dart';
import '../access_control/access_control_state.dart';
import '../pesagem/manual_capture/manual_capture_services.dart';

enum StationEnvironment {
  producao('Produção'),
  homologacao('Homologação'),
  desenvolvimento('Desenvolvimento');

  const StationEnvironment(this.label);
  final String label;
}

class UnitOption {
  const UnitOption(this.code, this.description);
  final int code;
  final String description;
  String get label => '$code - $description';
}

enum PrinterFormat {
  ticket('Ticket/Cupom'),
  a4('A4');

  const PrinterFormat(this.label);
  final String label;
}

enum PrinterStatus {
  online('Online'),
  offline('Offline'),
  unavailable('Indisponível');

  const PrinterStatus(this.label);
  final String label;
}

enum PaperOrientation {
  portrait('Retrato'),
  landscape('Paisagem');

  const PaperOrientation(this.label);
  final String label;
}

enum TicketLogo { standard, demonstration }

class PaperSettings {
  PaperSettings({
    required this.size,
    required this.source,
    this.orientation = PaperOrientation.portrait,
  });
  String size, source;
  PaperOrientation orientation;
}

class PrinterOption {
  const PrinterOption({
    required this.id,
    required this.name,
    required this.status,
    required this.format,
    required this.connectionType,
    required this.connection,
    required this.sizes,
    required this.sources,
  });
  final String id, name, connectionType, connection;
  final PrinterStatus status;
  final PrinterFormat format;
  final List<String> sizes, sources;

  PaperSettings defaultPaper() =>
      PaperSettings(size: sizes.first, source: sources.first);
}

class PrintSettings {
  String printerId = 'ticket-usb';
  String fallbackPrinterId = 'a4-usb';
  final Map<String, PaperSettings> paperByPrinter = {};
  TicketLogo logo = TicketLogo.standard;
  bool emitEntry = true, emitExit = true, windowsTicket = false;
  int copies = 1;
  String header = '', footer = '';
}

/// Rascunho local de apresentação, sem persistência ou efeito nas integrações.
class SettingsState extends ChangeNotifier {
  SettingsState({
    GateEquipmentSource? gateEquipmentSource,
    ManualCaptureServices? manualCapture,
  }) : gateEquipmentSource =
           gateEquipmentSource ?? const MockGateEquipmentSource(),
       manualCapture = manualCapture ?? ManualCaptureServices.current;
  final ManualCaptureServices manualCapture;
  final GateEquipmentSource gateEquipmentSource;
  bool manualWeighingEnabled = true;
  final indicators = IndicatorConfiguration();
  final indicatorState = MemoryIndicatorState();
  final permissions = PermissionState();
  final accessControl = AccessControlState();
  int unitCode = 4;
  StationEnvironment environment = StationEnvironment.homologacao;
  bool integratedSgv = false;
  static const defaultDisplayMessage = 'COOXUPÉ';
  static const maxDisplayMessageLength = 40;
  String displayMessage = defaultDisplayMessage;
  bool barriers = false,
      trafficLight = false,
      informationDisplay = false,
      ocr = false,
      voice = false;
  String? entryBarrierId, exitBarrierId;
  bool get gateAssignmentsValid =>
      entryBarrierId == null ||
      exitBarrierId == null ||
      entryBarrierId != exitBarrierId;
  bool assignBarrier(GateSide side, String? id) {
    if (id != null && !gateEquipmentSource.available.any((e) => e.id == id)) {
      return false;
    }
    if (id != null &&
        id == (side == GateSide.entry ? exitBarrierId : entryBarrierId)) {
      return false;
    }
    update(() {
      if (side == GateSide.entry) {
        entryBarrierId = id;
      } else {
        exitBarrierId = id;
      }
      accessControl.bindEquipment(side, id);
    });
    return true;
  }

  bool swapBarriers() {
    if (!barriers) return false;
    update(() {
      final previousEntry = entryBarrierId;
      entryBarrierId = exitBarrierId;
      exitBarrierId = previousEntry;
      accessControl.bindEquipments(entryBarrierId, exitBarrierId);
    });
    return true;
  }

  void setDisplayMessage(String value) {
    final hasText = value.trim().isNotEmpty;
    update(() {
      displayMessage = !hasText
          ? defaultDisplayMessage
          : String.fromCharCodes(value.runes.take(maxDisplayMessageLength));
    });
  }

  String ocrAddress = '', ocrToken = '';
  int? ocrPort;
  final printing = PrintSettings();

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  @override
  void dispose() {
    indicators.dispose();
    indicatorState.dispose();
    permissions.dispose();
    accessControl.dispose();
    super.dispose();
  }
}
