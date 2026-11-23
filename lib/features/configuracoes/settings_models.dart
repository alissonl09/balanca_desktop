import 'package:flutter/foundation.dart';

import '../../core/libra/libra_settings_store.dart';
import '../../core/libra/libra_auth_session.dart';
import '../../core/database/database_manager.dart';

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

/// Posições fixas dos dispositivos na configuração, independentes do papel.
enum GateSlot { one, two }

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
    LibraSettingsStore? libraStore,
    LibraSettingsData? libraSettings,
    LibraAuthSession? libraAuth,
    this.database,
  }) : gateEquipmentSource =
           gateEquipmentSource ?? const MockGateEquipmentSource(),
       manualCapture = manualCapture ?? ManualCaptureServices.current,
       libraStore = libraStore ?? MemoryLibraSettingsStore(),
       libra = libraSettings ?? LibraSettingsData(),
       libraAuth = libraAuth ?? LibraAuthSession() {
    environment = StationEnvironment.values.firstWhere(
      (e) => e.name == libra.selectedEnvironment,
      orElse: () => StationEnvironment.homologacao,
    );
  }
  final LibraSettingsStore libraStore;
  final LibraSettingsData libra;
  final LibraAuthSession libraAuth;
  final DatabaseManager? database;
  Future<void> saveLibraSettings() {
    libra.selectedEnvironment = environment.name;
    return libraStore.save(libra);
  }

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
  String? _gate1Id, _gate2Id;
  bool _gatesReversed = false;
  String? gateId(GateSlot slot) => slot == GateSlot.one ? _gate1Id : _gate2Id;
  GateSide gateSide(GateSlot slot) =>
      (slot == GateSlot.one) != _gatesReversed ? GateSide.entry : GateSide.exit;
  String? get entryBarrierId => _gatesReversed ? _gate2Id : _gate1Id;
  String? get exitBarrierId => _gatesReversed ? _gate1Id : _gate2Id;
  bool get gateAssignmentsValid =>
      entryBarrierId == null ||
      exitBarrierId == null ||
      entryBarrierId != exitBarrierId;
  bool assignBarrier(GateSide side, String? id) {
    final slot = gateSide(GateSlot.one) == side ? GateSlot.one : GateSlot.two;
    return assignGate(slot, id);
  }

  bool assignGate(GateSlot slot, String? id) {
    if (id != null && !gateEquipmentSource.available.any((e) => e.id == id)) {
      return false;
    }
    if (id != null &&
        id == gateId(slot == GateSlot.one ? GateSlot.two : GateSlot.one)) {
      return false;
    }
    update(() {
      if (slot == GateSlot.one) {
        _gate1Id = id;
      } else {
        _gate2Id = id;
      }
      accessControl.bindEquipments(entryBarrierId, exitBarrierId);
    });
    return true;
  }

  bool swapBarriers() {
    if (!barriers) return false;
    update(() {
      _gatesReversed = !_gatesReversed;
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
    final previousEnvironment = environment;
    final previousUrl = libra.environments[environment.name]?.baseUrl;
    change();
    if (previousEnvironment != environment ||
        previousUrl != libra.environments[environment.name]?.baseUrl) {
      libraAuth.clear();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    libraAuth.clear();
    indicators.dispose();
    indicatorState.dispose();
    permissions.dispose();
    accessControl.dispose();
    super.dispose();
  }
}
