import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/indicators/serial_indicator_service.dart';
import '../../core/widgets/visual_components.dart';
import '../../core/widgets/read_only_value_field.dart';
import '../ticket/ticket_session.dart';
import 'pesagem_layout.dart';
import 'pesagem_side_panel.dart';
import 'weight_panels.dart';
import 'operation_preview.dart';
import 'weighing_dialogs.dart';
import 'weighing_preview.dart';
import '../../core/offline/offline_station.dart';
import 'local_weighing_notice.dart';
import '../../core/offline/offline_models.dart';
import '../../core/offline/pre_ticket_source.dart';
import '../configuracoes/settings_models.dart';
import '../ticket/ticket_mapper.dart';
import '../ticket/ticket_preview.dart';
import '../ticket/printer_service.dart';
import '../ticket/ticket_pesagem.dart';
import '../ticket/ticket_print_renderer.dart';
import 'operation_lookup.dart';
import 'pre_ticket_service.dart';
import '../../core/libra/libra_api_client.dart';
import '../../core/libra/libra_configuration.dart';
import 'pesagem_edit_service.dart';
import 'pesagem_actions.dart';
import 'pesagem_action_bar.dart';
import 'manual_weighing_policy.dart';
import 'manual_capture/capture_dialog.dart';
import 'manual_capture/capture_models.dart';
import '../access_control/access_control_panel.dart';
import '../../core/permissions/permission_models.dart';

import 'package:flutter/foundation.dart' show kDebugMode;

/// Interface de pesagem com consulta real ou modo mock explícito.
class PesagemPage extends StatefulWidget {
  const PesagemPage({
    super.key,
    this.ticketSession,
    this.station,
    this.lookupService,
    this.editService,
    this.settings,
    this.actionDispatcher,
  });
  final TicketSession? ticketSession;
  final OfflineStation? station;
  final OperationLookupService? lookupService;
  final PesagemEditService? editService;
  final SettingsState? settings;
  final PesagemActionDispatcher? actionDispatcher;
  @override
  State<PesagemPage> createState() => _PesagemPageState();
}

class _PesagemPageState extends State<PesagemPage> {
  late final _actionDispatcher =
      widget.actionDispatcher ?? PesagemActionDispatcher();
  late final _settings = widget.settings ?? SettingsState();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final _operationalChanges = Listenable.merge([
    _settings,
    _settings.permissions,
  ]);
  void _refreshOperationalSettings() {
    if (_foundPlate != null &&
        (_consultedUnit != _settings.unitCode ||
            _consultedEnvironment != _settings.environment)) {
      _clearLookup();
    }
    if (mounted) setState(() {});
  }

  int? _consultedUnit;
  StationEnvironment? _consultedEnvironment;

  final _plate = TextEditingController();
  final _trailer = TextEditingController();
  final _observation = TextEditingController();
  static const _operationFields = [
    'Motorista',
    'Transportador',
    'Emissor(es)',
    'Depósito',
    'Item',
    'Destino',
    'Tipo do documento',
    'Nº Nota(s) / Documento(s)',
    invoiceWeightField,
    'Embalagem',
    'Operador',
    'Observação',
  ];
  late final _operationControllers = <String, TextEditingController>{
    for (final label in _operationFields)
      label: label == 'Observação' ? _observation : TextEditingController(),
  };
  late final _invoiceWeightInput = _operationControllers[invoiceWeightField]!;
  late final _weightPanelChanges = Listenable.merge([
    _settings.indicatorState,
    _invoiceWeightInput,
  ]);
  final _trailerFocus = FocusNode(debugLabel: 'Carreta');
  final _operationFocus = <String, FocusNode>{
    for (final label in _operationFields) label: FocusNode(debugLabel: label),
  };
  late final _libraConfiguration = LibraConfiguration();
  late final _lookupService =
      widget.lookupService ??
      (_libraConfiguration.mock
          ? DemoOperationLookupService()
          : PreTicketService(
              settings: _settings,
              configuration: _libraConfiguration,
            ));
  late final _editService = widget.editService ?? MemoryPesagemEditService();
  bool _actionModalOpen = false, _saving = false, _lookingUp = false;
  bool _ticketPrinting = false;
  int _lookupGeneration = 0;
  Map<String, String> get _draft => {
    ...?_ticketSession.current?.operation,
    ..._ticketSession.officialOperation,
    for (final entry in _operationControllers.entries)
      entry.key: entry.value.text,
  };
  late final FocusNode _plateFocus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
        _lookupOnBlur = !HardwareKeyboard.instance.isShiftPressed;
      }
      return KeyEventResult.ignored;
    },
  )..addListener(_onPlateFocus);
  bool _lookupOnBlur = false;
  String? _foundPlate;
  List<String> _trailers = [];
  static const _plateFieldWidth = 190.0;
  WeighingSummary _summary = const WeighingSummary();
  // Apenas memória desta tela: nunca persiste ou simula uma leitura física.
  WeighingPreview? _lastConfirmedPreview;
  bool _weighingFlowOpen = false;
  late final TicketSession _ticketSession =
      widget.ticketSession ?? TicketSession();

  @override
  void initState() {
    super.initState();
    _actionDispatcher.bind(_runAction);
    _operationalChanges.addListener(_refreshOperationalSettings);
    final current = _ticketSession.current;
    if (current != null) {
      _plate.text = current.plate;
      _trailer.text = current.trailer;
      final values = _ticketSession.draftOperation.isNotEmpty
          ? _ticketSession.draftOperation
          : current.operation;
      for (final entry in _operationControllers.entries) {
        entry.value.text = values[entry.key] ?? '';
      }
      _summary = current.summary;
      _foundPlate = _ticketSession.consultedPlate;
      _consultedUnit = _ticketSession.consultedUnitCode;
      _consultedEnvironment = _ticketSession.consultedEnvironment;
      _trailers = List.of(_ticketSession.trailerOptions);
      _lastConfirmedPreview = _ticketSession.confirmed;
    }
    for (final controller in [_plate, _trailer]) {
      controller.addListener(_publishTicketData);
    }
    for (final controller in _operationControllers.values) {
      controller.addListener(_onDraftChanged);
    }
    _trailerFocus.skipTraversal = _trailers.length == 1;
    _publishTicketData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_foundPlate != null &&
          _consultedUnit != null &&
          (_consultedUnit != _settings.unitCode ||
              _consultedEnvironment != _settings.environment)) {
        _clearLookup();
      }
      _plateFocus.requestFocus();
    });
  }

  void _onDraftChanged() {
    _ticketSession.draftOperation = _draft;
    if (_ticketSession.phase == WeighingPhase.nova) _publishTicketData();
  }

  void _publishTicketData({bool commitOperation = false}) {
    final current = WeighingPreview(
      plate: normalizePlate(_plate.text),
      trailer: normalizePlate(_trailer.text),
      operation:
          commitOperation ||
              _ticketSession.phase == WeighingPhase.nova ||
              _ticketSession.current == null
          ? _draft
          : _ticketSession.current!.operation,
      currentWeight: _ticketSession.current?.currentWeight ?? 0,
      summary: _summary,
      capturedAt: _ticketSession.current?.capturedAt,
      indicatorSource: _ticketSession.current?.indicatorSource,
      manualOperator: _ticketSession.current?.manualOperator,
      manualJustification: _ticketSession.current?.manualJustification,
      manualEvidence: _ticketSession.current?.manualEvidence,
    );
    final confirmed = _ticketSession.confirmed;
    if (confirmed != null &&
        (confirmed.plate != current.plate ||
            confirmed.trailer != current.trailer)) {
      _ticketSession.clearConfirmation();
    }
    _ticketSession.current = current;
    _ticketSession.consultedPlate = _foundPlate;
    _ticketSession.consultedUnitCode = _consultedUnit;
    _ticketSession.consultedEnvironment = _consultedEnvironment;
    _ticketSession.trailerOptions = List.of(_trailers);
    _ticketSession.draftOperation = _draft;
  }

  bool get _canSave =>
      _ticketSession.phase == WeighingPhase.aberta &&
      !_saving &&
      _settings.permissions.allows(AppPermission.editOpen);

  bool _actionEnabled(PesagemAction action) => switch (action) {
    PesagemAction.salvar => _canSave,
    PesagemAction.manual => ManualWeighingPolicy.available(
      enabled: _settings.manualWeighingEnabled,
      reading: _settings.indicatorState.reading,
      permissions: _settings.permissions,
    ),
    PesagemAction.pesar ||
    PesagemAction.nova => _settings.permissions.allows(AppPermission.weigh),
    PesagemAction.imprimir =>
      _settings.permissions.allows(AppPermission.printTicket) ||
          _settings.permissions.allows(AppPermission.reprintTicket),
  };

  Future<void> _runAction(
    PesagemAction action, {
    bool alternative = false,
  }) async {
    if (!_actionEnabled(action)) return;
    if (_weighingFlowOpen ||
        _actionModalOpen ||
        _saving ||
        _lookingUp ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    switch (action) {
      case PesagemAction.nova:
        _clearLookup();
      case PesagemAction.manual:
        await _startWeighing(manual: true);
      case PesagemAction.pesar:
        await _startWeighing();
      case PesagemAction.salvar:
        if (!_canSave) return;
        setState(() => _saving = true);
        try {
          await _editService.save(_ticketSession, _draft);
          if (mounted) _message('Dados da pesagem atualizados.');
        } catch (error) {
          if (mounted) {
            _message('Não foi possível atualizar os dados da pesagem.');
          }
        } finally {
          if (mounted) setState(() => _saving = false);
        }
      case PesagemAction.imprimir:
        final printing = _settings.savedPrinting;
        if (printing.simulated) {
          _actionModalOpen = true;
          try {
            await showTicketPreview(
              context,
              ticket: ticketFromSession(_ticketSession, _settings),
              format: printing.preferred,
            );
          } finally {
            _actionModalOpen = false;
          }
          return;
        }
        final ticket =
            _ticketSession.printableStation == _settings.indicatorStationId
            ? _ticketSession.printableTicket
            : null;
        if (ticket == null) {
          _message('Confirme uma pesagem para imprimir o ticket.');
          return;
        }
        await _printTicket(ticket, printing, alternative: alternative);
    }
  }

  Future<void> _printTicket(
    TicketPesagem ticket,
    PrintSettings printing, {
    bool alternative = false,
    bool? automaticClosing,
  }) async {
    if (_ticketPrinting || _settings.printerService.busy) {
      _message(
        'Já há um trabalho de impressão em processamento. Use F5 para tentar depois.',
        replaceQueued: true,
      );
      return;
    }
    final preferred = printing.preferred;
    final alternate = preferred.alternative;
    Future<PrintResult> send(PrinterFormat format, PrintSettings settings) {
      _message('Preparando ticket para ${format.label}…', replaceQueued: true);
      return _settings.printerService.print(
        settings: settings,
        format: format,
        document: () => PrintDocument.ticket(ticket),
        ticketId: ticket.ticketNumber,
        canSubmit: automaticClosing == null
            ? null
            : () {
                final effective = _automaticPrinting(
                  ticket,
                  closing: automaticClosing,
                );
                final destination = effective?.destination(format);
                return destination?.configured == true &&
                    destination!.queue == settings.destination(format).queue;
              },
      );
    }

    setState(() => _ticketPrinting = true);
    try {
      final format = alternative ? alternate : preferred;
      final result = await send(format, printing);
      if (!mounted) return;
      if (alternative ||
          !result.canOfferAlternative ||
          (automaticClosing != null &&
              _automaticPrinting(ticket, closing: automaticClosing) == null) ||
          !printing.destination(alternate).configured ||
          !identical(ticket, _ticketSession.printableTicket) ||
          _actionModalOpen ||
          _weighingFlowOpen ||
          ModalRoute.of(context)?.isCurrent != true) {
        _message('${format.label} · ${result.message}', replaceQueued: true);
        return;
      }
      _actionModalOpen = true;
      bool? useAlternative;
      try {
        useAlternative = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${format.label} indisponível'),
            content: Text(
              '${result.message}\n\nEnviar para ${printing.destination(alternate).queue}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Imprimir em ${alternate.label}'),
              ),
            ],
          ),
        );
      } finally {
        _actionModalOpen = false;
      }
      if (mounted &&
          useAlternative == true &&
          _actionEnabled(PesagemAction.imprimir) &&
          identical(ticket, _ticketSession.printableTicket)) {
        final effective = automaticClosing == null
            ? printing
            : _automaticPrinting(ticket, closing: automaticClosing);
        if (effective == null ||
            !effective.destination(alternate).configured ||
            effective.destination(alternate).queue !=
                printing.destination(alternate).queue) {
          return;
        }
        final alternativeResult = await send(alternate, effective);
        if (mounted) {
          _message(
            '${alternate.label} · ${alternativeResult.message}',
            replaceQueued: true,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _ticketPrinting = false);
    }
  }

  PrintSettings? _automaticPrinting(
    TicketPesagem ticket, {
    required bool closing,
  }) {
    if (!mounted) return null;
    final printing = _settings.savedPrinting;
    if (_settings.printSettingsLoadFailed ||
        printing.simulated ||
        !printing.printsAutomatically(closing: closing) ||
        !_settings.printing.printsAutomatically(closing: closing) ||
        !_settings.permissions.allows(AppPermission.printTicket) ||
        _ticketSession.printableStation != _settings.indicatorStationId ||
        _ticketSession.phase !=
            (closing ? WeighingPhase.fechada : WeighingPhase.aberta) ||
        !identical(ticket, _ticketSession.printableTicket) ||
        !PrinterFormat.values.any(
          (format) => printing.destination(format).enabled,
        )) {
      return null;
    }
    return printing;
  }

  Widget? get _alternativePrint {
    if (!_actionEnabled(PesagemAction.imprimir)) return null;
    final printing = _settings.savedPrinting;
    final alternative = printing.preferred.alternative;
    if (printing.simulated || !printing.destination(alternative).configured) {
      return null;
    }
    return PopupMenuButton<PrinterFormat>(
      key: const ValueKey('pesagem-alternative-print'),
      tooltip: 'Outro destino de impressão',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 130),
      icon: const Icon(Icons.arrow_drop_down, size: 18),
      enabled: !_ticketPrinting && !_settings.printerService.busy,
      onSelected: (_) => _runAction(PesagemAction.imprimir, alternative: true),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: alternative,
          child: Text('Imprimir em ${alternative.label}'),
        ),
      ],
    );
  }

  Future<void> _startWeighing({bool manual = false}) async {
    if (_weighingFlowOpen) return;
    if (_ticketSession.phase != WeighingPhase.nova &&
        _ticketSession.phase != WeighingPhase.aberta) {
      _message('Inicie uma nova pesagem para registrar outra captura.');
      return;
    }
    final phaseAtCapture = _ticketSession.phase;
    final summaryAtCapture = _summary;
    final closing = phaseAtCapture == WeighingPhase.aberta;
    final plate = normalizePlate(_plate.text);
    final openPlate =
        _ticketSession.openWeighingPlate ??
        _foundPlate ??
        _ticketSession.confirmed?.plate;
    if (closing &&
        openPlate != null &&
        openPlate.isNotEmpty &&
        openPlate != plate) {
      _message('Use a placa $openPlate para fechar a pesagem aberta.');
      return;
    }
    final stationAtCapture = _settings.indicatorStationId;
    _weighingFlowOpen = true;
    TicketPesagem? confirmedTicket;
    try {
      ManualAuthorization? authorization;
      ManualWeighingEvidence? evidence;
      DateTime? capturedAt;
      SerialCapture? serialCapture;
      double weight = 0;
      if (manual) {
        authorization = await showManualAuthentication(
          context,
          permissions: _settings.permissions,
        );
        if (!mounted ||
            authorization == null ||
            !_actionEnabled(PesagemAction.manual) ||
            !_settings.permissions.userAllows(
              authorization.user,
              AppPermission.authorizeManual,
            )) {
          return;
        }
        evidence = await showManualCapture(
          context,
          authorization: authorization,
          services: _settings.manualCapture,
          plate: plate,
        );
        if (!mounted || evidence == null) return;
        weight = evidence.finalWeight!;
        capturedAt = evidence.dateTime;
      } else if (_settings.serialIndicator.realMode) {
        try {
          serialCapture = _settings.serialIndicator.capture();
        } on FormatException catch (error) {
          _message(error.message);
          return;
        }
        weight = serialCapture.reading.wholeKg!.toDouble();
        capturedAt = serialCapture.reading.readAt;
      }
      final WeighingSummary? confirmedSummary;
      if (capturedAt == null || !weight.isFinite || weight <= 0) {
        confirmedSummary = null;
      } else if (closing) {
        final first = summaryAtCapture.first;
        confirmedSummary = WeighingSummary(
          first: first,
          firstWeighedAt: summaryAtCapture.firstWeighedAt,
          second: weight,
          secondWeighedAt: capturedAt,
          net: first.isFinite && first > 0
              ? double.parse((first - weight).abs().toStringAsFixed(3))
              : null,
        );
      } else {
        confirmedSummary = WeighingSummary(
          first: weight,
          firstWeighedAt: capturedAt,
        );
      }
      final preview = WeighingPreview(
        plate: plate,
        trailer: normalizePlate(_trailer.text),
        operation: _draft,
        currentWeight: weight,
        summary: closing
            ? confirmedSummary ?? summaryAtCapture
            : summaryAtCapture,
        manualOperator: authorization?.user,
        manualJustification: authorization?.justification,
        capturedAt: capturedAt,
        indicatorSource: serialCapture?.reading.source,
        manualEvidence: evidence,
      );
      final confirmed = await showWeighingConfirmation(
        context,
        preview,
        onSave: () {
          if (serialCapture != null &&
              !_settings.serialIndicator.canConfirm(serialCapture)) {
            throw const FormatException(
              'A comunicação ou a configuração do indicador mudou durante a confirmação. '
              'Cancele e faça uma nova captura.',
            );
          }
          if (!_actionEnabled(
            manual ? PesagemAction.manual : PesagemAction.pesar,
          )) {
            throw StateError('Permissão de pesagem indisponível.');
          }
          if (authorization != null &&
              !_settings.permissions.userAllows(
                authorization.user,
                AppPermission.authorizeManual,
              )) {
            throw StateError('Permissão de pesagem indisponível.');
          }
          if (confirmedSummary != null &&
              (_settings.indicatorStationId != stationAtCapture ||
                  normalizePlate(_plate.text) != preview.plate ||
                  _ticketSession.phase != phaseAtCapture ||
                  !identical(_summary, summaryAtCapture))) {
            throw const FormatException(
              'Os dados da pesagem mudaram durante a confirmação. '
              'Cancele e faça uma nova captura.',
            );
          }
          setState(() {
            _lastConfirmedPreview = preview;
            if (confirmedSummary != null) {
              _summary = confirmedSummary;
              _ticketSession.phase = closing
                  ? WeighingPhase.fechada
                  : WeighingPhase.aberta;
              _ticketSession.openWeighingPlate = closing ? null : plate;
            }
          });
          // Um indicador desconectado não substitui uma captura manual existente.
          if (preview.isManual) _ticketSession.recordManualReading(preview);
          if (preview.capturedAt != null || _ticketSession.confirmed == null) {
            _ticketSession.confirmed = preview;
          }
          _publishTicketData(commitOperation: true);
          if (confirmedSummary != null &&
              !(_lookupService is DemoOperationLookupService &&
                  _foundPlate != null)) {
            final printing = _settings.savedPrinting;
            final ticket = ticketFromSession(
              _ticketSession,
              _settings,
              savedPrinting: printing,
            );
            _ticketSession.printableTicket = ticket;
            _ticketSession.printableStation = _settings.indicatorStationId;
            confirmedTicket = ticket;
          }
          _message(
            serialCapture == null
                ? 'Pesagem de ${formatWeight(_lastConfirmedPreview!.currentWeight)} Kg confirmada em simulação local. '
                      '${manual ? 'Auditoria da captura salva localmente. Nenhuma integração foi acionada.' : 'Nenhum dado foi persistido.'}'
                : 'Pesagem de ${formatWeight(weight)} Kg confirmada nesta sessão.',
          );
        },
      );
      if (confirmed != true) confirmedTicket = null;
    } finally {
      _weighingFlowOpen = false;
    }
    final ticket = confirmedTicket;
    if (mounted && ticket != null) {
      final printing = _automaticPrinting(ticket, closing: closing);
      if (printing != null) {
        unawaited(_printTicket(ticket, printing, automaticClosing: closing));
      }
    }
  }

  void _onPlateFocus() {
    if (!_plateFocus.hasFocus && _lookupOnBlur) {
      _lookupOnBlur = false;
      _lookup(showInvalid: false);
    }
  }

  Future<void> _lookup({bool showInvalid = true}) async {
    if (_foundPlate != null || _lookingUp) return;
    final plate = normalizePlate(_plate.text);
    if (!RegExp(r'^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$').hasMatch(plate)) {
      if (showInvalid) _message('Informe uma placa válida.');
      return;
    }
    final generation = ++_lookupGeneration;
    setState(() => _lookingUp = true);
    final unit = _settings.unitCode;
    final environment = _settings.environment;
    try {
      final connection = widget.station?.connection ?? StationConnection.online;
      final result = await _lookupService.lookup(plate, connection);
      if (!mounted ||
          generation != _lookupGeneration ||
          unit != _settings.unitCode ||
          environment != _settings.environment ||
          normalizePlate(_plate.text) != plate) {
        return;
      }
      // Resultado remoto tardio não vira cache local após queda da conexão.
      final offline =
          (widget.station?.connection ?? connection) ==
          StationConnection.offline;
      final integrated =
          result != null &&
          !(offline && result.origin == PreTicketOrigin.remota);
      setState(() {
        _foundPlate = integrated ? plate : null;
        _consultedUnit = integrated ? unit : null;
        _consultedEnvironment = integrated ? environment : null;
        if (integrated) _plate.text = plate;
        _ticketSession.operationMode = integrated
            ? OperationMode.integrada
            : OperationMode.manual;
        _ticketSession.officialOperation = integrated
            ? result.values
            : const {};
        _ticketSession.preTickets = integrated ? result.preTickets : const [];
        _trailers = integrated ? result.trailers : [];
        _trailerFocus.skipTraversal = _trailers.length == 1;
        if (integrated) {
          if (result.origin == PreTicketOrigin.local || _trailers.isNotEmpty) {
            _trailer.text = _trailers.length == 1 ? _trailers.single : '';
          }
          for (final e in result.values.entries) {
            _operationControllers[e.key]?.text = e.value;
          }
          _summary = result.summary;
          _ticketSession.phase = result.phase;
          _ticketSession.openWeighingPlate =
              result.phase == WeighingPhase.aberta ? plate : null;
        }
        // Sem integração, conserva os valores manuais; nunca preenche exemplos.
      });
      _publishTicketData(commitOperation: true);
      if (!integrated) {
        _message(
          _lookupService is DemoOperationLookupService
              ? 'Placa não encontrada nas operações simuladas.'
              : 'Nenhum pré-ticket encontrado para esta placa.',
        );
      }
      if (_trailerFocus.hasFocus && _trailerFocus.skipTraversal) {
        _trailerFocus.nextFocus();
      }
    } catch (error) {
      if (mounted &&
          generation == _lookupGeneration &&
          unit == _settings.unitCode &&
          environment == _settings.environment &&
          normalizePlate(_plate.text) == plate) {
        // Sem resultado, a entrada permanece manual, sem inventar operação.
        _message(
          error is LibraException
              ? error.message
              : 'Consulta indisponível. Preencha os dados manualmente.',
        );
      }
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _message(String text, {bool replaceQueued = false}) {
    final messenger = _messenger.currentState;
    if (replaceQueued) {
      messenger?.clearSnackBars();
    } else {
      messenger?.hideCurrentSnackBar();
    }
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  void _clearLookup() {
    setState(() {
      _lookupOnBlur = false;
      ++_lookupGeneration;
      _foundPlate = null;
      _consultedUnit = null;
      _consultedEnvironment = null;
      _trailers = [];
      _ticketSession.current = null;
      _ticketSession.phase = WeighingPhase.nova;
      _ticketSession.openWeighingPlate = null;
      _summary = const WeighingSummary();
      _plate.clear();
      _trailer.clear();
      _ticketSession.operationMode = OperationMode.manual;
      _ticketSession.officialOperation = const {};
      _ticketSession.preTickets = const [];
      for (final controller in _operationControllers.values) {
        controller.clear();
      }
      _trailerFocus.skipTraversal = false;
      _lastConfirmedPreview = null;
      _ticketSession.clearConfirmation();
    });
    _publishTicketData();
    _messenger.currentState?.hideCurrentSnackBar();
    _plateFocus.requestFocus();
  }

  @override
  void dispose() {
    _operationalChanges.removeListener(_refreshOperationalSettings);
    if (widget.settings == null) _settings.dispose();
    _actionDispatcher.unbind(_runAction);
    _plate.dispose();
    _plateFocus.dispose();
    _trailer.dispose();
    _trailerFocus.dispose();
    for (final controller in _operationControllers.values) {
      controller.dispose();
    }
    for (final node in _operationFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PesagemActionScope(
    dispatcher: _actionDispatcher,
    enabled: widget.actionDispatcher == null,
    child: FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = PesagemLayout.fromSize(
            constraints.biggest,
            localNotice: widget.station?.activeWeighing != null,
          );
          final width = math.min(constraints.maxWidth, 1600.0);
          const minimumFormWidth = 570.0;
          final minimumContentWidth =
              minimumFormWidth + layout.gap + layout.sideWidth;
          final narrow = width < minimumContentWidth;
          final side = _sidePanel(layout);
          final form = SingleChildScrollView(
            key: const ValueKey('pesagem-main-scroll'),
            child: _mainContent(layout),
          );
          Widget columns(Widget content) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              SizedBox(width: layout.gap),
              side,
            ],
          );
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: narrow
                  ? _mainCard(
                      layout,
                      SingleChildScrollView(
                        key: const ValueKey('pesagem-content-horizontal'),
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: minimumContentWidth,
                          child: columns(form),
                        ),
                      ),
                    )
                  : columns(_mainCard(layout, form)),
            ),
          );
        },
      ),
    ),
  );

  Widget _sidePanel(PesagemLayout layout) => SizedBox(
    width: layout.sideWidth,
    child: PesagemSidePanel(
      layout: layout,
      integratedSgv: _settings.integratedSgv,
      accessControl: _settings.integratedSgv
          ? AccessControlPanel(
              state: _settings.accessControl,
              gates: _settings.barriers,
              trafficLights: _settings.trafficLight,
              display: _settings.informationDisplay,
              entryEquipmentId: _settings.entryBarrierId,
              exitEquipmentId: _settings.exitBarrierId,
              equipmentSource: _settings.gateEquipmentSource,
              displayMessage: _settings.displayMessage,
              simulationEnabled:
                  kDebugMode ||
                  _settings.environment == StationEnvironment.desenvolvimento,
            )
          : null,
    ),
  );

  Widget _mainCard(PesagemLayout layout, Widget content) => VisualCard(
    key: const ValueKey('pesagem-main-card'),
    radius: 14,
    shadow: true,
    padding: EdgeInsets.symmetric(
      horizontal: layout.cardPadding,
      vertical: layout.shortHeight ? 2 : layout.cardPadding,
    ),
    child: ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: content,
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(top: layout.verticalGap),
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _settings.indicatorState,
              _settings.printerService,
            ]),
            builder: (_, _) => PesagemActionBar(
              layout: layout,
              alternativePrint: _alternativePrint,
              actions: {
                for (final action in PesagemAction.values)
                  action:
                      !_actionEnabled(action) ||
                          (action == PesagemAction.imprimir &&
                              (_ticketPrinting ||
                                  _settings.printerService.busy))
                      ? null
                      : () => _actionDispatcher.invoke(action),
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _mainContent(PesagemLayout layout) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(layout),
      SizedBox(height: layout.verticalGap),
      _search(layout),
      SizedBox(height: layout.verticalGap),
      _operation(layout),
      SizedBox(height: layout.verticalGap),
      ListenableBuilder(
        listenable: _weightPanelChanges,
        builder: (_, _) => WeightPanels(
          layout: layout,
          summary: _summary,
          reading: _settings.indicatorState.reading,
          invoiceWeight: parseInvoiceWeight(
            _ticketSession.officialOperation[invoiceWeightField] ??
                _invoiceWeightInput.text,
            decimalPoint: _ticketSession.invoiceWeightUsesDecimalPoint,
          ),
        ),
      ),
    ],
  );

  Widget _title(PesagemLayout layout) => Container(
    padding: EdgeInsets.only(bottom: layout.tightHeight ? 2 : 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: widget.station != null
              ? LocalWeighingNotice(station: widget.station!)
              : const PageHeading(
                  title: 'Pesagem',
                  subtitle: 'Consulte e registre as informações da operação de pesagem.',
                  asset: 'balanca_icon',
                ),
        ),
        SizedBox(width: layout.gap),
        Container(
          width: layout.shortHeight ? 126 : (layout.compact ? 148 : 180),
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: layout.shortHeight ? 2 : (layout.spacious ? 8 : 4),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.inputBorder),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0f000000),
                offset: Offset(0, 2),
                blurRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pesagem Nº',
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _ticketSession.ticketNumber,
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: layout.compact ? 26 : 30,
                  height: 1,
                  letterSpacing: 1,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _field(
    PesagemLayout layout,
    String label, {
    String? hint,
    bool readOnly = false,
    bool disabled = false,
    bool future = false,
    TextEditingController? controller,
    int? maxLength,
    FocusNode? focusNode,
    ValueChanged<String>? onSubmitted,
    Widget? suffixIcon,
    bool? isDense,
    String? displayLabel,
  }) => FocusTraversalOrder(
    order: NumericFocusOrder(
      label == 'Placa'
          ? 1
          : label == 'Carreta'
          ? 2
          : 3 + _operationFields.indexOf(label).toDouble(),
    ),
    child: VisualField(
      displayLabel ?? label,
      hint: hint,
      readOnly: readOnly,
      disabled: disabled,
      future: future,
      controller: controller,
      maxLength: maxLength,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      suffixIcon: suffixIcon,
      isDense: isDense,
      compact: !layout.spacious,
      fieldHeight: layout.fieldHeight,
      labelGap: layout.labelGap,
    ),
  );

  Widget _searchSection(String title, Widget field) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppColors.green,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(width: _plateFieldWidth, child: field),
    ],
  );

  Widget _search(PesagemLayout layout) {
    final plate = _searchSection(
      'Consultar placa',
      _field(
        layout,
        'Placa',
        hint: 'Ex.: ABC1D23',
        controller: _plate,
        maxLength: 8,
        focusNode: _plateFocus,
        readOnly: _foundPlate != null,
        onSubmitted: (_) => _lookup(),
        suffixIcon: ExcludeFocus(
          child: IconButton(
            tooltip: _foundPlate == null
                ? 'Consultar placa'
                : 'Limpar consulta',
            iconSize: 20,
            color: _foundPlate == null ? AppColors.green : AppColors.muted,
            icon: _lookingUp
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: 'Consultando Libra',
                    ),
                  )
                : Icon(
                    _foundPlate == null
                        ? Icons.search
                        : Icons.cleaning_services_outlined,
                  ),
            onPressed: _lookingUp
                ? null
                : () => _foundPlate == null ? _lookup() : _clearLookup(),
          ),
        ),
      ),
    );
    return VisualCard(
      padding: EdgeInsets.symmetric(
        horizontal: layout.sectionPadding,
        vertical: layout.shortHeight
            ? 2
            : (layout.tightHeight ? 3 : (layout.spacious ? 10 : 6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: layout.compact ? 240 : 260, child: plate),
          Expanded(
            child: Container(
              padding: EdgeInsets.only(left: layout.spacious ? 24 : 14),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Color(0xffd7dfdc))),
              ),
              child: _searchSection(
                'Composição do veículo',
                _trailerField(layout),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trailerField(PesagemLayout layout) {
    if (_trailers.length < 2) {
      return _field(
        layout,
        'Carreta',
        hint: 'Ex.: DEF4G56',
        controller: _trailer,
        focusNode: _trailerFocus,
        maxLength: 8,
        readOnly: _trailers.isNotEmpty,
        // The dense decorator otherwise shrinks its visible border without
        // Placa's suffix button. Fill the shared layout.fieldHeight instead.
        isDense: false,
      );
    }
    return FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VisualFieldLabel('Carreta'),
          SizedBox(height: layout.labelGap),
          SizedBox(
            width: _plateFieldWidth,
            height: layout.fieldHeight,
            child: DropdownButtonFormField<String>(
              focusNode: _trailerFocus,
              key: ValueKey(_foundPlate),
              initialValue: _trailer.text.isEmpty ? null : _trailer.text,
              isExpanded: true,
              alignment: AlignmentDirectional.centerStart,
              style: const TextStyle(fontSize: 14, color: AppColors.text),
              decoration: InputDecoration(
                isDense: false,
                constraints: BoxConstraints.tightFor(
                  height: layout.fieldHeight,
                ),
                hintText: 'Selecione a carreta',
                contentPadding: VisualField.fixedHeightContentPadding,
              ),
              items: [
                for (final plate in _trailers)
                  DropdownMenuItem(value: plate, child: Text(plate)),
              ],
              onChanged: (value) => setState(() => _trailer.text = value ?? ''),
            ),
          ),
        ],
      ),
    );
  }

  Widget _operation(PesagemLayout layout) {
    const title = Text(
      'Dados da Operação',
      style: TextStyle(
        fontSize: 17,
        color: AppColors.heading,
        fontWeight: FontWeight.bold,
      ),
    );
    const subtitle = Text(
      'Informações da operação de pesagem.',
      style: TextStyle(fontSize: 13, color: AppColors.muted),
    );
    final iconSize = layout.tightHeight ? 26.0 : (layout.compact ? 30.0 : 38.0);
    return VisualCard(
      key: const ValueKey('pesagem-operation-card'),
      padding: EdgeInsets.symmetric(
        horizontal: layout.sectionPadding,
        vertical: layout.operationVerticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: const BoxDecoration(
                  color: AppColors.paleGreen,
                  shape: BoxShape.circle,
                ),
                child: const Center(child: AppAsset('truck', size: 22)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: layout.tightHeight
                    ? const Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [title, subtitle],
                      )
                    : const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, SizedBox(height: 3), subtitle],
                      ),
              ),
            ],
          ),
          SizedBox(height: layout.operationHeadingGap),
          Column(
            children: [
              _operationRow(layout, [
                _operationValue(layout, 'Motorista'),
                _operationValue(layout, 'Transportador'),
              ]),
              SizedBox(height: layout.operationRowGap),
              _operationRow(layout, [
                _operationValue(layout, 'Emissor(es)'),
                _operationValue(layout, 'Depósito'),
              ]),
              SizedBox(height: layout.operationRowGap),
              _operationRow(
                layout,
                [
                  _operationValue(layout, 'Item'),
                  _operationValue(layout, 'Tipo do documento'),
                  _operationValue(layout, 'Nº Nota(s) / Documento(s)'),
                ],
                flexes: const [10, 12, 18],
              ),
              SizedBox(height: layout.operationRowGap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: _operationValue(layout, invoiceWeightField),
                  ),
                  SizedBox(width: layout.spacious ? 16 : 12),
                  Expanded(child: _operationValue(layout, 'Embalagem')),
                  SizedBox(width: layout.spacious ? 16 : 12),
                  Expanded(child: _operationValue(layout, 'Operador')),
                  SizedBox(width: layout.spacious ? 16 : 12),
                  Expanded(
                    flex: 2,
                    child: _operationValue(layout, 'Observação'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _operationValue(PesagemLayout layout, String label) {
    final displayLabel = label == 'Transportador' ? 'Transportadora' : label;
    if (_ticketSession.officialOperation.containsKey(label)) {
      return FocusTraversalOrder(
        order: NumericFocusOrder(
          3 + _operationFields.indexOf(label).toDouble(),
        ),
        child: ReadOnlyValueField(
          label: displayLabel,
          value: _ticketSession.officialOperation[label]!,
          height: layout.fieldHeight,
          labelGap: layout.labelGap,
        ),
      );
    }
    return _field(
      layout,
      label,
      displayLabel: displayLabel,
      controller: _operationControllers[label],
      focusNode: _operationFocus[label],
      disabled: label == 'Operador',
      future: label == 'Operador',
      hint: label == 'Operador' ? 'Integração futura' : null,
    );
  }

  Widget _operationRow(
    PesagemLayout layout,
    List<Widget> fields, {
    List<int>? flexes,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < fields.length; i++) ...[
        if (i > 0) SizedBox(width: layout.spacious ? 16 : 12),
        Expanded(flex: flexes?[i] ?? 1, child: fields[i]),
      ],
    ],
  );
}
