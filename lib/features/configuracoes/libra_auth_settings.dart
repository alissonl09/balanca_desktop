import 'package:flutter/material.dart';

import '../../core/libra/libra_api_client.dart';
import 'settings_models.dart';
import 'settings_widgets.dart';

class LibraAuthSettings extends StatefulWidget {
  const LibraAuthSettings({
    super.key,
    required this.settings,
    required this.baseUrl,
    required this.connectionDisabled,
  });
  final SettingsState settings;
  final Uri? baseUrl;
  final bool connectionDisabled;
  @override
  State<LibraAuthSettings> createState() => _LibraAuthSettingsState();
}

class _LibraAuthSettingsState extends State<LibraAuthSettings> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true, _busy = false;
  String? _status;
  int _revision = 0;
  late StationEnvironment _environment;

  @override
  void initState() {
    super.initState();
    _environment = widget.settings.environment;
  }

  @override
  void didUpdateWidget(LibraAuthSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_environment != widget.settings.environment ||
        oldWidget.baseUrl != widget.baseUrl ||
        oldWidget.settings != widget.settings) {
      oldWidget.settings.libraAuth.clear();
      widget.settings.libraAuth.clear();
      _environment = widget.settings.environment;
      _username.clear();
      _password.clear();
      _hidden = true;
      _revision++;
      _busy = false;
      _status = null;
    }
  }

  void _edited(String _) {
    widget.settings.libraAuth.clear();
    setState(() {
      _revision++;
      _status = null;
    });
  }

  Future<void> _signIn() async {
    if (_busy || !_form.currentState!.validate()) return;
    final base = widget.baseUrl;
    if (base == null) {
      setState(
        () => _status = 'Informe uma URL HTTPS válida na integração Libra.',
      );
      return;
    }
    if (widget.connectionDisabled) {
      setState(
        () =>
            _status = 'Autenticação real desabilitada no modo mock ou offline.',
      );
      return;
    }
    final revision = _revision;
    setState(() {
      _busy = true;
      _status = null;
    });
    String message;
    try {
      await widget.settings.libraAuth.signIn(
        base,
        _username.text,
        _password.text,
      );
      message = 'Autenticação realizada para esta sessão.';
    } on LibraAuthException catch (error) {
      message = error.message;
    } catch (_) {
      message = 'Não foi possível concluir a autenticação.';
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _busy = false;
      _status = message;
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: 'Autenticação Libra-API',
    description:
        'Usuário, senha e token ficam somente em memória durante a sessão. '
        'Salvar configurações não grava essas credenciais. Utiliza a Base URL acima.',
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsFields(
            children: [
              TextFormField(
                key: const ValueKey('libra-jwt-username'),
                controller: _username,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Usuário de integração',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o usuário de integração.'
                    : null,
                onChanged: _edited,
              ),
              TextFormField(
                key: const ValueKey('libra-jwt-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: _hidden,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Senha de integração',
                  suffixIcon: IconButton(
                    tooltip: _hidden ? 'Mostrar senha' : 'Ocultar senha',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(
                      _hidden ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Informe a senha de integração.'
                    : null,
                onChanged: _edited,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('libra-jwt-login'),
                onPressed: _busy ? null : _signIn,
                icon: const Icon(Icons.lock_outline),
                label: Text(
                  _busy ? 'Autenticando…' : 'Autenticar nesta sessão',
                ),
              ),
              TextButton(
                key: const ValueKey('libra-jwt-clear'),
                onPressed: () {
                  widget.settings.libraAuth.clear();
                  _username.clear();
                  _password.clear();
                  setState(() {
                    _revision++;
                    _busy = false;
                    _hidden = true;
                    _status = 'Credenciais e token removidos da sessão.';
                  });
                },
                child: const Text('Limpar autenticação'),
              ),
            ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!, key: const ValueKey('libra-jwt-status')),
            ),
        ],
      ),
    ),
  );
}
