import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/visual_components.dart';
import 'cadastro_panel.dart';
import 'cadastro_record.dart';
import 'cadastros_memory.dart';
import '../../core/permissions/permission_models.dart';

/// Cadastros com dados temporários em memória; demais abas ainda provisórias.
class CadastrosPage extends StatefulWidget {
  const CadastrosPage({
    super.key,
    required this.compact,
    required this.memory,
    this.permissions,
  });
  final bool compact;
  final CadastrosMemory memory;
  final PermissionState? permissions;

  @override
  State<CadastrosPage> createState() => _CadastrosPageState();
}

class _CadastrosPageState extends State<CadastrosPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    'Remetentes / Destinatários',
    'Transportadoras',
    'Motoristas',
    'Placas',
    'Operações',
    'Itens / Produtos',
    'Unidades',
  ];
  late final _controller = TabController(length: _tabs.length, vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1400),
      child: VisualCard(
        key: const ValueKey('cadastros-main-card'),
        radius: 14,
        shadow: true,
        padding: widget.compact
            ? const EdgeInsets.symmetric(horizontal: 20, vertical: 16)
            : EdgeInsets.all(MediaQuery.sizeOf(context).width <= 900 ? 18 : 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeading(
              title: 'Cadastros',
              subtitle: 'Selecione o cadastro que deseja acessar.',
              // Ícone Material temporário, até a definição do asset próprio.
              icon: Icons.badge_outlined,
            ),
            SizedBox(height: widget.compact ? 14 : 22),
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    ...ScrollConfiguration.of(context).dragDevices,
                    PointerDeviceKind.mouse,
                  },
                ),
                child: TabBar(
                  key: const ValueKey('cadastros-tabs'),
                  controller: _controller,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: AppColors.green,
                  unselectedLabelColor: const Color(0xff687178),
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 18),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: const BoxDecoration(
                    color: Color(0xfff7faf8),
                    border: Border(
                      bottom: BorderSide(width: 3, color: AppColors.green),
                    ),
                  ),
                  tabs: [
                    for (final label in _tabs)
                      Tab(height: widget.compact ? 38 : 43, text: label),
                  ],
                ),
              ),
            ),
            SizedBox(height: widget.compact ? 12 : 20),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) =>
                  _controller.index < CadastroKind.values.length
                  ? CadastroPanel(
                      key: ValueKey(CadastroKind.values[_controller.index]),
                      kind: CadastroKind.values[_controller.index],
                      memory: widget.memory,
                      permissions: widget.permissions,
                    )
                  : VisualCard(
                      key: const ValueKey('cadastro-placeholder'),
                      radius: 9,
                      padding: EdgeInsets.all(widget.compact ? 14 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cadastro de ${_tabs[_controller.index]}',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: AppColors.heading,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Os campos deste cadastro serão definidos em uma próxima etapa.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
