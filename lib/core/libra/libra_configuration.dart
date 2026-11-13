import 'dart:io';

import '../../features/configuracoes/settings_models.dart';
import 'libra_settings_store.dart';

class LibraAuthentication {
  const LibraAuthentication(this.key, this.value);
  final String key, value;
  bool get configured => key.trim().isNotEmpty && value.isNotEmpty;
}

/// Resolve a configuração local da estação e o fallback de processo.
class LibraConfiguration {
  LibraConfiguration({Map<String, String>? environment})
    : _environment = Map.unmodifiable(environment ?? Platform.environment);

  final Map<String, String> _environment;
  static const developmentBaseUrl = 'https://spring-dsv.cooxupe.com.br:8133';

  bool get mock => _environment['LIBRA_MODE'] == 'mock';
  bool get offline => _environment['LIBRA_OFFLINE'] == 'true';

  String _suffix(StationEnvironment environment) => switch (environment) {
    StationEnvironment.producao => 'PRD',
    StationEnvironment.homologacao => 'HML',
    StationEnvironment.desenvolvimento => 'DSV',
  };

  String apiKey(StationEnvironment environment) =>
      _environment['LIBRA_API_KEY_${_suffix(environment)}']?.trim() ?? '';

  LibraAuthentication authentication(
    StationEnvironment environment, {
    LibraSettingsData? local,
  }) {
    final entry = local?.environments[environment.name];
    if (entry != null && entry.authOverride) {
      return LibraAuthentication(entry.authKey.trim(), entry.authValue);
    }
    return LibraAuthentication('x-api-key', apiKey(environment));
  }

  Uri? baseUrl(StationEnvironment environment, {LibraSettingsData? local}) {
    final configured =
        local?.environments[environment.name]?.baseUrl.trim() ?? '';
    final value = configured.isNotEmpty
        ? configured
        : _environment['LIBRA_BASE_URL_${_suffix(environment)}'] ??
              (environment == StationEnvironment.desenvolvimento
                  ? developmentBaseUrl
                  : '');
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    return uri;
  }
}
