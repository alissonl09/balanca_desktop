import 'package:flutter/material.dart';

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
import '../features/relatorios/relatorios_page.dart';
import '../features/ticket/ticket_session.dart';
import '../core/permissions/permission_models.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.station});
  final OfflineStation? station;
  @override
  State<AppShell> createState() => _AppShellState();
}

enum _AppPage { pesagem, cadastros, relatorios, configuracoes }

class _AppShellState extends State<AppShell> {
  _AppPage _page = _AppPage.pesagem;
  final _cadastrosMemory = CadastrosMemory.mock();
  final _settings = SettingsState();
  final _ticketSession = TicketSession();
  final _pesagemActions = PesagemActionDispatcher();
  late final _station = widget.station ?? OfflineStation();

  @override
  void initState() {
    super.initState();
    _settings.permissions.addListener(_permissionsChanged);
  }

  void _permissionsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cadastrosMemory.dispose();
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
                                        memory: _cadastrosMemory,
                                        permissions: _settings.permissions,
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
                                  vertical: size.height >= 1000 ? 18 : 10,
                                ),
                                child: PesagemPage(
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
    required this.station,
  });
  final bool small, compact;
  final OfflineStation station;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 62 : 70,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: small ? 16 : 30),
      child: Row(
        children: [
          AppAsset(
            'logo-topo',
            size: small
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
