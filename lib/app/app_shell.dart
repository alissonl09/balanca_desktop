import 'package:flutter/material.dart';

import 'dart:convert';
import 'dart:math';
import 'dart:ui' show AppExitResponse;

import '../core/database/database_manager.dart';
import '../core/offline/sqlite_pesagem_store.dart';
import '../features/access_control/access_control_state.dart';

import '../core/theme/app_colors.dart';
import '../core/widgets/visual_components.dart';
import '../core/widgets/station_connection_indicator.dart';
import '../core/offline/offline_station.dart';
import '../features/cadastros/cadastros_page.dart';
import '../features/cadastros/cadastros_memory.dart';
import '../features/configuracoes/configuracoes_page.dart';
import '../features/configuracoes/settings_models.dart';
import '../features/pesagem/pesagem_page.dart';
import '../features/pesagem/pesagem_actions.dart';
import '../features/pesagem/operation_lookup.dart';
import '../core/libra/libra_configuration.dart';
import '../core/libra/libra_settings_store.dart';
import '../core/indicators/indicator_settings_store.dart';
import '../core/offline/offline_models.dart';
import '../features/relatorios/relatorios_page.dart';
import '../features/ticket/ticket_session.dart';
import '../features/ticket/printer_service.dart';
import '../core/permissions/permission_models.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.station,
    this.lookupService,
    this.libraStore,
    this.libraSettings,
    this.database,
    this.indicatorStore,
    this.indicatorSettings = const IndicatorSettingsData(),
    this.printStore,
    this.printStations = const {},
    this.printSettingsLoadFailed = false,
    this.printerService,
  });
  final LibraSettingsStore? libraStore;
  final LibraSettingsData? libraSettings;
  final DatabaseManager? database;
  final LocalIndicatorSettingsStore? indicatorStore;
  final IndicatorSettingsData indicatorSettings;
  final LocalPrintSettingsStore? printStore;
  final Map<String, Map<String, dynamic>> printStations;
  final bool printSettingsLoadFailed;
  final PrinterService? printerService;
  final OfflineStation? station;
  final OperationLookupService? lookupService;
  @override
  State<AppShell> createState() => _AppShellState();
}

enum _AppPage { pesagem, cadastros, relatorios, configuracoes }

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  _AppPage _page = _AppPage.pesagem;
  late final _cadastrosReal = CadastrosMemory.real(_settings.permissions);
  CadastrosMemory? _cadastrosDemo;
  late CadastrosMemory _cadastros = _cadastrosReal;
  late final _settings = SettingsState(
    libraStore: widget.libraStore,
    libraSettings: widget.libraSettings,
    database: widget.database,
    indicatorStore: widget.indicatorStore,
    indicatorSettings: widget.indicatorSettings,
    printStore: widget.printStore,
    printStations: widget.printStations,
    printSettingsLoadFailed: widget.printSettingsLoadFailed,
    printerService: widget.printerService,
  );
  var _ticketSession = TicketSession();
  String? _stationLoadError;
  final _pesagemActions = PesagemActionDispatcher();
  late final _station =
      widget.station ??
      OfflineStation(
        store: widget.database == null
            ? null
            : SqlitePesagemStore(widget.database!),
        idFactory: widget.database == null
            ? null
            : () => base64UrlEncode(
                List<int>.generate(24, (_) => Random.secure().nextInt(256)),
              ),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.database?.isOperationActive = () =>
        _ticketSession.phase == WeighingPhase.aberta ||
        _station.weighings.any(
          (w) =>
              w.phase == WeighingPhase.aberta ||
              w.phase == WeighingPhase.ticketPendente,
        ) ||
        GateSide.values.any(
          (side) => _settings.accessControl.gate(side) != GateState.closed,
        );
    widget.database?.onRestored = () async {
      await _station.reload();
      if (mounted) {
        setState(() {
          _ticketSession = TicketSession();
          _stationLoadError = null;
        });
      }
    };
    final configuration = LibraConfiguration();
    // Estado operacional inicial configurado, sem sincronização automática.
    if (widget.station == null &&
        (widget.database == null || widget.database!.available)) {
      _initializeStation(configuration);
    }
    _settings.permissions.addListener(_permissionsChanged);
  }

  Future<void> _initializeStation(LibraConfiguration configuration) async {
    try {
      // Carrega a outbox mesmo ao iniciar offline; não depende de login/rede.
      await _station.load();
      if (widget.lookupService == null &&
          !configuration.mock &&
          !configuration.offline) {
        await _station.setConnection(StationConnection.online);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _stationLoadError = 'Não foi possível carregar as pesagens locais. Acesse Configurações > Banco de Dados para diagnóstico.',
        );
      }
    }
  }

  void _permissionsChanged() {
    if (mounted) setState(() {});
  }

  void _setCadastroSimulation(bool enabled) => setState(() {
    _cadastros = enabled
        ? (_cadastrosDemo ??= CadastrosMemory.mock(_settings.permissions))
        : _cadastrosReal;
  });

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _settings.serialIndicator.close();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.database?.isOperationActive = null;
    widget.database?.onRestored = null;
    _cadastrosReal.dispose();
    _cadastrosDemo?.dispose();
    _settings.permissions.removeListener(_permissionsChanged);
    _settings.dispose();
    if (widget.station == null) _station.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final small = size.width <= 900;
    final compact = size.width > 1250 && size.height <= 950;
    final shortWeighing = _page == _AppPage.pesagem && size.height < 620;
    return PesagemActionScope(
      dispatcher: _pesagemActions,
      enabled: _page == _AppPage.pesagem,
      child: Scaffold(
        backgroundColor: AppColors.green,
        body: Column(
          children: [
            _Header(
              small: small,
              compact: _page == _AppPage.pesagem ? size.height <= 950 : compact,
              short: shortWeighing,
              station: _station,
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: small ? 78 : 124,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.only(top: 34, left: small ? 6 : 10),
                        child: Column(
                          children: [
                            _menu(
                              'Pesagem',
                              'balanca_icon',
                              _page == _AppPage.pesagem,
                              small,
                              () => setState(() => _page = _AppPage.pesagem),
                            ),
                            const SizedBox(height: 16),
                            _menu(
                              'Cadastros',
                              'cadastros',
                              _page == _AppPage.cadastros,
                              small,
                              () => setState(() => _page = _AppPage.cadastros),
                              icon: Icons.badge_outlined,
                            ),
                            const SizedBox(height: 16),
                            _menu(
                              'Relatórios',
                              'relatorios',
                              _page == _AppPage.relatorios,
                              small,
                              () => setState(() => _page = _AppPage.relatorios),
                              icon: Icons.assessment_outlined,
                            ),
                            const SizedBox(height: 16),
                            _menu(
                              'Configurações',
                              'config',
                              _page == _AppPage.configuracoes,
                              small,
                              () => setState(
                                () => _page = _AppPage.configuracoes,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                      ),
                      child: ColoredBox(
                        color: AppColors.background,
                        child: _page != _AppPage.pesagem
                            ? SingleChildScrollView(
                                key: ValueKey(_page),
                                padding: compact
                                    ? const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      )
                                    : EdgeInsets.all(small ? 14 : 24),
                                child: _page == _AppPage.cadastros
                                    ? CadastrosPage(
                                        compact: compact,
                                        memory: _cadastros,
                                        onSimulationChanged:
                                            _setCadastroSimulation,
                                      )
                                    : _page == _AppPage.relatorios
                                    ? RelatoriosPage(compact: compact)
                                    : ConfiguracoesPage(
                                        compact: compact,
                                        settings: _settings,
                                        ticketSession: _ticketSession,
                                      ),
                              )
                            : Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal:
                                      size.width >= 1800 && size.height >= 1000
                                      ? 24
                                      : 12,
                                  vertical: shortWeighing
                                      ? 3
                                      : size.height >= 1000
                                      ? 18
                                      : 10,
                                ),
                                child:
                                    (widget.database != null &&
                                            !widget.database!.available) ||
                                        _stationLoadError != null
                                    ? Center(
                                        child: Text(
                                          _stationLoadError ?? 'Banco local indisponível. Acesse Configurações > Banco de Dados para diagnóstico.',
                                        ),
                                      )
                                    : PesagemPage(
                                        lookupService: widget.lookupService,
                                        actionDispatcher: _pesagemActions,
                                        ticketSession: _ticketSession,
                                        station: _station,
                                        settings: _settings,
                                      ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(
    String label,
    String id,
    bool active,
    bool small,
    VoidCallback onTap, {
    IconData? icon,
  }) => Semantics(
    selected: active,
    child: Material(
      color: active ? Colors.white : Colors.transparent,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
      child: InkWell(
        key: ValueKey('menu-$id'),
        onTap: _canOpenMenu(id) ? onTap : null,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
        hoverColor: Colors.white.withValues(alpha: .08),
        child: Container(
          constraints: BoxConstraints(minHeight: small ? 66 : 78),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null)
                Icon(
                  icon,
                  size: small ? 28 : 34,
                  color: active ? AppColors.green : Colors.white,
                )
              else
                AppAsset(
                  id,
                  size: small ? 28 : 34,
                  color: active ? AppColors.green : Colors.white,
                ),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: small ? 10 : 12,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.green : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  bool _canOpenMenu(String id) => switch (id) {
    'cadastros' => _settings.permissions.allows(AppPermission.readRegistry),
    'relatorios' => _settings.permissions.allows(AppPermission.readReports),
    'config' =>
      AppPermission.values
          .where((p) => p.group == 'Configurações')
          .any(_settings.permissions.allows),
    _ => true,
  };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.small,
    required this.compact,
    required this.short,
    required this.station,
  });
  final bool small, compact, short;
  final OfflineStation station;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: short ? 48 : (compact ? 62 : 70),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: small ? 16 : 30),
      child: Row(
        children: [
          AppAsset(
            'logo-topo',
            size: short
                ? 40
                : small
                ? 48
                : compact
                ? 50
                : 58,
            label: 'Logo Cooxupé',
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sistema de Gerenciamento de Pesagens',
                  style: TextStyle(
                    fontSize: small ? 13 : 17,
                    height: 1.2,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (!small) ...[
                  const SizedBox(height: 3),
                  const Text(
                    'Matriz Cooxupé  •  Sistema de Pesagem',
                    style: TextStyle(fontSize: 13, color: AppColors.paleGreen),
                  ),
                ],
              ],
            ),
          ),
          StationConnectionIndicator(station: station),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            key: const ValueKey('user-menu'),
            tooltip: 'Menu do usuário',
            onSelected: (action) => _onMenuSelected(context, action),
            color: Colors.white,
            elevation: 8,
            offset: const Offset(0, 9),
            constraints: const BoxConstraints.tightFor(width: 250),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        'AR',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alisson Romano',
                          style: TextStyle(
                            color: AppColors.heading,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Operador',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 10),
              _menuItem(
                'switch',
                Icons.switch_account_outlined,
                'Trocar usuário',
              ),
              _menuItem('logout', Icons.logout_outlined, 'Logout'),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xff289b70),
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    'AR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!small) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 105,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alisson Romano',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Operador',
                          style: TextStyle(
                            color: AppColors.paleGreen,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.green, size: 19),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.heading,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  void _onMenuSelected(BuildContext context, String action) {
    if (action == 'logout') {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sair do sistema?'),
          content: const Text('Deseja realmente sair do sistema?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logout: simulação local')),
                );
              },
              child: const Text('Sair'),
            ),
          ],
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trocar usuário: simulação local')),
    );
  }
}
