import 'package:flutter/material.dart';

import '../../core/libra/libra_api_client.dart';
import '../../core/libra/libra_configuration.dart';
import '../pesagem/pre_ticket_service.dart';
import '../pesagem/operation_preview.dart';
import 'settings_models.dart';
import 'settings_widgets.dart';
import 'libra_auth_settings.dart';

class LibraSettings extends StatefulWidget {
  const LibraSettings({
    super.key,
    required this.settings,
    this.configuration,
    this.client,
  });
  final SettingsState settings;
  final LibraConfiguration? configuration;
  final LibraApiClient? client;
  @override
  State<LibraSettings> createState() => _LibraSettingsState();
}

class _LibraSettingsState extends State<LibraSettings> {
  final _plate = TextEditingController();
  bool _hidden = true, _testing = false;
  String? _status;
  SettingsState get settings => widget.settings;
  late final _configuration = widget.configuration ?? LibraConfiguration();
  late StationEnvironment _visibleEnvironment;
  @override
  void initState() {
    super.initState();
    _visibleEnvironment = settings.environment;
  }

  @override
  void didUpdateWidget(LibraSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_visibleEnvironment != settings.environment) {
      _visibleEnvironment = settings.environment;
      _hidden = true;
      _status = null;
    }
  }

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    if (_testing) return;
    if (_configuration.mock) {
      setState(
        () => _status = 'Modo mock ativo. Teste real de conexão desabilitado.',
      );
      return;
    }
    final environment = settings.environment;
    final unit = settings.unitCode;
    final authentication = _configuration.authentication(
      environment,
      local: settings.libra,
    );
    if (!authentication.configured) {
      setState(() => _status = 'Credencial não configurada.');
      return;
    }
    if (!RegExp(r'^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$')
        .hasMatch(normalizePlate(_plate.text))) {
      setState(() => _status = 'Informe uma placa de teste válida.');
      return;
    }
    // Snapshot da configuração: alterações durante a chamada não alteram o diagnóstico.
    final base = _configuration.baseUrl(environment, local: settings.libra);
    setState(() {
      _testing = true;
      _status = null;
    });
    String result;
    try {
      await PreTicketService(
        settings: settings,
        configuration: _configuration,
        client: widget.client,
      ).testConnection(_plate.text);
      result = 'Conexão realizada.';
    } on LibraException catch (error) {
      result = switch (error.failure) {
        LibraFailure.authentication => 'Falha de autenticação.',
        LibraFailure.server => 'Endpoint indisponível.',
        LibraFailure.timeout => 'Timeout.',
        LibraFailure.communication => 'Erro de comunicação.',
        _ => error.message,
      };
    } catch (_) {
      result = 'Erro de comunicação.';
    }
    if (!mounted) return;
    final currentAuth = _configuration.authentication(
      settings.environment,
      local: settings.libra,
    );
    setState(() {
      _testing = false;
      _status =
          environment == settings.environment &&
              unit == settings.unitCode &&
              base ==
                  _configuration.baseUrl(
                    settings.environment,
                    local: settings.libra,
                  ) &&
              authentication.key == currentAuth.key &&
              authentication.value == currentAuth.value
          ? result
          : 'Configuração alterada. Teste a conexão novamente.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final environment = settings.environment;
    final entry = settings.libra.forEnvironment(environment.name);
    final base =
        _configuration
            .baseUrl(environment, local: settings.libra)
            ?.toString() ??
        '';
    return SettingsSection(
      title: 'Integração Libra',
      description: 'Solução temporária para ambiente controlado de testes. Salve as configurações para mantê-las nesta estação.',
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (settings.libra.loadFailed)
                const Text(
                  'Não foi possível carregar a configuração local da Libra. Revise os campos antes de salvar.',
                ),
              Text(
                'Ambiente: ${environment.label} · Unidade: ${settings.unitCode}',
              ),
              const SizedBox(height: 12),
              // Recria os campos ao trocar ambiente; o Value nunca é preenchido pelo fallback.
              KeyedSubtree(
                key: ValueKey('libra-${environment.name}'),
                child: SettingsFields(
                  children: [
                    TextFormField(
                      key: const ValueKey('libra-base-url'),
                      initialValue: entry.baseUrl.isEmpty
                          ? base
                          : entry.baseUrl,
                      decoration: const InputDecoration(labelText: 'Base URL'),
                      onChanged: (v) => settings.update(() {
                        entry.baseUrl = v;
                        _status = null;
                      }),
                      validator: (_) =>
                          _configuration.baseUrl(
                                    environment,
                                    local: settings.libra,
                                  ) ==
                                  null &&
                              entry.baseUrl.trim().isNotEmpty
                          ? 'Informe uma origem HTTPS válida.'
                          : null,
                    ),
                    TextFormField(
                      key: const ValueKey('libra-auth-key'),
                      initialValue: entry.authKey,
                      decoration: const InputDecoration(labelText: 'Auth Key'),
                      onChanged: (v) => settings.update(() {
                        entry.authKey = v;
                        entry.authOverride = true;
                        _status = null;
                      }),
                    ),
                    TextFormField(
                      key: const ValueKey('libra-auth-value'),
                      initialValue: entry.authValue,
                      obscureText: _hidden,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Auth Value',
                        suffixIcon: IconButton(
                          tooltip: _hidden ? 'Mostrar valor' : 'Ocultar valor',
                          onPressed: () => setState(() => _hidden = !_hidden),
                          icon: Icon(
                            _hidden ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                      onChanged: (v) => settings.update(() {
                        entry.authValue = v;
                        entry.authOverride = true;
                        _status = null;
                      }),
                    ),
                    TextFormField(
                      key: const ValueKey('libra-test-plate'),
                      controller: _plate,
                      decoration: const InputDecoration(
                        labelText: 'Placa de teste',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('libra-test-connection'),
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(_testing ? 'Testando conexão…' : 'Testar conexão'),
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _status!,
                    key: const ValueKey('libra-connection-status'),
                  ),
                ),
              const SizedBox(height: 16),
              LibraAuthSettings(
                settings: settings,
                baseUrl: _configuration.baseUrl(
                  environment,
                  local: settings.libra,
                ),
                connectionDisabled:
                    _configuration.mock || _configuration.offline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
