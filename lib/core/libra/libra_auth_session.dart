import 'libra_api_client.dart';

/// Uma rota só deve ser cadastrada após confirmação do contrato da Libra.
class LibraBearerRoute {
  const LibraBearerRoute(this.method, this.path);
  final String method, path;
}

/// Credenciais e token exclusivamente em memória; nunca faz replay de negócio.
class LibraAuthSession {
  LibraAuthSession({
    LibraApiClient? client,
    DateTime Function()? now,
    Set<LibraBearerRoute> verifiedRoutes = const {},
  }) : _client = client ?? LibraApiClient(),
       _now = now ?? DateTime.now,
       _routes = Set.unmodifiable(verifiedRoutes);

  final LibraApiClient _client;
  final DateTime Function() _now;
  final Set<LibraBearerRoute> _routes;
  Uri? _base;
  String? _username, _password, _token;
  DateTime? _renewAt;
  Future<String>? _pending;
  int _generation = 0;

  bool get authenticated => _token != null && _now().isBefore(_renewAt!);

  void clear() {
    _generation++;
    _base = null;
    _username = _password = _token = null;
    _renewAt = null;
    _pending = null;
  }

  Future<void> signIn(Uri baseUrl, String username, String password) async {
    clear();
    _base = baseUrl;
    _username = username;
    _password = password;
    await _accessToken();
  }

  Future<String> _accessToken() {
    if (authenticated) return Future.value(_token!);
    if (_base == null || _username == null || _password == null) {
      return Future.error(
        const LibraAuthException(LibraAuthFailure.configuration),
      );
    }
    return _pending ??= _login(_generation);
  }

  Future<String> _login(int generation) async {
    // Capture inputs before awaiting; switching environment invalidates the result.
    final base = _base;
    final username = _username;
    final password = _password;
    final started = _now();
    try {
      if (base == null || username == null || password == null) {
        throw const LibraAuthException(LibraAuthFailure.configuration);
      }
      final data = await _client.authenticate(
        baseUrl: base,
        username: username,
        password: password,
      );
      if (generation != _generation) {
        throw const LibraAuthException(LibraAuthFailure.configuration);
      }
      if (data is! Map<String, dynamic> ||
          data['accessToken'] is! String ||
          (data['accessToken'] as String).isEmpty ||
          RegExp(r'\s').hasMatch(data['accessToken'] as String) ||
          data['username'] is! String ||
          (data['username'] as String).trim().isEmpty ||
          data['roles'] is! List ||
          !(data['roles'] as List).every((r) => r is String) ||
          data['expiresIn'] is! num) {
        throw const LibraAuthException(LibraAuthFailure.invalidResponse);
      }
      final seconds = data['expiresIn'] as num;
      if (!seconds.isFinite || seconds <= 0 || seconds > 2147483647) {
        throw const LibraAuthException(LibraAuthFailure.invalidResponse);
      }
      // Margem proporcional de 10%, limitada a 30s. Nenhuma validade fixa.
      final lifetimeMs = (seconds * 1000).floor();
      final marginMs = (lifetimeMs * .1).floor().clamp(0, 30000);
      final renewAt = started.add(
        Duration(milliseconds: lifetimeMs - marginMs),
      );
      if (!_now().isBefore(renewAt)) {
        throw const LibraAuthException(LibraAuthFailure.invalidResponse);
      }
      _renewAt = renewAt;
      return _token = data['accessToken'] as String;
    } catch (_) {
      if (generation == _generation) {
        _token = null;
        _renewAt = null;
        // Após falha, exigir ação explícita do operador; evitar tempestade de login.
        _username = _password = null;
      }
      rethrow;
    } finally {
      if (generation == _generation) _pending = null;
    }
  }

  /// Opt-in por método/rota exatos, origem HTTPS e contrato confirmado.
  Future<Map<String, String>> headersFor(String method, Uri target) async {
    if (_base == null ||
        target.scheme != 'https' ||
        target.origin != _base!.origin ||
        target.userInfo.isNotEmpty ||
        target.hasFragment ||
        target.path == '/api/v1/auth' ||
        target.path == '/api/v1/pre-tickets' ||
        !_routes.any((r) => r.method == method && r.path == target.path)) {
      return const {};
    }
    final generation = _generation;
    final token = await _accessToken();
    if (generation != _generation) {
      throw const LibraAuthException(LibraAuthFailure.configuration);
    }
    return {'Authorization': 'Bearer $token'};
  }

  /// O chamador informa o header enviado. 403 não renova; nunca repete a operação.
  void handleResponse(int status, String? authorization) {
    if (status == 401 && _token != null && authorization == 'Bearer $_token') {
      _token = null;
      _renewAt = null;
    }
  }
}
