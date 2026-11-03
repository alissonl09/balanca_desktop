import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/visual_components.dart';
import 'pesagem_actions.dart';
import 'pesagem_layout.dart';

class PesagemActionBar extends StatelessWidget {
  const PesagemActionBar({
    super.key,
    required this.layout,
    required this.actions,
  });

  final PesagemLayout layout;
  final Map<PesagemAction, VoidCallback?> actions;

  @override
  Widget build(BuildContext context) => VisualCard(
    key: const ValueKey('pesagem-action-bar'),
    padding: EdgeInsets.all(layout.compact ? 6 : 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final gap = layout.compact ? 5.0 : 8.0;
        final columns = constraints.maxWidth >= 810 ? 5 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < PesagemAction.values.length; i++)
              SizedBox(
                width: width,
                child: FocusTraversalOrder(
                  order: NumericFocusOrder(20 + i.toDouble()),
                  child: _button(PesagemAction.values[i]),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _button(PesagemAction action) {
    final primary = action == PesagemAction.pesar;
    final manual = action == PesagemAction.manual;
    final enabled = actions[action] != null;
    final foreground = !enabled
        ? AppColors.muted
        : primary
        ? Colors.white
        : manual
        ? const Color(0xffd32929)
        : AppColors.green;
    return TextButton(
      key: ValueKey('pesagem-action-${action.name}'),
      onPressed: actions[action],
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: primary ? AppColors.green : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: Size(0, layout.compact ? 42 : layout.actionHeight),
        side: BorderSide(color: primary ? AppColors.green : AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 29,
            child: Center(
              child: action == PesagemAction.nova
                  ? const Text(
                      '+',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Transform.scale(
                      scale: _usesIllustratedIcon(action) ? 1.1 : 1,
                      child: AppAsset(
                        action.asset,
                        size: _usesIllustratedIcon(action) ? 30 : 26,
                        color: primary
                            ? Colors.white
                            : manual
                            ? const Color(0xffd32929)
                            : null,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              action.label,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 12,
                height: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: primary
                  ? Colors.white.withValues(alpha: .14)
                  : const Color(0xfff8f9fa),
              border: Border.all(
                color: primary
                    ? Colors.white.withValues(alpha: .25)
                    : AppColors.border,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              action.shortcut,
              style: TextStyle(
                fontSize: 11,
                color: primary ? Colors.white : AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _usesIllustratedIcon(PesagemAction action) =>
      action == PesagemAction.imprimir || action == PesagemAction.salvar;
}
