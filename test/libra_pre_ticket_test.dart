import 'dart:async';

import 'support/libra_http_fake.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/core/libra/libra_api_client.dart';
import 'package:balanca_desktop/core/libra/libra_configuration.dart';
import 'package:balanca_desktop/core/libra/pre_ticket_dto.dart';
import 'package:balanca_desktop/core/offline/offline_models.dart';
import 'package:balanca_desktop/features/configuracoes/settings_models.dart';
import 'package:balanca_desktop/features/pesagem/pre_ticket_service.dart';

void main() {
  final base = Uri.parse('https://libra.example.invalid');
  // Valor sintético, sem qualquer credencial de ambiente real.
  const placeholder = 'synthetic-test-placeholder';
  Future<Object?> call(LibraApiClient api) => api.getPreTickets(
    baseUrl: base,
    apiKey: placeholder,
    unitCode: 4,
    plate: 'ABC1D23',
  );

  test('URL, parâmetros, header, redirect e logs sem credencial', () async {
    final http = TestClient(body: payload);
    final logs = <String>[];
    final result = await call(
      LibraApiClient(clientFactory: () => http, log: logs.add),
    );
    expect(http.uri!.path, '/api/v1/pre-tickets');
    expect(http.uri!.origin, base.origin);
    expect(http.uri!.queryParameters, {
      'cdUnidadeBalanca': '4',
      'placa': 'ABC1D23',
    });
    expect(http.request.headers.values['x-api-key'] == placeholder, isTrue);
    expect(http.request.followRedirects, isFalse);
    expect(http.closed, isTrue);
    expect(result, isA<List>());
    expect(logs.single, contains('status=200'));
    expect(logs.join().contains(placeholder), isFalse);
    expect(logs.join(), isNot(contains('ABC1D23')));
  });

  for (final status in [401, 403, 500, 302]) {
    test('HTTP $status é erro funcional, sem corpo/segredo nos logs', () async {
      final http = TestClient(status: status, body: placeholder);
      final logs = <String>[];
      final api = LibraApiClient(clientFactory: () => http, log: logs.add);
      await expectLater(
        call(api),
        throwsA(
          isA<LibraException>().having(
            (e) => e.failure,
            'falha',
            status == 401 || status == 403
                ? LibraFailure.authentication
                : LibraFailure.server,
          ),
        ),
      );
      expect(logs.single, contains('status=$status'));
      expect(logs.join().contains(placeholder), isFalse);
      expect(http.closed, isTrue);
    });
  }
  for (final entry in [
    (200, ''),
    (200, '[]'),
    (200, '{}'),
    (204, ''),
    (404, ''),
  ]) {
    test('resposta vazia ${entry.$1}/${entry.$2}', () async {
      final http = TestClient(status: entry.$1, body: entry.$2);
      final result = await call(LibraApiClient(clientFactory: () => http));
      expect(PreTicketDto.decode(result), isEmpty);
    });
  }
  for (final failure in [
    LibraFailure.timeout,
    LibraFailure.communication,
    LibraFailure.certificate,
  ]) {
    test('trata $failure e fecha conexão', () async {
      final http = TestClient(
        result: () {
          if (failure == LibraFailure.timeout) {
            return Completer<HttpClientResponse>().future;
          }
          if (failure == LibraFailure.certificate) {
            throw const HandshakeException('teste');
          }
          throw const SocketException('teste');
        },
      );
      final api = LibraApiClient(
        clientFactory: () => http,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        call(api),
        throwsA(
          isA<LibraException>().having((e) => e.failure, 'falha', failure),
        ),
      );
      expect(http.closed, isTrue);
    });
  }
  test('DTO, documentos agrupados, lista e campos XFER', () {
    final tickets = PreTicketDto.decode(jsonDecode(payload));
    final ticket = tickets.single;
    expect(ticket.nota, '1; 2');
    expect(ticket.sequencia, '7');
    expect(ticket.tipoOperacao, 'XFER');
    expect(ticket.numeroTicketOrigem, '80');
    expect(ticket.codigoUnidadeOrigem, '2');
    expect(ticket.pesoLiquidoOrigem, 1200);
    final values = PreTicketDto.operationValues(tickets);
    expect(values['Peso N.F. (Kg)'], '1234.5');
    expect(values['Motorista'], 'Motorista de teste');
    expect(values['Transportador'], 'Transportadora de teste');
    expect(values['Emissor(es)'], 'Cooperativa');
    expect(values['Depósito'], 'JAPY');
    expect(values['Tipo do documento'], 'NF-e');
    expect(values['Embalagem'], 'Granel');
    expect(PreTicketDto.decode(jsonDecode(payload)[0]), hasLength(1));
    expect(
      PreTicketDto.operationValues([...tickets, ...tickets])['Peso N.F. (Kg)'],
      '2469.0',
    );
    expect(
      () => PreTicketDto.decode({'error': 'incompatível'}),
      throwsA(isA<LibraException>()),
    );
    expect(
      () => PreTicketDto.decode([
        {'nota': {}},
      ]),
      throwsA(isA<LibraException>()),
    );
  });
  test('ambiente sem fallback DSV em HML/PRD e credencial ausente', () async {
    final config = LibraConfiguration(environment: {});
    expect(
      config.baseUrl(StationEnvironment.desenvolvimento).toString(),
      LibraConfiguration.developmentBaseUrl,
    );
    expect(config.baseUrl(StationEnvironment.producao), isNull);
    expect(config.baseUrl(StationEnvironment.homologacao), isNull);
    expect(config.apiKey(StationEnvironment.desenvolvimento).isEmpty, isTrue);
    expect(config.mock, isFalse);
    for (final value in [
      'http://example.invalid',
      'https://secret@example.invalid',
      'https://example.invalid?q=secret',
    ]) {
      expect(
        LibraConfiguration(environment: {'LIBRA_BASE_URL_DSV': value})
            .baseUrl(StationEnvironment.desenvolvimento),
        isNull,
      );
    }
  });
  test(
    'service lê unidade/ambiente atuais, normaliza placa e não inventa carreta',
    () async {
      final settings = SettingsState()
        ..environment = StationEnvironment.desenvolvimento;
      addTearDown(settings.dispose);
      final clients = <TestClient>[];
      final service = PreTicketService(
        settings: settings,
        configuration: LibraConfiguration(
          environment: {'LIBRA_API_KEY_DSV': placeholder},
        ),
        client: LibraApiClient(
          clientFactory: () {
            final http = TestClient(body: payload);
            clients.add(http);
            return http;
          },
        ),
      );
      final result = await service.lookup('abc-1d23', StationConnection.online);
      expect(result!.trailers, isEmpty);
      expect(result.preTickets.single.tipoOperacao, 'XFER');
      expect(clients.last.uri!.queryParameters['placa'], 'ABC1D23');
      expect(clients.last.uri!.queryParameters['cdUnidadeBalanca'], '4');
      settings.unitCode = 9;
      await service.lookup('ABC1D23', StationConnection.online);
      expect(clients.last.uri!.queryParameters['cdUnidadeBalanca'], '9');
      settings.environment = StationEnvironment.producao;
      await expectLater(
        service.lookup('ABC1D23', StationConnection.online),
        throwsA(
          isA<LibraException>().having(
            (e) => e.failure,
            'falha',
            LibraFailure.configuration,
          ),
        ),
      );
      await expectLater(
        service.lookup('ABC1D23', StationConnection.offline),
        throwsA(
          isA<LibraException>().having(
            (e) => e.failure,
            'falha',
            LibraFailure.offline,
          ),
        ),
      );
      expect(clients, hasLength(2));
    },
  );
}
