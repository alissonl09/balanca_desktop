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
    this.invoiceWeight,
  });
  final WeighingSummary summary;
  final IndicatorReading reading;
  final double? invoiceWeight;
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
    height: layout.tightHeight ? 20 : layout.panelHeadingHeight,
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
  EdgeInsets get _padding => EdgeInsets.symmetric(
    horizontal: layout.panelPadding,
    vertical: layout.tightHeight ? 3 : layout.panelPadding,
  );
  double get _headingGap => layout.tightHeight ? 2 : (compact ? 5 : 8);

  double? get _invoiceWeightDifference {
    final net = summary.netWeight;
    final invoice = invoiceWeight;
    if (net == null || invoice == null) return null;
    final difference = net - invoice;
    if (!difference.isFinite) return null;
    return double.parse(difference.toStringAsFixed(3));
  }

  Widget _summaryHeading() {
    final difference = _invoiceWeightDifference;
    final heading = _heading('Resumo da Pesagem');
    if (difference == null) return heading;
    final sign = difference > 0
        ? '+'
        : difference < 0
        ? '-'
        : '';
    final color = difference > 0
        ? const Color(0xff0755a5)
        : difference < 0
        ? const Color(0xffb42318)
        : AppColors.text;
    return Row(
      children: [
        Expanded(flex: 5, child: heading),
        const SizedBox(width: 8),
        Flexible(
          flex: 4,
          child: Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: 'Peso Líquido menos Peso N.F.',
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  key: const ValueKey('invoice-weight-difference'),
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                    children: [
                      const TextSpan(text: 'Dif. N.F.  '),
                      TextSpan(
                        text: '$sign${formatWeight(difference.abs())} Kg',
                        style: TextStyle(color: color),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String get _displayWeight {
    final weight = reading.weight;
    if (!reading.physical) return formatWeight(weight ?? 0);
    return weight == null
        ? '—'
        : formatIndicatorWeight(weight, reading.decimalPlaces!);
  }

  String get _displayStatus {
    if (!reading.connected) return reading.status.label;
    if (reading.error != null) return 'Leitura inválida';
    final stability = switch (reading.stable) {
      null => 'Estabilidade desconhecida',
      true => 'Peso estável',
      false => 'Peso instável',
    };
    return reading.gross == false ? '$stability · líquido' : stability;
  }

  Color get _statusColor =>
      reading.connected && reading.error == null && reading.stable == true
      ? const Color(0xff42ca75)
      : const Color(0xffe14b4b);

  Widget _indicator() => VisualCard(
    padding: _padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('⚖  Indicador de Peso'),
        SizedBox(height: _headingGap),
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
                right: layout.shortHeight ? 45 : 70,
                left: layout.shortHeight ? 10 : 18,
                top: layout.shortHeight ? 2 : 12,
                bottom: layout.shortHeight ? 8 : 9,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _displayWeight,
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
              ),
              Positioned(
                right: layout.shortHeight ? 8 : 18,
                bottom: 25,
                child: Text(
                  reading.physical && reading.weight == null
                      ? ''
                      : reading.unit,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: layout.shortHeight ? 4 : 8,
                child: Row(
                  children: [
                    Container(
                      key: const ValueKey('weight-stability-dot'),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _statusColor,
                        boxShadow: [
                          BoxShadow(
                            color: _statusColor.withValues(alpha: .75),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Tooltip(
                        message: reading.error ?? _displayStatus,
                        child: Text(
                          _displayStatus,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
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
      ],
    ),
  );

  Widget _summary() => VisualCard(
    padding: _padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summaryHeading(),
        SizedBox(height: _headingGap),
        LayoutBuilder(
          builder: (context, constraints) {
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
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (label, value, background, border) in cards)
                  Container(
                    key: ValueKey('summary-card-$label'),
                    width:
                        (constraints.maxWidth - (cards.length - 1) * gap) /
                        cards.length,
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
