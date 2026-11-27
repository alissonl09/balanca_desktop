import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/visual_components.dart';
import 'cadastro_panel.dart';
import 'cadastro_record.dart';
import 'cadastros_memory.dart';

class CadastrosPage extends StatefulWidget {
  const CadastrosPage({
    super.key,
    required this.compact,
    required this.memory,
    this.onSimulationChanged,
  });
  final bool compact;
  final CadastrosMemory memory;
  final ValueChanged<bool>? onSimulationChanged;

  @override
  State<CadastrosPage> createState() => _CadastrosPageState();
}

class _CadastrosPageState extends State<CadastrosPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = [...CadastroKind.values];
  static const _unitLabel = 'Unidades';
  late final _controller = TabController(length: _tabs.length + 1, vsync: this);

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
            Row(
              children: [
                const Expanded(
                  child: PageHeading(
                    title: 'Cadastros',
                    subtitle: 'Selecione o cadastro que deseja acessar.',
                    icon: Icons.badge_outlined,
                  ),
                ),
                if (widget.onSimulationChanged != null) ...[
                  const SizedBox(width: 8),
                  const Flexible(child: Text('Modo simulado')),
                  Semantics(
                    label: 'Modo simulado',
                    child: Switch(
                      key: const ValueKey('cadastro-simulation'),
                      value: widget.memory.simulated,
                      onChanged: widget.onSimulationChanged,
                    ),
                  ),
                ],
              ],
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
                    for (final kind in _tabs)
                      Tab(height: widget.compact ? 38 : 43, text: kind.label),
                    Tab(height: widget.compact ? 38 : 43, text: _unitLabel),
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
                      key: ValueKey((widget.memory, _controller.index)),
                      kind: CadastroKind.values[_controller.index],
                      memory: widget.memory,
                    )
                  : VisualCard(
                      key: const ValueKey('cadastro-placeholder'),
                      radius: 9,
                      padding: EdgeInsets.all(widget.compact ? 14 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cadastro de $_unitLabel',
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
