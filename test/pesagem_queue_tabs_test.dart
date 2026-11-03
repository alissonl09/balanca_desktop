import 'package:balanca_desktop/core/theme/app_theme.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_layout.dart';
import 'package:balanca_desktop/features/pesagem/pesagem_side_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const operations = <({String plate, String? trailer, String time})>[
  (plate: 'ABC1D23', trailer: null, time: '09:12'),
  (plate: 'DEF2E34', trailer: '   ', time: '09:18'),
  (plate: 'GHI3F45', trailer: 'JKL6M78', time: '09:25'),
];
const yard = <({String plate, String? trailer, String time})>[
  (plate: 'RST7K89', trailer: null, time: '08:35'),
  (plate: 'UVW8L90', trailer: 'XYZ9M01', time: '08:42'),
];

void main() {
  Future<void> mountQueue(WidgetTester tester, {required bool sgv}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 650,
              child: PesagemSidePanel(
                layout: PesagemLayout.fromSize(const Size(1200, 650)),
                integratedSgv: sgv,
                vehicles: operations,
                yardVehicles: yard,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String badge(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('queue-count')),
          matching: find.byType(Text),
        ),
      )
      .data!;

  Finder row(String plate, int index) =>
      find.byKey(ValueKey('queue-row-$plate-$index'));

  testWidgets('SGV desligado mostra lista simples e carreta opcional', (
    tester,
  ) async {
    await mountQueue(tester, sgv: false);
    expect(find.text('Veículos em Operação'), findsOneWidget);
    expect(find.text('Veículos no Pátio'), findsNothing);
    expect(badge(tester), '3');
    expect(
      find.descendant(of: row('ABC1D23', 0), matching: find.text('-')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('DEF2E34', 1), matching: find.text('-')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('GHI3F45', 2), matching: find.text('JKL6M78')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('operation-search')),
      'ghi3f45',
    );
    await tester.pumpAndSettle();
    expect(badge(tester), '1');
    expect(find.text('JKL6M78'), findsOneWidget);
    expect(find.text('09:12'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SGV ligado alterna pátio e operação com busca e contagem', (
    tester,
  ) async {
    await mountQueue(tester, sgv: true);
    final yardTab = find.byKey(const ValueKey('queue-tab-yard'));
    final operationTab = find.byKey(const ValueKey('queue-tab-operation'));
    expect(yardTab, findsOneWidget);
    expect(operationTab, findsOneWidget);
    expect(
      tester.getTopLeft(yardTab).dx,
      lessThan(tester.getTopLeft(operationTab).dx),
    );
    expect(badge(tester), '2');
    expect(find.text('08:35'), findsOneWidget);
    expect(find.text('09:12'), findsNothing);

    final search = find.byKey(const ValueKey('operation-search'));
    await tester.enterText(search, 'uvw8l90');
    await tester.pumpAndSettle();
    expect(badge(tester), '1');
    expect(find.text('XYZ9M01'), findsOneWidget);
    await tester.tap(operationTab);
    await tester.pumpAndSettle();
    expect(badge(tester), '3');
    expect(find.text('09:12'), findsOneWidget);
    expect(find.text('08:42'), findsNothing);
    await tester.enterText(search, 'DEF2E34');
    await tester.pumpAndSettle();
    expect(badge(tester), '1');
    expect(find.text('09:18'), findsOneWidget);
    expect(find.text('09:12'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
