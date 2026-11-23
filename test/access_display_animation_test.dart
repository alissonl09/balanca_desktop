import 'package:balanca_desktop/features/access_control/access_control_panel.dart';
import 'package:balanca_desktop/features/access_control/access_control_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in {
    GateState.closed: 'FECHADA',
    GateState.open: 'ABERTA',
    GateState.moving: 'EM MOVIMENTO',
    GateState.error: 'ERRO',
  }.entries) {
    testWidgets('cancelas exibem somente o estado ${entry.value}', (
      tester,
    ) async {
      final state = AccessControlState()
        ..bindEquipments('entrada-01', 'saida-01');
      addTearDown(state.dispose);
      for (final side in GateSide.values) {
        state.simulateGate(side, entry.key);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: AccessControlPanel(
                state: state,
                gates: true,
                trafficLights: true,
                display: false,
                entryEquipmentId: 'entrada-01',
                exitEquipmentId: 'saida-01',
                equipmentSource: const MockGateEquipmentSource(),
                displayMessage: '',
              ),
            ),
          ),
        ),
      );
      expect(find.text(entry.value), findsNWidgets(2));
      expect(find.textContaining('Entrada ·'), findsNothing);
      expect(find.textContaining('Saída ·'), findsNothing);
      expect(find.text('Cancela Entrada 01'), findsOneWidget);
      expect(find.text('Cancela Saída 01'), findsOneWidget);
    });
  }

  test('normalização preserva somente caracteres do painel digital', () {
    expect(sanitizeDisplayText('COOXUPÉ'), 'COOXUPE');
    expect(sanitizeDisplayText('BALANÇA'), 'BALANCA');
    expect(sanitizeDisplayText('INFORMAÇÃO'), 'INFORMACAO');
    expect(
      sanitizeDisplayText('BEM-VINDO À COOXUPÉ 😀'),
      'BEM-VINDO A COOXUPE',
    );
  });

  testWidgets('mensagem longa atravessa o display da direita para a esquerda', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 120);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const message = 'BEM-VINDO À BALANÇA 01 DA COOXUPÉ';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: InformationDisplay(message: message),
          ),
        ),
      ),
    );
    final display = find.byKey(const ValueKey('information-display'));
    final text = find.byKey(const ValueKey('display-message-text'));
    expect(find.text('BEM-VINDO A BALANCA 01 DA COOXUPE'), findsOneWidget);
    final style = tester.widget<Text>(text).style!;
    expect(style.fontFamily, 'DS-Digital');
    expect(style.color, const Color(0xffff3026));
    expect(style.fontWeight, FontWeight.w700);
    expect(
      find.ancestor(of: text, matching: find.byType(ClipRect)),
      findsOneWidget,
    );
    final start = tester.getTopLeft(text).dx;
    await tester.pump(const Duration(seconds: 2));
    final middle = tester.getTopLeft(text).dx;
    await tester.pump(const Duration(seconds: 2));
    final later = tester.getTopLeft(text).dx;
    expect(start, greaterThan(middle));
    expect(middle, greaterThan(later));
    expect(tester.getSize(display).width, 280);
    expect(tester.takeException(), isNull);
  });
}
