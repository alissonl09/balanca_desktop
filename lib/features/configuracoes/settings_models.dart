import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/libra/libra_settings_store.dart';
import '../../core/libra/libra_auth_session.dart';
import '../../core/database/database_manager.dart';

import '../../core/indicators/indicator_models.dart';
import '../../core/indicators/indicator_driver.dart';
import '../../core/indicators/indicator_settings_store.dart';
import '../../core/indicators/serial_indicator_service.dart';
import '../../core/permissions/permission_models.dart';
import '../access_control/access_control_state.dart';
import '../pesagem/manual_capture/manual_capture_services.dart';
import '../ticket/print_settings.dart';
import '../ticket/printer_service.dart';
import '../ticket/windows_printer_adapter.dart';

export '../ticket/print_settings.dart';

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

/// Posições fixas dos dispositivos na configuração, independentes do papel.
enum GateSlot { one, two }

/// Configurações compartilhadas pelas telas da estação.
class SettingsState extends ChangeNotifier {
  SettingsState({
    GateEquipmentSource? gateEquipmentSource,
    ManualCaptureServices? manualCapture,
    LibraSettingsStore? libraStore,
    LibraSettingsData? libraSettings,
    LibraAuthSession? libraAuth,
    this.indicatorStore,
    IndicatorSettingsData? indicatorSettings,
    IndicatorTransport Function()? serialTransportFactory,
    Future<List<String>> Function()? serialPortList,
    this.database,
    this.printStore,
    Map<String, Map<String, dynamic>> printStations = const {},
    PrinterService? printerService,
    this.printSettingsLoadFailed = false,
  }) : gateEquipmentSource =
           gateEquipmentSource ?? const MockGateEquipmentSource(),
       manualCapture = manualCapture ?? ManualCaptureServices.current,
       libraStore = libraStore ?? MemoryLibraSettingsStore(),
       libra = libraSettings ?? LibraSettingsData(),
       libraAuth = libraAuth ?? LibraAuthSession(),
       _indicatorSettings = indicatorSettings ?? const IndicatorSettingsData(),
       _printStations = Map.of(printStations),
       _defaultPrintSimulation = printStore == null && printerService == null,
       _ownsPrinterService = printerService == null,
       printerService =
           printerService ??
           PrinterService(WindowsPrinterAdapter(), log: printStore?.log) {
    environment = StationEnvironment.values.firstWhere(
      (e) => e.name == libra.selectedEnvironment,
      orElse: () => StationEnvironment.homologacao,
    );
    unitCode = _indicatorSettings.units[environment.name] ?? unitCode;
    printing = _loadPrintSettings();
    serialIndicator = SerialIndicatorService(
      indicatorState,
      transportFactory: serialTransportFactory,
      portList: serialPortList,
    );
    try {
      _loadIndicatorModels();
      _loadIndicatorStation();
    } catch (_) {
      _indicatorSettings = const IndicatorSettingsData(loadFailed: true);
      _loadIndicatorModels();
      _loadIndicatorStation();
    }
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
  final LocalIndicatorSettingsStore? indicatorStore;
  IndicatorSettingsData _indicatorSettings;
  late final SerialIndicatorService serialIndicator;
  bool _disposed = false;
  bool get indicatorSettingsLoadFailed => _indicatorSettings.loadFailed;
  String get indicatorStationId => '${environment.name}/$unitCode';

  void _loadIndicatorModels() {
    final saved = _indicatorSettings.models;
    final models = saved == null
        ? initialIndicatorModels()
        : saved.map(IndicatorModel.fromJson).toList();
    indicators.models
      ..clear()
      ..addAll(models);
  }

  void _loadIndicatorStation() {
    try {
      indicators.restoreStation(
        _indicatorSettings.stations[indicatorStationId],
      );
    } catch (_) {
      indicators.restoreStation(null);
      indicators.mode = IndicatorMode.real;
      serialIndicator.configure(
        station: indicatorStationId,
        mode: IndicatorMode.real,
        issue: 'Configuração serial desta estação inválida.',
      );
      return;
    }
    if (_indicatorSettings.loadFailed) indicators.mode = IndicatorMode.real;
    _applyOperationalIndicator(indicators.mode, indicators.operational);
  }

  void _applyOperationalIndicator(
    IndicatorMode mode,
    IndicatorInstallation? item,
  ) {
    String? issue;
    if (_indicatorSettings.loadFailed) {
      issue = 'Falha ao carregar a configuração local dos indicadores.';
    } else if (mode == IndicatorMode.real) {
      final model = indicators.model(item?.modelCode);
      if (item == null) {
        issue = 'Selecione o indicador operacional da estação.';
      } else if (item.active) {
        if (model == null) {
          issue = 'Modelo do indicador operacional indisponível.';
        } else if (item.connectionType != IndicatorConnectionType.serial) {
          issue = 'A leitura operacional real requer transporte Serial.';
        } else {
          issue = [
            ...item.validate(model),
            ?item.serialProtocolError,
          ].firstOrNull;
        }
      }
    }
    serialIndicator.configure(
      station: indicatorStationId,
      mode: mode,
      installation: item?.active == true ? item : null,
      issue: issue,
    );
  }

  Future<void> saveIndicatorSettings({required bool catalog}) async {
    final station = indicatorStationId;
    final next = IndicatorSettingsData(
      stations: {
        ..._indicatorSettings.stations,
        if (!catalog) station: indicators.stationJson(),
      },
      models: catalog
          ? [for (final model in indicators.models) model.toJson()]
          : _indicatorSettings.models,
      units: {
        ..._indicatorSettings.units,
        if (!catalog) environment.name: unitCode,
      },
      loadFailed: catalog && _indicatorSettings.loadFailed,
    );
    await indicatorStore?.save(next);
    if (_disposed) return;
    _indicatorSettings = next;
    // Aplica o snapshot salvo, mesmo se houver alterações ainda em edição.
    final committed = IndicatorConfiguration();
    try {
      committed.restoreStation(next.stations[indicatorStationId]);
      _applyOperationalIndicator(
        next.loadFailed ? IndicatorMode.real : committed.mode,
        committed.operational,
      );
    } finally {
      committed.dispose();
    }
  }

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
  final LocalPrintSettingsStore? printStore;
  final PrinterService printerService;
  final bool _defaultPrintSimulation, _ownsPrinterService;
  bool printSettingsLoadFailed;
  Map<String, Map<String, dynamic>> _printStations;
  late PrintSettings printing;

  PrintSettings get savedPrinting => _loadPrintSettings();

  PrintSettings _loadPrintSettings() {
    final stored = _printStations[indicatorStationId];
    return stored == null
        ? PrintSettings(simulated: _defaultPrintSimulation)
        : PrintSettings.fromJson(stored);
  }

  Future<void> savePrintSettings() async {
    final next = {..._printStations, indicatorStationId: printing.toJson()};
    await printStore?.save(next);
    if (_disposed) return;
    _printStations = next;
    printSettingsLoadFailed = false;
    notifyListeners();
  }

  void update(VoidCallback change) {
    final previousStation = indicatorStationId;
    final previousEnvironment = environment;
    final previousUrl = libra.environments[environment.name]?.baseUrl;
    change();
    if (previousStation != indicatorStationId) {
      _loadIndicatorStation();
      printing = _loadPrintSettings();
    }
    if (previousEnvironment != environment ||
        previousUrl != libra.environments[environment.name]?.baseUrl) {
      libraAuth.clear();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsPrinterService) printerService.dispose();
    unawaited(serialIndicator.close());
    libraAuth.clear();
    indicators.dispose();
    indicatorState.dispose();
    permissions.dispose();
    accessControl.dispose();
    super.dispose();
  }
}
