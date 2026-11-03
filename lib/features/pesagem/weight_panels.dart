import 'pesagem_layout.dart';
import 'weighing_preview.dart';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/digital_text_style.dart';
import '../../core/widgets/visual_components.dart';
import '../../core/indicators/indicator_driver.dart';

class WeightPanels extends StatelessWidget {
  const WeightPanels({
    super.key,
    required this.layout,
    this.summary = const WeighingSummary(),
    this.reading = const IndicatorReading(),
  });
  final WeighingSummary summary;
  final IndicatorReading reading;
  final PesagemLayout layout;
  bool get compact => !layout.spacious;
  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('weight-panels'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 4, child: _indicator()),
      SizedBox(width: layout.gap),
      Expanded(flex: 6, child: _summary()),
    ],
  );

  Widget _heading(String text) => SizedBox(
    height: layout.panelHeadingHeight,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          color: AppColors.heading,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
  EdgeInsets get _padding => EdgeInsets.all(layout.panelPadding);

  Widget _indicator() => VisualCard(
    padding: _padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('⚖  Indicador de Peso'),
        SizedBox(height: compact ? 5 : 8),
        Container(
          height: layout.displayHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff006548), Color(0xff004934)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                right: 70,
                left: 18,
                top: 12,
                bottom: 9,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatWeight(reading.weight ?? 0),
                    key: const ValueKey('peso-atual'),
                    style: digitalTextStyle.copyWith(
                      fontSize: layout.compact ? 64 : 80,
                      color: const Color(0xff92e52d),
                      shadows: const [
                        Shadow(color: Color(0x5292e52d), blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 18,
                bottom: 25,
                child: Text(
                  reading.unit,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Positioned(
                left: 16,
                bottom: 8,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: reading.connected
                            ? const Color(0xff42ca75)
                            : const Color(0xffe14b4b),
                        boxShadow: const [
                          BoxShadow(color: Color(0xbfe14b4b), blurRadius: 6),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      reading.connected
                          ? (reading.stable == null
                                ? 'Estabilidade desconhecida'
                                : reading.stable!
                                ? 'Peso estável'
                                : 'Peso instável')
                          : 'Indicador desconectado',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _summary() => VisualCard(
    padding: _padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('Resumo da Pesagem'),
        SizedBox(height: compact ? 5 : 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const columns = 4;
            final gap = compact ? 8.0 : 12.0;
            final cards = [
              (
                'Pesagem 1',
                summary.first,
                Color(0xfffffaf0),
                Color(0xfff0d68a),
              ),
              (
                'Pesagem 2',
                summary.second,
                Color(0xfffff8f2),
                Color(0xffeccbab),
              ),
              (
                'Peso Líquido',
                summary.net,
                Color(0xfff4faf2),
                Color(0xffb7d7ae),
              ),
              ('Peso Seco', summary.dry, Color(0xfffff5f5), Color(0xffefb9b9)),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (label, value, background, border) in cards)
                  Container(
                    key: ValueKey('summary-card-$label'),
                    width:
                        (constraints.maxWidth - (columns - 1) * gap) / columns,
                    height: layout.displayHeight,
                    padding: EdgeInsets.symmetric(
                      horizontal: layout.compact ? 4 : 8,
                      vertical: layout.compact ? 5 : 10,
                    ),
                    decoration: BoxDecoration(
                      color: background,
                      border: Border.all(color: border),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: layout.compact ? 20 : 24,
                          child: Center(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text.rich(
                                key: ValueKey('summary-value-$label'),
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: formatWeight(value),
                                      style: const TextStyle(
                                        fontSize: 30,
                                        color: Color(0xff111111),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const TextSpan(
                                      text: ' Kg',
                                      style: TextStyle(
                                        fontSize: 17,
                                        color: Color(0xff495057),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
