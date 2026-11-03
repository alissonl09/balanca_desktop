import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import 'preview_authentication.dart';
import 'weighing_preview.dart';
import 'manual_weighing_policy.dart';
import '../../core/permissions/permission_models.dart';

Future<bool?> showWeighingConfirmation(
  BuildContext context,
  WeighingPreview preview,
) => showDialog<bool>(
  context: context,
  builder: (_) => _ConfirmationDialog(preview: preview),
);

Future<ManualAuthorization?> showManualAuthentication(
  BuildContext context, {
  required PermissionState permissions,
}) => showDialog<ManualAuthorization>(
  context: context,
  builder: (_) => _AuthenticationDialog(permissions: permissions),
);

Future<double?> showManualWeightEntry(BuildContext context) =>
    showDialog<double>(
      context: context,
      builder: (_) => const _ManualWeightDialog(),
    );

class _ConfirmationDialog extends StatelessWidget {
  const _ConfirmationDialog({required this.preview});
  final WeighingPreview preview;

  @override
  Widget build(BuildContext context) {
    final contentWidth = math.min(
      620.0,
      math.max(
        0.0,
        MediaQuery.sizeOf(context).width -
            MediaQuery.paddingOf(context).horizontal -
            96,
      ),
    );
    final detailWidth = contentWidth >= 460
        ? (contentWidth - 16) / 2
        : contentWidth;
    final color = preview.isManual ? const Color(0xff9a5600) : AppColors.green;
    final details = {
      'Placa': preview.plate,
      'Carreta': preview.trailer,
      for (final entry in preview.operation.entries)
        if (entry.key != 'Destino') entry.key: entry.value,
    };
    return AlertDialog(
      key: const ValueKey('weighing-confirmation'),
      insetPadding: const EdgeInsets.all(24),
      scrollable: true,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Confirmação da Pesagem'),
          const SizedBox(height: 10),
          Text(
            preview.summary.isClosing
                ? 'FECHAMENTO DE PESO'
                : 'ABERTURA DE PESO',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: contentWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: .35)),
              ),
              child: Column(
                children: [
                  Text(
                    preview.isManual
                        ? 'PESO MANUAL • informado pelo operador'
                        : 'PESO AUTOMÁTICO • indicador desconectado',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatWeight(preview.currentWeight)} Kg',
                    style: TextStyle(
                      fontSize: 32,
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (preview.isManual)
                    Text('Liberado por: ${preview.manualOperator}'),
                  if (preview.isManual)
                    Text(
                      'Justificativa: ${preview.manualJustification ?? '-'}',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                for (final entry in details.entries)
                  SizedBox(
                    width: detailWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                        SelectableText(
                          entry.value.trim().isEmpty
                              ? 'Não informado'
                              : entry.value,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                for (final entry in preview.summary.values.entries)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      Text(
                        '${formatWeight(entry.value)} Kg',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Simulação local • sem gravação definitiva.',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Salvar Pesagem'),
        ),
      ],
    );
  }
}

class _AuthenticationDialog extends StatefulWidget {
  const _AuthenticationDialog({required this.permissions});
  final PermissionState permissions;
  @override
  State<_AuthenticationDialog> createState() => _AuthenticationDialogState();
}

class _AuthenticationDialogState extends State<_AuthenticationDialog> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _justification = TextEditingController();
  String? _error;

  void _release() {
    if (!authenticateManualPreview(_user.text, _password.text)) {
      setState(
        () => _error = 'Autenticação inválida. Verifique usuário e senha.',
      );
    } else if (!widget.permissions.userAllows(
      _user.text,
      AppPermission.authorizeManual,
    )) {
      setState(
        () => _error = 'Usuário sem permissão para autorizar Peso Manual.',
      );
    } else if (_justification.text.trim().isEmpty) {
      setState(() => _error = 'Informe a justificativa desta leitura manual.');
    } else {
      Navigator.pop(
        context,
        ManualAuthorization(
          user: _user.text,
          justification: _justification.text,
        ),
      );
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _justification.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('manual-authentication'),
    insetPadding: const EdgeInsets.all(24),
    scrollable: true,
    title: const Text('Liberar Peso Manual'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Autenticação provisória para teste local.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('manual-user'),
            controller: _user,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Usuário'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('manual-password'),
            controller: _password,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: const InputDecoration(labelText: 'Senha'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('manual-justification'),
            controller: _justification,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Justificativa',
              helperText: 'Obrigatória para esta leitura manual.',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      ElevatedButton(onPressed: _release, child: const Text('Liberar')),
    ],
  );
}

class _ManualWeightDialog extends StatefulWidget {
  const _ManualWeightDialog();
  @override
  State<_ManualWeightDialog> createState() => _ManualWeightDialogState();
}

class _ManualWeightDialogState extends State<_ManualWeightDialog> {
  final _weight = TextEditingController();
  final _form = GlobalKey<FormState>();

  double? get _value => double.tryParse(_weight.text.replaceAll(',', '.'));

  void _continue() {
    if (_form.currentState!.validate()) Navigator.pop(context, _value);
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('manual-weight-dialog'),
    insetPadding: const EdgeInsets.all(24),
    scrollable: true,
    title: const Text('Pesagem Manual'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xff523210),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                children: [
                  const Text(
                    'PESO MANUAL',
                    style: TextStyle(
                      color: Color(0xffffd58a),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('manual-weight'),
                    controller: _weight,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff523210),
                    ),
                    inputFormatters: [
                      TextInputFormatter.withFunction(
                        (oldValue, newValue) =>
                            RegExp(r'^\d{0,9}([,.]\d{0,3})?$')
                                .hasMatch(newValue.text)
                            ? newValue
                            : oldValue,
                      ),
                    ],
                    decoration: const InputDecoration(
                      hintText: '0',
                      suffixText: 'Kg',
                      filled: true,
                      fillColor: Color(0xfffff8ec),
                    ),
                    validator: (_) =>
                        _value == null || !_value!.isFinite || _value! <= 0
                        ? 'Informe um peso maior que zero.'
                        : null,
                    onFieldSubmitted: (_) => _continue(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Valor informado pelo operador.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xff9a5600),
          foregroundColor: Colors.white,
        ),
        onPressed: _continue,
        child: const Text('Prosseguir'),
      ),
    ],
  );
}
