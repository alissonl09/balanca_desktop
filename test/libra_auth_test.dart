import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/libra/libra_api_client.dart';
import 'package:balanca_desktop/core/libra/libra_auth_session.dart';
import 'package:balanca_desktop/core/libra/libra_settings_store.dart';
import 'package:balanca_desktop/features/configuracoes/libra_auth_settings.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';

import 'support/libra_http_fake.dart';

final base = Uri.parse('https://libra.example.invalid');
final protected = base.resolve('/synthetic-protected');
const responseBody =
    '{"accessToken":"synthetic-token","username":"synthetic-user",'
    '"roles":["ROLE_SMART"],"expiresIn":100}';
const routes = {LibraBearerRoute('POST', '/synthetic-protected')};

void main() {
  test('valida credenciais e URL antes de abrir conexão', () async {
    var calls = 0;
    final client = LibraApiClient(
      clientFactory: () {
        calls++;
        return TestClient(body: responseBody);
      },
    );
    for (final url in [
      'http://libra.invalid',
      'https://user:pass@libra.invalid',
      'https://libra.invalid/path',
      'https://libra.invalid?query=1',
    ]) {
      await expectLater(
        client.authenticate(
          baseUrl: Uri.parse(url),
          username: 'user',
          password: 'password',
        ),
        throwsA(isA<LibraAuthException>()),
      );
    }
    for (final credentials in [('', 'password'), ('user', '')]) {
      await expectLater(
        client.authenticate(
          baseUrl: base,
          username: credentials.$1,
          password: credentials.$2,
        ),
        throwsA(isA<LibraAuthException>()),
      );
    }
    expect(calls, 0);
  });

  testWidgets(
    'troca de ambiente com mesma URL limpa os campos e modo offline bloqueia login',
    (tester) async {
      final settings = SettingsState();
      addTearDown(settings.dispose);
      Widget page() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LibraAuthSettings(
              settings: settings,
              baseUrl: base,
              connectionDisabled: true,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page());
      final user = find.byKey(const ValueKey('libra-jwt-username'));
      final password = find.byKey(const ValueKey('libra-jwt-password'));
      await tester.enterText(user, 'synthetic-user');
      await tester.enterText(password, 'synthetic-password');
      await tester.tap(find.byKey(const ValueKey('libra-jwt-login')));
      await tester.pumpAndSettle();
      expect(
        find.text('Autenticação real desabilitada no modo mock ou offline.'),
        findsOneWidget,
      );
      settings.update(() => settings.environment = StationEnvironment.producao);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(user).controller!.text, isEmpty);
      expect(tester.widget<TextFormField>(password).controller!.text, isEmpty);
    },
  );

  test(
    'login POST exato, sem Bearer, redirects ou logs; limpeza da sessão',
    () async {
      final logs = <String>[];
      final fake = TestClient(body: responseBody);
      final session = LibraAuthSession(
        client: LibraApiClient(clientFactory: () => fake, log: logs.add),
        verifiedRoutes: routes,
      );
      await session.signIn(base, ' synthetic-user ', ' synthetic-password ');
      expect(fake.method, 'POST');
      expect(fake.uri, base.resolve('/api/v1/auth'));
      expect(jsonDecode(utf8.decode(fake.request.bytes)), {
        'username': 'synthetic-user',
        'password': ' synthetic-password ',
      });
      expect(fake.request.headers.values.containsKey('Authorization'), isFalse);
      expect(fake.request.followRedirects, isFalse);
      expect(fake.closed, isTrue);
      expect(logs, isEmpty);
      expect(await session.headersFor('POST', protected), {
        'Authorization': 'Bearer synthetic-token',
      });
      session.clear();
      expect(session.authenticated, isFalse);
      expect(await session.headersFor('POST', protected), isEmpty);
    },
  );

  test('Bearer somente em origem, método e rota confirmados', () async {
    final session = LibraAuthSession(
      client: LibraApiClient(
        clientFactory: () => TestClient(body: responseBody),
      ),
      verifiedRoutes: routes,
    );
    await session.signIn(base, 'user', 'password');
    for (final target in [
      base.resolve('/api/v1/auth'),
      base.resolve('/api/v1/pre-tickets'),
      base.resolve('/other'),
      Uri.parse('https://other.invalid/synthetic-protected'),
      Uri.parse('http://libra.example.invalid/synthetic-protected'),
    ]) {
      expect(await session.headersFor('POST', target), isEmpty);
    }
    expect(await session.headersFor('GET', protected), isEmpty);
    final unverified = LibraAuthSession(
      client: LibraApiClient(
        clientFactory: () => TestClient(body: responseBody),
      ),
    );
    await unverified.signIn(base, 'user', 'password');
    expect(await unverified.headersFor('POST', protected), isEmpty);
  });

  test(
    'expiresIn, margem, renovação concorrente, 401 e 403 sem replay',
    () async {
      var now = DateTime.utc(2026);
      var calls = 0;
      final session = LibraAuthSession(
        now: () => now,
        verifiedRoutes: routes,
        client: LibraApiClient(
          clientFactory: () {
            calls++;
            return TestClient(
              body: responseBody.replaceFirst(
                'synthetic-token',
                'token-$calls',
              ),
            );
          },
        ),
      );
      await session.signIn(base, 'user', 'password');
      now = now.add(const Duration(seconds: 89));
      var headers = await session.headersFor('POST', protected);
      expect(calls, 1);
      session.handleResponse(403, headers['Authorization']);
      expect(session.authenticated, isTrue);
      now = now.add(const Duration(seconds: 1));
      await Future.wait(
        List.generate(5, (_) => session.headersFor('POST', protected)),
      );
      expect(calls, 2);
      session.handleResponse(401, headers['Authorization']); // resposta antiga
      expect(session.authenticated, isTrue);
      headers = await session.headersFor('POST', protected);
      session.handleResponse(401, headers['Authorization']);
      expect(session.authenticated, isFalse);
      expect(calls, 2); // não reenvia nem autentica em background
      await session.headersFor('POST', protected);
      expect(calls, 3);
    },
  );

  for (final entry in {
    400: LibraAuthFailure.invalidRequest,
    401: LibraAuthFailure.rejected,
    403: LibraAuthFailure.forbidden,
    429: LibraAuthFailure.rateLimited,
    502: LibraAuthFailure.gateway,
    503: LibraAuthFailure.unavailable,
  }.entries) {
    test('HTTP ${entry.key} sanitizado e sem tentativas automáticas', () async {
      var calls = 0;
      final session = LibraAuthSession(
        verifiedRoutes: routes,
        client: LibraApiClient(
          clientFactory: () {
            calls++;
            return TestClient(status: entry.key, body: 'private-details');
          },
        ),
      );
      await expectLater(
        session.signIn(base, 'user', 'password'),
        throwsA(
          isA<LibraAuthException>()
              .having((e) => e.failure, 'failure', entry.value)
              .having(
                (e) => e.toString().contains('private-details'),
                'sanitized',
                isFalse,
              ),
        ),
      );
      expect(session.authenticated, isFalse);
      await expectLater(
        session.headersFor('POST', protected),
        throwsA(isA<LibraAuthException>()),
      );
      expect(calls, 1);
    });
  }

  for (final body in [
    '{}',
    'invalid-json',
    responseBody.replaceFirst('100', '0'),
    responseBody.replaceFirst('100', '-1'),
    responseBody.replaceFirst('["ROLE_SMART"]', 'null'),
    responseBody.replaceFirst('synthetic-token', ''),
    responseBody.replaceFirst('100', '"900"'),
  ]) {
    test('rejeita resposta incompleta ou inválida: $body', () async {
      final session = LibraAuthSession(
        client: LibraApiClient(clientFactory: () => TestClient(body: body)),
      );
      await expectLater(
        session.signIn(base, 'user', 'password'),
        throwsA(isA<LibraAuthException>()),
      );
      expect(session.authenticated, isFalse);
    });
  }

  test(
    'timeout e falhas de rede não repetem login nem expõem erro bruto',
    () async {
      for (final failure in [
        TimeoutException('private'),
        const SocketException('private'),
        const HandshakeException('private'),
      ]) {
        final fake = TestClient(result: () async => throw failure);
        final session = LibraAuthSession(
          client: LibraApiClient(clientFactory: () => fake),
        );
        await expectLater(
          session.signIn(base, 'user', 'password'),
          throwsA(
            isA<LibraAuthException>().having(
              (e) => e.message.contains('private'),
              'sanitized',
              isFalse,
            ),
          ),
        );
        expect(fake.closed, isTrue);
      }
      final pending = Completer<HttpClientResponse>();
      final fake = TestClient(result: () => pending.future);
      final session = LibraAuthSession(
        client: LibraApiClient(
          timeout: const Duration(milliseconds: 1),
          clientFactory: () => fake,
        ),
      );
      await expectLater(
        session.signIn(base, 'user', 'password'),
        throwsA(
          isA<LibraAuthException>().having(
            (e) => e.failure,
            'failure',
            LibraAuthFailure.timeout,
          ),
        ),
      );
      expect(fake.closed, isTrue);
      pending.complete(TestResponse(200, responseBody));
    },
  );

  test('limpeza durante login descarta resposta tardia', () async {
    final pending = Completer<HttpClientResponse>();
    final session = LibraAuthSession(
      client: LibraApiClient(
        clientFactory: () => TestClient(result: () => pending.future),
      ),
    );
    final login = session.signIn(base, 'user', 'password');
    session.clear();
    pending.complete(TestResponse(200, responseBody));
    await expectLater(login, throwsA(isA<LibraAuthException>()));
    expect(session.authenticated, isFalse);
  });

  testWidgets(
    'campos obrigatórios, máscara, login e ausência na persistência',
    (tester) async {
      final fake = TestClient(body: responseBody);
      final store = MemoryLibraSettingsStore();
      final settings = SettingsState(
        libraStore: store,
        libraAuth: LibraAuthSession(
          client: LibraApiClient(clientFactory: () => fake),
        ),
      );
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LibraAuthSettings(
                settings: settings,
                baseUrl: base,
                connectionDisabled: false,
              ),
            ),
          ),
        ),
      );
      final login = find.byKey(const ValueKey('libra-jwt-login'));
      await tester.tap(login);
      await tester.pump();
      expect(find.text('Informe o usuário de integração.'), findsOneWidget);
      expect(find.text('Informe a senha de integração.'), findsOneWidget);
      final user = find.byKey(const ValueKey('libra-jwt-username'));
      final password = find.byKey(const ValueKey('libra-jwt-password'));
      await tester.enterText(user, 'synthetic-user');
      await tester.enterText(password, 'synthetic-password');
      final input = find.descendant(
        of: password,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(input).obscureText, isTrue);
      await tester.tap(find.byTooltip('Mostrar senha'));
      await tester.pump();
      expect(tester.widget<EditableText>(input).obscureText, isFalse);
      await tester.tap(login);
      await tester.pumpAndSettle();
      expect(settings.libraAuth.authenticated, isTrue);
      await settings.saveLibraSettings();
      final saved = jsonEncode((await store.load()).toJson());
      for (final secret in [
        'synthetic-user',
        'synthetic-password',
        'synthetic-token',
      ]) {
        expect(saved.contains(secret), isFalse);
      }
      settings.update(() => settings.environment = StationEnvironment.producao);
      expect(settings.libraAuth.authenticated, isFalse);
    },
  );
}
