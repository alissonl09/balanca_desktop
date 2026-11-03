import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/app/app_shell.dart';
import 'package:balanca_desktop/core/offline/offline_models.dart';
import 'package:balanca_desktop/core/offline/offline_station.dart';
import 'package:balanca_desktop/core/offline/pre_ticket_source.dart';
import 'package:balanca_desktop/core/theme/app_theme.dart';

void main() {
  testWidgets(
    'cabeçalho global mostra Offline, Online e progresso em todas as abas',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1366, 768);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = OfflineStation(canOpenOffline: (_) => true);
      addTearDown(s.dispose);
      final ticket = KnownPreTicket(id: 'pre', plate: 'ABC1D23');
      final w = await s.create(ticket);
      await s.open(w.idLocal, 20000, ticket: ticket);
      await s.close(w.idLocal, 8000);
      await s.requestTicket(w.idLocal, {});
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AppShell(station: s),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offline · 3 pendências'), findsOneWidget);
      expect(
        find.textContaining('Ticket aguardando sincronização'),
        findsOneWidget,
      );
      await s.setConnection(StationConnection.online);
      await tester.pumpAndSettle();
      expect(find.text('Online · 3 pendências'), findsOneWidget);
      await s.setConnection(StationConnection.sincronizando);
      for (var i = 0; i < 2; i++) {
        final e = s.readyEvents.first;
        await s.beginEvent(e.idLocal);
        await s.confirmEvent(e.idLocal, remoteId: 'remote-$i');
      }
      await tester.pumpAndSettle();
      expect(find.text('Sincronizando · 2/3'), findsOneWidget);
      for (final menu in [
        'menu-cadastros',
        'menu-relatorios',
        'menu-config',
        'menu-balanca_icon',
      ]) {
        await tester.tap(find.byKey(ValueKey(menu)));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('station-connectivity')).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Sincronizando · 2/3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final e = s.readyEvents.single;
      await s.beginEvent(e.idLocal);
      await s.confirmEvent(e.idLocal, remoteId: 'ticket');
      await s.setConnection(StationConnection.online);
      await tester.pumpAndSettle();
      expect(find.text('Online'), findsOneWidget);
    },
  );

  testWidgets('fechamento local pendente aparece sem regredir ao navegar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = OfflineStation(canOpenOffline: (_) => true);
    addTearDown(s.dispose);
    final t = KnownPreTicket(id: 'pre', plate: 'ABC1D23');
    final w = await s.create(t);
    await s.open(w.idLocal, 100, ticket: t);
    await s.close(w.idLocal, 50);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AppShell(station: s),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Pesagem fechada localmente — aguardando sincronização',
      ),
      findsOneWidget,
    );
    expect(find.text('Offline · 2 pendências'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
