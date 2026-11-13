import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum LibraFailure {
  configuration,
  authentication,
  communication,
  timeout,
  server,
  response,
  offline,
  certificate,
}

class LibraException implements Exception {
  const LibraException(this.failure);
  final LibraFailure failure;
  String get message => switch (failure) {
    LibraFailure.configuration =>
      'Revise a URL e os campos de autenticação da Libra para este ambiente.',
    LibraFailure.authentication =>
      'Não foi possível autenticar a aplicação na Libra.',
    LibraFailure.communication => 'Não foi possível comunicar com a Libra.',
    LibraFailure.timeout =>
      'A consulta à Libra excedeu o tempo limite. Tente novamente.',
    LibraFailure.server =>
      'A Libra apresentou um erro ao consultar o pré-ticket.',
    LibraFailure.response =>
      'A Libra retornou uma resposta de pré-ticket inválida.',
    LibraFailure.offline => 'Estação offline. Consulta à Libra indisponível.',
    LibraFailure.certificate =>
      'Não foi possível validar o certificado HTTPS da Libra.',
  };
  @override
  String toString() => message;
}

/// Sem interceptores de terceiros. Nunca registra headers, corpo ou exceções brutas.
class LibraApiClient {
  LibraApiClient({
    this.timeout = const Duration(seconds: 15),
    HttpClient Function()? clientFactory,
    void Function(String)? log,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _log = log ?? (kDebugMode ? debugPrint : null);

  final Duration timeout;
  final HttpClient Function() _clientFactory;
  final void Function(String)? _log;

  Future<Object?> getPreTickets({
    required Uri baseUrl,
    required String apiKey,
    String authKey = 'x-api-key',
    bool notFoundIsEmpty = true,
    required int unitCode,
    required String plate,
  }) async {
    final hasAuthentication = authKey.trim().isNotEmpty && apiKey.isNotEmpty;
    if ((hasAuthentication &&
            (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(authKey) ||
                apiKey.contains(RegExp(r'[\r\n]')))) ||
        unitCode <= 0 ||
        baseUrl.scheme != 'https' ||
        baseUrl.host.isEmpty ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment) {
      throw const LibraException(LibraFailure.configuration);
    }
    final uri = baseUrl.replace(
      path: '/api/v1/pre-tickets',
      queryParameters: {'cdUnidadeBalanca': '$unitCode', 'placa': plate},
    );
    final client = _clientFactory();
    final watch = Stopwatch()..start();
    int? status;
    var outcome = 'erro';
    try {
      final result = await (() async {
        final request = await client.getUrl(uri);
        // Não encaminha a credencial em redirecionamentos.
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (hasAuthentication) request.headers.set(authKey, apiKey);
        final response = await request.close();
        status = response.statusCode;
        if (status == 401 || status == 403) {
          throw const LibraException(LibraFailure.authentication);
        }
        if ((status == 404 && notFoundIsEmpty) || status == 204) return null;
        if (status != 200) throw const LibraException(LibraFailure.server);
        final body = await utf8.decoder.bind(response).join();
        if (body.trim().isEmpty) return null;
        return jsonDecode(body);
      })().timeout(timeout);
      outcome = 'sucesso';
      return result;
    } on TimeoutException {
      outcome = 'timeout';
      throw const LibraException(LibraFailure.timeout);
    } on HandshakeException {
      outcome = 'tls';
      throw const LibraException(LibraFailure.certificate);
    } on FormatException {
      throw const LibraException(LibraFailure.response);
    } on IOException {
      throw const LibraException(LibraFailure.communication);
    } finally {
      client.close(force: true);
      // Host/rota configurados, sem parâmetros, placa, headers ou corpo.
      _log?.call(
        'Libra GET ${baseUrl.origin}/api/v1/pre-tickets '
        'status=${status ?? "indisponível"} ms=${watch.elapsedMilliseconds} $outcome',
      );
    }
  }
}
