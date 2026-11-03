import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/digital_text_style.dart';
import 'access_control_state.dart';

String sanitizeDisplayText(String input) {
  const replacements = {
    'À': 'A',
    'Á': 'A',
    'Â': 'A',
    'Ã': 'A',
    'Ä': 'A',
    'Å': 'A',
    'à': 'A',
    'á': 'A',
    'â': 'A',
    'ã': 'A',
    'ä': 'A',
    'å': 'A',
    'Ç': 'C',
    'ç': 'C',
    'È': 'E',
    'É': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'è': 'E',
    'é': 'E',
    'ê': 'E',
    'ë': 'E',
    'Ì': 'I',
    'Í': 'I',
    'Î': 'I',
    'Ï': 'I',
    'ì': 'I',
    'í': 'I',
    'î': 'I',
    'ï': 'I',
    'Ñ': 'N',
    'ñ': 'N',
    'Ò': 'O',
    'Ó': 'O',
    'Ô': 'O',
    'Õ': 'O',
    'Ö': 'O',
    'ò': 'O',
    'ó': 'O',
    'ô': 'O',
    'õ': 'O',
    'ö': 'O',
    'Ù': 'U',
    'Ú': 'U',
    'Û': 'U',
    'Ü': 'U',
    'ù': 'U',
    'ú': 'U',
    'û': 'U',
    'ü': 'U',
    'Ý': 'Y',
    'ý': 'Y',
    'ÿ': 'Y',
    'Æ': 'AE',
    'æ': 'AE',
    'Œ': 'OE',
    'œ': 'OE',
    'ß': 'SS',
  };
  final prepared = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final replacement = replacements[char];
    if (replacement != null) {
      prepared.write(replacement);
    } else if ((rune >= 65 && rune <= 90) ||
        (rune >= 97 && rune <= 122) ||
        (rune >= 48 && rune <= 57) ||
        char == ' ' ||
        char == '-') {
      prepared.write(char.toUpperCase());
    } else if (char == '\t' || char == '\n' || char == '\r') {
      prepared.write(' ');
    }
  }
  return prepared.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

class AccessControlPanel extends StatelessWidget {
  const AccessControlPanel({
    super.key,
    required this.state,
    required this.gates,
    required this.trafficLights,
    required this.display,
    required this.entryEquipmentId,
    required this.exitEquipmentId,
    required this.equipmentSource,
    required this.displayMessage,
    this.simulationEnabled = false,
  });
  final AccessControlState state;
  final bool gates, trafficLights, display, simulationEnabled;
  final String displayMessage;
  final String? entryEquipmentId, exitEquipmentId;
  final GateEquipmentSource equipmentSource;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => Column(
      key: const ValueKey('access-control'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Controle de acesso',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (simulationEnabled)
              IconButton(
                key: const ValueKey('access-simulation'),
                tooltip: 'Simulação local',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () => _simulation(context),
                icon: const Icon(Icons.science_outlined),
              ),
          ],
        ),
        if (gates || trafficLights)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final side in GateSide.values) Expanded(child: _lane(side)),
            ],
          ),
        if (display) InformationDisplay(message: displayMessage),
        if (!gates && !trafficLights && !display)
          const Text(
            'Nenhum componente visual habilitado.',
            style: TextStyle(fontSize: 12),
          ),
      ],
    ),
  );

  Widget _lane(GateSide side) => Column(
    key: ValueKey('lane-${side.name}'),
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (trafficLights && side == GateSide.entry)
            TrafficLightVisual(state: state.light(side), side: side),
          if (gates && trafficLights && side == GateSide.entry)
            const SizedBox(width: 4),
          if (gates) GateVisual(state: state.gate(side), side: side),
          if (gates && trafficLights && side == GateSide.exit)
            const SizedBox(width: 4),
          if (trafficLights && side == GateSide.exit)
            TrafficLightVisual(state: state.light(side), side: side),
        ],
      ),
      Text(
        '${side == GateSide.entry ? 'Entrada' : 'Saída'}${gates ? ' · ${_label(state.gate(side))}' : ''}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      if (gates)
        Text(
          _equipmentName(side),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: AppColors.muted),
        ),
      const SizedBox(height: 5),
    ],
  );

  String _equipmentName(GateSide side) {
    final id = side == GateSide.entry ? entryEquipmentId : exitEquipmentId;
    if (id == null) return 'Não configurada';
    for (final equipment in equipmentSource.available) {
      if (equipment.id == id) return equipment.name;
    }
    return 'Equipamento indisponível';
  }

  String _label(GateState value) => switch (value) {
    GateState.open => 'ABERTA',
    GateState.closed => 'FECHADA',
    GateState.moving => 'EM MOVIMENTO',
    GateState.error => 'ERRO',
  };

  Future<void> _simulation(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Simulação local de acesso'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Estados apenas visuais. Nenhum comando é enviado a equipamento.',
            ),
            const SizedBox(height: 12),
            if (gates || trafficLights)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final side in GateSide.values)
                    for (final target in [GateState.open, GateState.closed])
                      OutlinedButton(
                        key: ValueKey('simulate-${side.name}-${target.name}'),
                        onPressed: () => state.simulateGate(side, target),
                        child: Text(
                          'Simular ${side == GateSide.entry ? 'Entrada' : 'Saída'} ${target == GateState.open ? 'Abrir' : 'Fechar'}',
                        ),
                      ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

class InformationDisplay extends StatefulWidget {
  const InformationDisplay({super.key, required this.message});
  final String message;

  @override
  State<InformationDisplay> createState() => _InformationDisplayState();
}

class _InformationDisplayState extends State<InformationDisplay>
    with SingleTickerProviderStateMixin {
  static final _style = digitalTextStyle.copyWith(
    color: const Color(0xffff3026),
    fontSize: 30,
    fontWeight: FontWeight.w700,
    shadows: const [
      Shadow(color: Color(0xffff3026), offset: Offset(-0.75, 0)),
      Shadow(color: Color(0xffff3026), offset: Offset(0.75, 0)),
    ],
  );
  late final AnimationController _travel;

  Duration _duration(String message) =>
      Duration(milliseconds: 8000 + message.runes.length * 280);
  String get _message => sanitizeDisplayText(widget.message);

  @override
  void initState() {
    super.initState();
    _travel = AnimationController(vsync: this, duration: _duration(_message))
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant InformationDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      _travel.duration = _duration(_message);
      _travel.repeat();
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('information-display'),
    margin: const EdgeInsets.only(top: 5),
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: const Color(0xff15191c),
      borderRadius: BorderRadius.circular(5),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: _message, style: _style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final travelDistance = constraints.maxWidth + painter.width;
        return SizedBox(
          width: double.infinity,
          height: 34,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _travel,
              builder: (context, _) => Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: constraints.maxWidth - travelDistance * _travel.value,
                    top: 2,
                    child: Text(
                      _message,
                      key: const ValueKey('display-message-text'),
                      maxLines: 1,
                      softWrap: false,
                      style: _style,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class TrafficLightVisual extends StatelessWidget {
  const TrafficLightVisual({
    super.key,
    required this.state,
    required this.side,
  });
  final TrafficLightState state;
  final GateSide side;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Semáforo ${side.name}: ${state == TrafficLightState.red ? 'vermelho' : 'verde'}',
    child: Container(
      key: ValueKey('traffic-light-${side.name}'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xff263238),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final red in [true, false])
            Container(
              width: 11,
              height: 11,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: red
                    ? (state == TrafficLightState.red
                          ? const Color(0xffff3026)
                          : const Color(0xff542320))
                    : (state == TrafficLightState.green
                          ? const Color(0xff42f575)
                          : const Color(0xff16452b)),
              ),
            ),
        ],
      ),
    ),
  );
}

class GateVisual extends StatelessWidget {
  const GateVisual({super.key, required this.state, required this.side});
  final GateState state;
  final GateSide side;
  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('gate-${side.name}'),
    height: 70,
    width: 100,
    // Toda a trajetória da haste fica dentro da caixa reservada.
    child: Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(side == GateSide.exit ? -1 : 1, 1, 1),
      child: ClipRect(
        child: TweenAnimationBuilder<double>(
          tween: Tween(
            begin: 0,
            end: state == GateState.open
                ? 1
                : state == GateState.moving
                ? .5
                : 0,
          ),
          duration: const Duration(milliseconds: 450),
          builder: (context, value, _) =>
              CustomPaint(painter: _GatePainter(value, state)),
        ),
      ),
    ),
  );
}

class _GatePainter extends CustomPainter {
  _GatePainter(this.open, this.state);
  final double open;
  final GateState state;
  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width * .22, 57);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pivot.dx - 9, 48, 18, 19),
        const Radius.circular(3),
      ),
      Paint()..color = state == GateState.error ? Colors.red : AppColors.green,
    );
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(-open * math.pi / 2);
    canvas.drawLine(
      Offset.zero,
      const Offset(50, 0),
      Paint()
        ..color = Colors.red
        ..strokeWidth = 5,
    );
    for (var x = 4.0; x < 50; x += 12) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + 5, 0),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 5,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GatePainter oldDelegate) =>
      oldDelegate.open != open || oldDelegate.state != state;
}
