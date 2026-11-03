import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/visual_components.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    this.description,
    required this.child,
  });
  final String title;
  final String? description;
  final Widget child;
  @override
  Widget build(BuildContext context) => VisualCard(
    radius: 9,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.heading,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description!,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ],
        const SizedBox(height: 12),
        Material(type: MaterialType.transparency, child: child),
      ],
    ),
  );
}

class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabledLabel = 'Ativo',
    this.disabledLabel = 'Inativo',
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String enabledLabel, disabledLabel;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        value ? enabledLabel : disabledLabel,
        style: const TextStyle(fontSize: 13),
      ),
      value: value,
      activeThumbColor: AppColors.green,
      onChanged: onChanged,
    ),
  );
}

class SettingsFields extends StatelessWidget {
  const SettingsFields({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 680
          ? (constraints.maxWidth - 16) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// Limita quebras explícitas de linha, inclusive em colagem; não é layout de impressão.
class ThreeLinesFormatter extends TextInputFormatter {
  const ThreeLinesFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .take(3)
        .join('\n');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: newValue.selection.extentOffset.clamp(0, text.length),
      ),
    );
  }
}

class TicketTextField extends StatefulWidget {
  const TicketTextField({
    super.key,
    required this.label,
    required this.fieldKey,
    required this.initialValue,
    required this.onChanged,
  });
  final String label, initialValue, fieldKey;
  final ValueChanged<String> onChanged;
  @override
  State<TicketTextField> createState() => _TicketTextFieldState();
}

class _TicketTextFieldState extends State<TicketTextField> {
  late final _controller = TextEditingController(text: widget.initialValue);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _controller,
    builder: (context, value, _) => TextFormField(
      key: ValueKey(widget.fieldKey),
      controller: _controller,
      minLines: 3,
      maxLines: 3,
      inputFormatters: const [ThreeLinesFormatter()],
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        counterText:
            '${value.text.isEmpty ? 0 : value.text.split('\n').length}/3 linhas',
      ),
    ),
  );
}
