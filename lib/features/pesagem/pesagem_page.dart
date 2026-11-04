import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
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
import 'operation_lookup.dart';
import 'pesagem_edit_service.dart';
import 'pesagem_actions.dart';
import 'pesagem_action_bar.dart';
import 'manual_weighing_policy.dart';
import 'manual_capture/capture_dialog.dart';
import 'manual_capture/capture_models.dart';
import '../access_control/access_control_panel.dart';
import '../../core/permissions/permission_models.dart';

import 'package:flutter/foundation.dart' show kDebugMode;

/// Interface de pesagem com consulta local de demonstração.
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
  late final _operationalChanges = Listenable.merge([
    _settings,
    _settings.indicatorState,
    _settings.permissions,
  ]);
  void _refreshOperationalSettings() {
    if (mounted) setState(() {});
  }

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
    'Peso N.F. (Kg)',
    'Embalagem',
    'Operador',
    'Observação',
  ];
  late final _operationControllers = <String, TextEditingController>{
    for (final label in _operationFields)
      label: label == 'Observação' ? _observation : TextEditingController(),
  };
  final _trailerFocus = FocusNode(debugLabel: 'Carreta');
  final _operationFocus = <String, FocusNode>{
    for (final label in _operationFields) label: FocusNode(debugLabel: label),
  };
  late final _lookupService =
      widget.lookupService ?? DemoOperationLookupService();
  late final _editService = widget.editService ?? MemoryPesagemEditService();
  bool _actionModalOpen = false, _saving = false, _lookingUp = false;
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
      if (mounted) _plateFocus.requestFocus();
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

  Future<void> _runAction(PesagemAction action) async {
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
        _actionModalOpen = true;
        try {
          await showTicketPreview(
            context,
            ticket: ticketFromSession(_ticketSession, _settings),
            format: PrinterFormat.ticket,
          );
        } finally {
          _actionModalOpen = false;
        }
    }
  }

  Future<void> _startWeighing({bool manual = false}) async {
    if (_weighingFlowOpen) return;
    if (_ticketSession.phase != WeighingPhase.nova &&
        _ticketSession.phase != WeighingPhase.aberta) {
      _message('Inicie uma nova pesagem para registrar outra captura.');
      return;
    }
    _weighingFlowOpen = true;
    try {
      ManualAuthorization? authorization;
      ManualWeighingEvidence? evidence;
      DateTime? capturedAt;
      double weight = 0; // Indicador atual desconectado, sem leitura real.
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
          plate: normalizePlate(_plate.text),
        );
        if (!mounted || evidence == null) return;
        weight = evidence.finalWeight!;
        capturedAt = evidence.dateTime;
      }
      final preview = WeighingPreview(
        plate: normalizePlate(_plate.text),
        trailer: normalizePlate(_trailer.text),
        operation: _draft,
        currentWeight: weight,
        summary: _summary,
        manualOperator: authorization?.user,
        manualJustification: authorization?.justification,
        capturedAt: capturedAt,
        manualEvidence: evidence,
      );
      final confirmed = await showWeighingConfirmation(context, preview);
      if (!mounted || confirmed != true) return;
      if (!_actionEnabled(
        manual ? PesagemAction.manual : PesagemAction.pesar,
      )) {
        return;
      }
      if (authorization != null &&
          !_settings.permissions.userAllows(
            authorization.user,
            AppPermission.authorizeManual,
          )) {
        return;
      }
      setState(() {
        _lastConfirmedPreview = preview;
        // Só a confirmação de captura válida altera o ciclo. Salvar dados não.
        if (capturedAt != null && weight > 0) {
          if (_ticketSession.phase == WeighingPhase.nova) {
            _summary = WeighingSummary(
              first: weight,
              firstWeighedAt: capturedAt,
            );
            _ticketSession.phase = WeighingPhase.aberta;
          } else {
            _summary = WeighingSummary(
              first: _summary.first,
              firstWeighedAt: _summary.firstWeighedAt,
              second: weight,
              secondWeighedAt: capturedAt,
              net: _summary.net,
              dry: _summary.dry,
            );
            _ticketSession.phase = WeighingPhase.fechada;
          }
        }
      });
      // Um indicador desconectado não substitui uma captura manual existente.
      if (preview.isManual) _ticketSession.recordManualReading(preview);
      if (preview.capturedAt != null || _ticketSession.confirmed == null) {
        _ticketSession.confirmed = preview;
      }
      _publishTicketData(commitOperation: true);
      _message(
        'Pesagem de ${formatWeight(_lastConfirmedPreview!.currentWeight)} Kg confirmada em simulação local. '
        '${manual ? 'Auditoria da captura salva localmente. Nenhuma integração foi acionada.' : 'Nenhum dado foi persistido.'}',
      );
    } finally {
      _weighingFlowOpen = false;
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
    _lookingUp = true;
    try {
      final connection =
          widget.station?.connection ?? StationConnection.offline;
      final result = await _lookupService.lookup(plate, connection);
      if (!mounted ||
          generation != _lookupGeneration ||
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
        if (integrated) _plate.text = plate;
        _ticketSession.operationMode = integrated
            ? OperationMode.integrada
            : OperationMode.manual;
        _ticketSession.officialOperation = integrated
            ? result.values
            : const {};
        _trailers = integrated ? result.trailers : [];
        _trailerFocus.skipTraversal = _trailers.length == 1;
        if (integrated) {
          _trailer.text = _trailers.length == 1 ? _trailers.single : '';
          for (final e in result.values.entries) {
            _operationControllers[e.key]?.text = e.value;
          }
          _summary = result.summary;
          _ticketSession.phase = result.phase;
        }
        // Sem integração, conserva os valores manuais; nunca preenche exemplos.
      });
      _publishTicketData(commitOperation: true);
      if (!integrated) {
        _message('Placa não encontrada nas operações simuladas.');
      }
      if (_trailerFocus.hasFocus && _trailerFocus.skipTraversal) {
        _trailerFocus.nextFocus();
      }
    } catch (error) {
      if (mounted && generation == _lookupGeneration) {
        // Sem resultado, a entrada permanece manual, sem inventar operação.
        _message('Consulta indisponível. Preencha os dados manualmente.');
      }
    } finally {
      _lookingUp = false;
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _clearLookup() {
    setState(() {
      _lookupOnBlur = false;
      ++_lookupGeneration;
      _foundPlate = null;
      _trailers = [];
      _ticketSession.current = null;
      _ticketSession.phase = WeighingPhase.nova;
      _summary = const WeighingSummary();
      _plate.clear();
      _trailer.clear();
      _ticketSession.operationMode = OperationMode.manual;
      _ticketSession.officialOperation = const {};
      for (final controller in _operationControllers.values) {
        controller.clear();
      }
      _trailerFocus.skipTraversal = false;
      _lastConfirmedPreview = null;
      _ticketSession.clearConfirmation();
    });
    _publishTicketData();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
          // Abaixo da largura mínima operacional, conserva-se a legibilidade com
          // rolagem apenas horizontal. Não se empilham os painéis verticalmente.
          final width = math.max(
            1120.0,
            math.min(constraints.maxWidth, 1600.0),
          );
          final content = SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('pesagem-main-scroll'),
                    child: _mainCard(layout),
                  ),
                ),
                SizedBox(width: layout.gap),
                SizedBox(
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
                                _settings.environment ==
                                    StationEnvironment.desenvolvimento,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          );
          return Align(
            alignment: Alignment.topCenter,
            child: constraints.maxWidth < width
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: content,
                  )
                : content,
          );
        },
      ),
    ),
  );

  Widget _mainCard(PesagemLayout layout) => VisualCard(
    key: const ValueKey('pesagem-main-card'),
    radius: 14,
    shadow: true,
    padding: EdgeInsets.all(layout.cardPadding),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(layout),
        SizedBox(height: layout.gap),
        _search(layout),
        SizedBox(height: layout.gap),
        _operation(layout),
        SizedBox(height: layout.gap),
        WeightPanels(
          layout: layout,
          summary: _summary,
          reading: _settings.indicatorState.reading,
        ),
        SizedBox(height: layout.gap),
        PesagemActionBar(
          layout: layout,
          actions: {
            for (final action in PesagemAction.values)
              action: !_actionEnabled(action)
                  ? null
                  : () => _actionDispatcher.invoke(action),
          },
        ),
      ],
    ),
  );

  Widget _title(PesagemLayout layout) => Container(
    padding: EdgeInsets.only(bottom: layout.compact ? 4 : 10),
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
          width: layout.compact ? 148 : 180,
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: layout.spacious
                ? 12
                : layout.compact
                ? 4
                : 6,
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
    double? fieldHeight,
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
      fieldHeight: fieldHeight ?? layout.fieldHeight,
      labelGap: layout.labelGap,
    ),
  );

  Widget _sectionTitle(String title, PesagemLayout layout) => Padding(
    padding: EdgeInsets.only(bottom: layout.compact ? 6 : 10),
    child: Text(
      title,
      style: const TextStyle(
        color: AppColors.green,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _search(PesagemLayout layout) => VisualCard(
    padding: EdgeInsets.all(layout.sectionPadding),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: layout.compact ? 240 : 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Consultar placa', layout),
              SizedBox(
                width: _plateFieldWidth,
                child: _field(
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
                      color: _foundPlate == null
                          ? AppColors.green
                          : AppColors.muted,
                      icon: Icon(
                        _foundPlate == null
                            ? Icons.search
                            : Icons.cleaning_services_outlined,
                      ),
                      onPressed: () =>
                          _foundPlate == null ? _lookup() : _clearLookup(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            padding: EdgeInsets.only(left: layout.spacious ? 24 : 14),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xffd7dfdc))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Composição do veículo', layout),
                SizedBox(width: _plateFieldWidth, child: _trailerField(layout)),
              ],
            ),
          ),
        ),
      ],
    ),
  );

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
    return VisualCard(
      key: const ValueKey('pesagem-operation-card'),
      padding: EdgeInsets.all(layout.operationPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: layout.compact ? 30 : 38,
                height: layout.compact ? 30 : 38,
                decoration: const BoxDecoration(
                  color: AppColors.paleGreen,
                  shape: BoxShape.circle,
                ),
                child: const Center(child: AppAsset('truck', size: 22)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dados da Operação',
                      style: TextStyle(
                        fontSize: 17,
                        color: AppColors.heading,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Informações da operação de pesagem.',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
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
                    child: _operationValue(layout, 'Peso N.F. (Kg)'),
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
          height: layout.operationFieldHeight,
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
      fieldHeight: layout.operationFieldHeight,
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
