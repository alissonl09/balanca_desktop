import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Leitura com indicação de truncamento somente quando o valor não cabe.
class ReadOnlyValueField extends StatelessWidget {
  const ReadOnlyValueField({
    super.key,
    required this.label,
    required this.value,
    required this.height,
    required this.labelGap,
  });

  final String label, value;
  final double height, labelGap;

  void _showFullValue(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(label),
      content: SizedBox(width: 520, child: SelectableText(value)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          height: 1,
          color: Color(0xff495057),
          fontWeight: FontWeight.w600,
        ),
      ),
      SizedBox(height: labelGap),
      SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final style = DefaultTextStyle.of(context).style
                .merge(const TextStyle(fontSize: 14, color: AppColors.text));
            final painter =
                TextPainter(
                  text: TextSpan(text: value, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout(
                  maxWidth: (constraints.maxWidth - 24).clamp(
                    0,
                    double.infinity,
                  ),
                );
            final overflows =
                painter.didExceedMaxLines ||
                painter.width > constraints.maxWidth - 24;
            painter.dispose();
            return Semantics(
              label: label,
              value: value,
              button: overflows,
              child: InkWell(
                onTap: overflows ? () => _showFullValue(context) : null,
                // A única parada de TAB é o botão de expansão, quando visível.
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(7),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    fillColor: Color(0xfff8f9fa),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (overflows)
                        SizedBox(
                          width: 30,
                          height: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Ver conteúdo completo: $label',
                            iconSize: 20,
                            onPressed: () => _showFullValue(context),
                            icon: const Icon(
                              Icons.more_horiz,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}
