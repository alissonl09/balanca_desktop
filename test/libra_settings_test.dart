import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/libra/libra_configuration.dart';
import 'package:balanca_desktop/core/libra/libra_api_client.dart';
import 'package:balanca_desktop/core/libra/libra_settings_store.dart';
import 'package:balanca_desktop/core/offline/offline_models.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';
import 'package:balanca_desktop/features/configuracoes/libra_settings.dart';
import 'package:balanca_desktop/features/configuracoes/configuracoes_page.dart';
import 'package:balanca_desktop/features/ticket/ticket_session.dart';
import 'package:balanca_desktop/features/pesagem/pre_ticket_service.dart';

import 'support/libra_http_fake.dart';

const syntheticValue = 'synthetic-local-placeholder';
Finder field(String key) => find.byKey(ValueKey('libra-$key'));

Future<void> mount(
  WidgetTester tester,
  SettingsState settings, {
  LibraConfiguration? configuration,
  LibraApiClient? client,
}) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: settings,
            builder: (_, _) => LibraSettings(
              settings: settings,
              configuration: configuration,
              client: client,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Salvar configurações persiste os campos editados na seção Libra',
    (tester) async {
      final store = MemoryLibraSettingsStore();
      final settings = SettingsState(libraStore: store)
        ..environment = StationEnvironment.desenvolvimento;
      addTearDown(settings.dispose);
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConfiguracoesPage(
                compact: true,
                settings: settings,
                ticketSession: TicketSession(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('auth-value'));
      await tester.enterText(field('auth-value'), syntheticValue);
      await tester.pumpAndSettle();
      expect(tester.getSize(field('auth-value')).width, lessThanOrEqualTo(372));
      final save = find.byKey(const ValueKey('save-settings'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final restored = await store.load();
      expect(restored.selectedEnvironment, 'desenvolvimento');
      expect(
        restored.forEnvironment('desenvolvimento').authValue == syntheticValue,
        isTrue,
      );
      expect(
        find.text('Configuração da Libra salva nesta estação.'),
        findsOneWidget,
      );
    },
  );

  test('padrões locais: Key x-api-key, Value vazio e ambientes isolados', () {
    final data = LibraSettingsData();
    final dsv = data.forEnvironment('desenvolvimento');
    expect(dsv.authKey, 'x-api-key');
    expect(dsv.authValue.isEmpty, isTrue);
    expect(dsv.authOverride, isFalse);
    dsv
      ..authValue = syntheticValue
      ..authOverride = true;
    expect(data.forEnvironment('producao').authValue.isEmpty, isTrue);
    expect(data.forEnvironment('homologacao').authValue.isEmpty, isTrue);
  });

  test('prioridade local, fallback e limpeza explícita sem header', () {
    final config = LibraConfiguration(
      environment: {'LIBRA_API_KEY_DSV': 'synthetic-environment-placeholder'},
    );
    final data = LibraSettingsData();
    final entry = data.forEnvironment('desenvolvimento');
    expect(
      config
          .authentication(StationEnvironment.desenvolvimento, local: data)
          .configured,
      isTrue,
    );
    entry
      ..authKey = 'custom-auth'
      ..authValue = syntheticValue
      ..authOverride = true;
    final auth = config.authentication(
      StationEnvironment.desenvolvimento,
      local: data,
    );
    expect(auth.key, 'custom-auth');
    expect(auth.value == syntheticValue, isTrue);
    entry.authValue = '';
    expect(
      config
          .authentication(StationEnvironment.desenvolvimento, local: data)
          .configured,
      isFalse,
    );
    entry.baseUrl = 'https://local.example.invalid';
    expect(
      config.baseUrl(StationEnvironment.desenvolvimento, local: data)!.host,
      'local.example.invalid',
    );
    expect(config.baseUrl(StationEnvironment.homologacao, local: data), isNull);
  });

  test('persistência local restaura ambiente, URL, Key e Value; sobrescrita funciona', () async {
    final directory = await Directory.systemTemp.createTemp(
      'libra_settings_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalLibraSettingsStore(directory: () async => directory);
    expect((await store.load()).environments, isEmpty);
    final data = LibraSettingsData()..selectedEnvironment = 'desenvolvimento';
    data.forEnvironment('desenvolvimento')
      ..baseUrl = 'https://example.invalid'
      ..authKey = 'custom-auth'
      ..authValue = syntheticValue
      ..authOverride = true;
    data.forEnvironment('homologacao').authKey = 'hml-auth';
    await store.save(data);
    await store.save(data);
    final restored = await store.load();
    expect(restored.selectedEnvironment, 'desenvolvimento');
    expect(
      restored.forEnvironment('desenvolvimento').authValue == syntheticValue,
      isTrue,
    );
    expect(restored.forEnvironment('desenvolvimento').authKey, 'custom-auth');
    expect(
      restored.forEnvironment('desenvolvimento').baseUrl,
      'https://example.invalid',
    );
    expect(restored.forEnvironment('homologacao').authKey, 'hml-auth');
    final state = SettingsState(libraSettings: restored);
    addTearDown(state.dispose);
    expect(state.environment, StationEnvironment.desenvolvimento);
  });

  for (final key in ['', 'x-api-key']) {
    test('sem par completo não envia autenticação: key=$key', () async {
      final http = TestClient();
      await LibraApiClient(clientFactory: () => http).getPreTickets(
        baseUrl: Uri.parse('https://example.invalid'),
        apiKey: key.isEmpty ? syntheticValue : '',
        authKey: key,
        unitCode: 4,
        plate: 'ABC1D23',
      );
      expect(http.request.headers.values.keys, [HttpHeaders.acceptHeader]);
    });
  }

  testWidgets(
    'campos mascarados, ambiente separado e serviço usa configuração editada',
    (tester) async {
      final settings = SettingsState()
        ..environment = StationEnvironment.desenvolvimento;
      addTearDown(settings.dispose);
      final config = LibraConfiguration(environment: {});
      await mount(tester, settings, configuration: config);
      expect(
        tester.widget<TextFormField>(field('auth-key')).initialValue,
        'x-api-key',
      );
      expect(
        tester.widget<TextFormField>(field('auth-value')).initialValue,
        '',
      );
      expect(
        tester.widget<TextFormField>(field('base-url')).initialValue,
        LibraConfiguration.developmentBaseUrl,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: field('auth-value'),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isTrue,
      );
      await tester.enterText(field('auth-key'), 'custom-auth');
      await tester.enterText(field('auth-value'), syntheticValue);
      await tester.enterText(
        field('base-url'),
        'https://edited.example.invalid',
      );
      await tester.tap(find.byTooltip('Mostrar valor'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: field('auth-value'),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isFalse,
      );
      final logs = <String>[];
      final http = TestClient(body: payload);
      await PreTicketService(
        settings: settings,
        configuration: config,
        client: LibraApiClient(clientFactory: () => http, log: logs.add),
      ).lookup('ABC1D23', StationConnection.online);
      expect(http.uri!.host, 'edited.example.invalid');
      expect(
        http.request.headers.values['custom-auth'] == syntheticValue,
        isTrue,
      );
      expect(logs.join().contains(syntheticValue), isFalse);
      settings.update(
        () => settings.environment = StationEnvironment.homologacao,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('auth-value')).initialValue,
        '',
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: field('auth-value'),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isTrue,
      );
      settings.update(
        () => settings.environment = StationEnvironment.desenvolvimento,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('auth-value')).initialValue ==
            syntheticValue,
        isTrue,
      );
    },
  );

  for (final status in [200, 401, 404, 500]) {
    testWidgets(
      'Testar conexão usa serviço/configuração atuais: HTTP $status',
      (tester) async {
        final settings = SettingsState()
          ..environment = StationEnvironment.desenvolvimento;
        addTearDown(settings.dispose);
        settings.libra.forEnvironment('desenvolvimento')
          ..authKey = 'test-auth'
          ..authValue = syntheticValue
          ..authOverride = true;
        final http = TestClient(status: status);
        await mount(
          tester,
          settings,
          configuration: LibraConfiguration(environment: {}),
          client: LibraApiClient(clientFactory: () => http),
        );
        await tester.enterText(field('test-plate'), 'ABC1D23');
        await tester.tap(field('test-connection'));
        await tester.pumpAndSettle();
        expect(http.uri!.queryParameters, {
          'placa': 'ABC1D23',
          'cdUnidadeBalanca': '4',
        });
        expect(
          http.request.headers.values['test-auth'] == syntheticValue,
          isTrue,
        );
        expect(
          find.text(
            status == 200
                ? 'Conexão realizada.'
                : status == 401
                ? 'Falha de autenticação.'
                : 'Endpoint indisponível.',
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('credencial ausente ou mock não dispara teste HTTP', (
    tester,
  ) async {
    final settings = SettingsState()
      ..environment = StationEnvironment.desenvolvimento;
    addTearDown(settings.dispose);
    final http = TestClient();
    await mount(
      tester,
      settings,
      configuration: LibraConfiguration(environment: {}),
      client: LibraApiClient(clientFactory: () => http),
    );
    await tester.tap(field('test-connection'));
    await tester.pumpAndSettle();
    expect(find.text('Credencial não configurada.'), findsOneWidget);
    expect(http.uri, isNull);
    await tester.pumpWidget(const SizedBox());
    await mount(
      tester,
      settings,
      configuration: LibraConfiguration(environment: {'LIBRA_MODE': 'mock'}),
      client: LibraApiClient(clientFactory: () => http),
    );
    await tester.tap(field('test-connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Modo mock ativo'), findsOneWidget);
    expect(http.uri, isNull);
  });
}
