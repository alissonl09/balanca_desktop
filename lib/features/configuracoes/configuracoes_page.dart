import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/visual_components.dart';
import 'printing_settings.dart';
import 'settings_mock_data.dart';
import 'settings_models.dart';
import 'settings_widgets.dart';
import '../ticket/ticket_session.dart';
import 'indicator_settings.dart';
import '../../core/indicators/indicator_models.dart';
import 'permissions_settings.dart';
import 'manual_webcam_settings.dart';
import 'libra_settings.dart';
import 'database_settings.dart';
import '../../core/permissions/permission_models.dart';
import '../access_control/access_control_state.dart';

enum _SettingsTab {
  general('Configurações Gerais'),
  vehicles('Gestão de Veículos'),
  printing('Impressão'),
  indicators('Indicadores de Peso'),
  models('Modelos de Indicadores'),
  permissions('Permissões'),
  database('Banco de Dados');

  const _SettingsTab(this.label);
  final String label;
  AppPermission get permission => switch (this) {
    general => AppPermission.generalSettings,
    vehicles => AppPermission.vehicleSettings,
    printing => AppPermission.printSettings,
    indicators => AppPermission.indicators,
    models => AppPermission.indicatorModels,
    permissions => AppPermission.permissions,
    database => AppPermission.maintainDatabase,
  };
}

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({
    super.key,
    required this.compact,
    required this.settings,
    required this.ticketSession,
  });
  final bool compact;
  final SettingsState settings;
  final TicketSession ticketSession;
  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final _form = GlobalKey<FormState>();
  _SettingsTab _tab = _SettingsTab.general;
  bool _hideToken = true;
  SettingsState get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    settings.addListener(_refresh);
    settings.permissions.addListener(_refresh);
  }

  @override
  void didUpdateWidget(ConfiguracoesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != settings) {
      oldWidget.settings.removeListener(_refresh);
      oldWidget.settings.permissions.removeListener(_refresh);
      settings.addListener(_refresh);
      settings.permissions.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    settings.removeListener(_refresh);
    settings.permissions.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {
    if (!settings.integratedSgv && _tab == _SettingsTab.vehicles) {
      _tab = _SettingsTab.general;
    }
  });

  bool _saving = false;
  Future<void> _save() async {
    if (_saving || _tab == _SettingsTab.database) return;
    if (!settings.permissions.allows(_tab.permission)) return;
    if (!settings.gateAssignmentsValid) {
      _message('Entrada e Saída devem usar cancelas diferentes.');
      return;
    }
    if (_tab == _SettingsTab.indicators) {
      for (final installation in settings.indicators.installations.where(
        (i) => i.active,
      )) {
        final model = settings.indicators.model(installation.modelCode);
        final errors = model == null
            ? ['Selecione um modelo.']
            : installation.validate(model);
        if (errors.isNotEmpty) {
          _message(errors.join('\n'));
          return;
        }
      }
      if (settings.indicators.mode == IndicatorMode.real) {
        final item = settings.indicators.operational;
        final issue = switch (item) {
          null => 'Selecione o indicador operacional da estação.',
          IndicatorInstallation(active: false) => null,
          IndicatorInstallation(
            connectionType: IndicatorConnectionType.serial,
          ) =>
            item.serialProtocolError,
          _ => 'A leitura operacional real requer transporte Serial.',
        };
        if (issue != null) {
          _message(issue);
          return;
        }
      }
    }
    final invalidOcr =
        settings.integratedSgv &&
        settings.ocr &&
        (settings.ocrAddress.trim().isEmpty ||
            settings.ocrPort == null ||
            settings.ocrPort! < 1 ||
            settings.ocrPort! > 65535);
    if (invalidOcr && _tab != _SettingsTab.printing) {
      setState(() => _tab = _SettingsTab.vehicles);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _form.currentState?.validate();
      });
      _message('Revise os campos indicados antes de salvar.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (_tab == _SettingsTab.printing) {
      final printing = settings.printing;
      for (final format in PrinterFormat.values) {
        final destination = printing.destination(format);
        if (!printing.simulated &&
            destination.enabled &&
            (destination.queue == null ||
                (format == PrinterFormat.ticket &&
                    destination.paper?.isRoll != true))) {
          _message('Selecione a fila e o papel de ${format.label}.');
          return;
        }
      }
      final preferred = printing.destination(printing.preferred);
      final savedMessage =
          !printing.simulated && preferred.queue != null && !preferred.enabled
          ? 'Configuração salva. Ative “Usar na pesagem” em ${printing.preferred.label} para imprimir tickets.'
          : 'Configuração de impressão salva nesta estação.';
      setState(() => _saving = true);
      try {
        await settings.savePrintSettings();
        if (mounted) _message(savedMessage);
      } catch (_) {
        if (mounted) {
          _message('Não foi possível salvar a configuração de impressão.');
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    if (_tab == _SettingsTab.indicators || _tab == _SettingsTab.models) {
      setState(() => _saving = true);
      try {
        await settings.saveIndicatorSettings(
          catalog: _tab == _SettingsTab.models,
        );
        if (mounted) {
          _message('Configuração de indicadores salva nesta estação.');
        }
      } catch (_) {
        if (mounted) {
          _message('Não foi possível salvar a configuração dos indicadores.');
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    if (_tab == _SettingsTab.general) {
      setState(() => _saving = true);
      try {
        await settings.saveLibraSettings();
        settings.libra.loadFailed = false;
        if (mounted) _message('Configuração da Libra salva nesta estação.');
      } catch (_) {
        if (mounted) {
          _message('Não foi possível salvar a configuração local da Libra.');
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    _message(
      'Configurações mantidas somente nesta sessão. Nenhuma integração foi acionada.',
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _SettingsTab.values.where(
      (tab) => tab != _SettingsTab.vehicles || settings.integratedSgv,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: VisualCard(
          key: const ValueKey('settings-main-card'),
          radius: 14,
          shadow: true,
          padding: widget.compact
              ? const EdgeInsets.symmetric(horizontal: 20, vertical: 16)
              : EdgeInsets.all(
                  MediaQuery.sizeOf(context).width <= 900 ? 18 : 26,
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeading(
                title: 'Configurações',
                subtitle: 'Gerencie os parâmetros de funcionamento do sistema de pesagem.',
                asset: 'config',
              ),
              SizedBox(height: widget.compact ? 14 : 22),
              Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      ...ScrollConfiguration.of(context).dragDevices,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: SingleChildScrollView(
                    key: const ValueKey('settings-tabs'),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final tab in tabs)
                          Container(
                            height: widget.compact ? 38 : 43,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: tab == _tab
                                  ? const Color(0xfff7faf8)
                                  : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(
                                  width: 3,
                                  color: tab == _tab
                                      ? AppColors.green
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                            child: TextButton(
                              key: ValueKey('settings-tab-${tab.name}'),
                              onPressed: () => setState(() {
                                _tab = tab;
                                _hideToken = true;
                              }),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                foregroundColor: tab == _tab
                                    ? AppColors.green
                                    : const Color(0xff687178),
                              ),
                              child: Text(tab.label),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: widget.compact ? 16 : 20),
              Form(
                key: _form,
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: !settings.permissions.allows(_tab.permission)
                      ? const SettingsSection(
                          title: 'Acesso restrito',
                          child: Text(
                            'Perfil sem permissão para esta configuração.',
                          ),
                        )
                      : switch (_tab) {
                          _SettingsTab.general => _general(),
                          _SettingsTab.vehicles => _vehicles(),
                          _SettingsTab.printing => PrintingSettings(
                            key: ValueKey(settings.indicatorStationId),
                            settings: settings,
                            ticketSession: widget.ticketSession,
                          ),
                          _SettingsTab.indicators => IndicatorSettings(
                            key: ValueKey(settings.indicatorStationId),
                            configuration: settings.indicators,
                            models: false,
                            serialIndicator: settings.serialIndicator,
                            loadFailed: settings.indicatorSettingsLoadFailed,
                          ),
                          _SettingsTab.models => IndicatorSettings(
                            configuration: settings.indicators,
                            models: true,
                            serialIndicator: settings.serialIndicator,
                          ),
                          _SettingsTab.permissions => PermissionsSettings(
                            permissions: settings.permissions,
                          ),
                          _SettingsTab.database => DatabaseSettings(
                            database: settings.database,
                            permissions: settings.permissions,
                          ),
                        },
                ),
              ),
              if (_tab != _SettingsTab.database) ...[
                const SizedBox(height: 16),
                const Text(
                  'Webcam, integração Libra, indicadores e impressão podem ser salvos nesta estação. As demais configurações permanecem na sessão.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    key: const ValueKey('save-settings'),
                    onPressed:
                        !_saving && settings.permissions.allows(_tab.permission)
                        ? _save
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Salvar configurações'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _general() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Configurações Gerais',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.bold,
          color: AppColors.heading,
        ),
      ),
      const SizedBox(height: 12),
      SettingsSection(
        title: 'Unidade da balança',
        description: 'Selecione a unidade desta estação. Opções simuladas, identificadas pelo código.',
        child: SettingsFields(
          children: [
            DropdownButtonFormField<int>(
              key: const ValueKey('station-unit'),
              initialValue: settings.unitCode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Unidade'),
              items: [
                for (final unit in mockUnits)
                  DropdownMenuItem(value: unit.code, child: Text(unit.label)),
              ],
              onChanged: (value) {
                if (value != null) {
                  settings.update(() => settings.unitCode = value);
                }
              },
            ),
            DropdownButtonFormField<StationEnvironment>(
              key: const ValueKey('station-environment'),
              initialValue: settings.environment,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ambiente'),
              items: [
                for (final environment in StationEnvironment.values)
                  DropdownMenuItem(
                    value: environment,
                    child: Text(environment.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  settings.update(() => settings.environment = value);
                }
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      LibraSettings(settings: settings),
      const SizedBox(height: 16),
      SettingsSection(
        title: 'Pesagem manual',
        description: 'Sem comunicação com o indicador, a pesagem manual fica disponível como contingência, mantendo a exigência de autorização.',
        child: SettingsToggle(
          key: const ValueKey('manual-weighing-enabled'),
          label: 'Pesagem manual',
          enabledLabel: 'Habilitado',
          disabledLabel: 'Desabilitado',
          value: settings.manualWeighingEnabled,
          onChanged: (v) =>
              settings.update(() => settings.manualWeighingEnabled = v),
        ),
      ),
      const SizedBox(height: 16),
      SettingsSection(
        title: 'Integração com SGV',
        description: 'Ativar exibe as opções de Gestão de Veículos. Nenhuma comunicação real é iniciada.',
        child: SettingsToggle(
          key: const ValueKey('sgv-integration'),
          label: 'Integrado ao sistema SGV (Gestão de Veículos)?',
          value: settings.integratedSgv,
          onChanged: (value) =>
              settings.update(() => settings.integratedSgv = value),
        ),
      ),
      const SizedBox(height: 16),
      ManualWebcamSettings(
        services: settings.manualCapture,
        manualWeighingEnabled: settings.manualWeighingEnabled,
      ),
    ],
  );

  Widget _vehicles() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsSection(
        title: 'Cancelas',
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SettingsToggle(
                    key: const ValueKey('barriers-enabled'),
                    label: 'Cancelas',
                    value: settings.barriers,
                    onChanged: (value) =>
                        settings.update(() => settings.barriers = value),
                  ),
                ),
                IconButton(
                  key: const ValueKey('reverse-gate-sides'),
                  tooltip: 'Inverter associação de Entrada e Saída',
                  icon: const Icon(Icons.autorenew_rounded),
                  color: AppColors.green,
                  visualDensity: VisualDensity.compact,
                  onPressed: settings.barriers ? settings.swapBarriers : null,
                ),
              ],
            ),
            if (settings.barriers) ...[
              const SizedBox(height: 12),
              SettingsFields(
                children: [
                  _barrier(
                    'gate-1',
                    'Cancela 1',
                    settings.gateSide(GateSlot.one),
                    settings.gateId(GateSlot.one),
                    settings.gateId(GateSlot.two),
                    (value) => _assignGate(GateSlot.one, value),
                  ),
                  _barrier(
                    'gate-2',
                    'Cancela 2',
                    settings.gateSide(GateSlot.two),
                    settings.gateId(GateSlot.two),
                    settings.gateId(GateSlot.one),
                    (value) => _assignGate(GateSlot.two, value),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      SettingsSection(
        title: 'Sinalização e informações',
        child: SettingsFields(
          children: [
            SettingsToggle(
              label: 'Semáforo',
              value: settings.trafficLight,
              onChanged: (value) =>
                  settings.update(() => settings.trafficLight = value),
            ),
            SettingsToggle(
              label: 'Display de Informações',
              value: settings.informationDisplay,
              onChanged: (value) =>
                  settings.update(() => settings.informationDisplay = value),
            ),
            if (settings.informationDisplay)
              TextFormField(
                key: const ValueKey('display-message'),
                initialValue: settings.displayMessage,
                maxLength: SettingsState.maxDisplayMessageLength,
                decoration: const InputDecoration(
                  labelText: 'Mensagem do display',
                  helperText: 'Texto exibido no painel eletrônico',
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe uma mensagem para o display.'
                    : null,
                onChanged: settings.setDisplayMessage,
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SettingsSection(
        title: 'OCR',
        description: 'Configuração de endereço, porta e autenticação. Sem comunicação nesta etapa.',
        child: Column(
          children: [
            SettingsToggle(
              key: const ValueKey('ocr-enabled'),
              label: 'OCR',
              value: settings.ocr,
              onChanged: (value) => settings.update(() => settings.ocr = value),
            ),
            if (settings.ocr) ...[
              const SizedBox(height: 12),
              SettingsFields(
                children: [
                  TextFormField(
                    key: const ValueKey('ocr-address'),
                    initialValue: settings.ocrAddress,
                    decoration: const InputDecoration(
                      labelText: 'Endereço',
                      hintText: 'IP ou host',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Informe o endereço do OCR.'
                        : null,
                    onChanged: (value) =>
                        settings.update(() => settings.ocrAddress = value),
                  ),
                  TextFormField(
                    key: const ValueKey('ocr-port'),
                    initialValue: settings.ocrPort?.toString() ?? '',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Porta',
                      helperText: 'Porta TCP de 1 a 65535.',
                    ),
                    validator: (value) {
                      final port = int.tryParse(value ?? '');
                      return port == null || port < 1 || port > 65535
                          ? 'Informe uma porta de 1 a 65535.'
                          : null;
                    },
                    onChanged: (value) => settings.update(
                      () => settings.ocrPort = int.tryParse(value),
                    ),
                  ),
                  TextFormField(
                    key: const ValueKey('ocr-token'),
                    initialValue: settings.ocrToken,
                    obscureText: _hideToken,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Token',
                      suffixIcon: IconButton(
                        tooltip: _hideToken ? 'Exibir token' : 'Ocultar token',
                        icon: Icon(
                          _hideToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _hideToken = !_hideToken),
                      ),
                    ),
                    onChanged: (value) =>
                        settings.update(() => settings.ocrToken = value),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      SettingsSection(
        title: 'Serviço de Voz',
        child: SettingsToggle(
          label: 'Serviço de Voz',
          value: settings.voice,
          onChanged: (value) => settings.update(() => settings.voice = value),
        ),
      ),
    ],
  );

  Widget _barrier(
    String key,
    String label,
    GateSide side,
    String? value,
    String? otherId,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey(key),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      helperText: side == GateSide.entry ? 'Entrada' : 'Saída',
    ),
    items: [
      for (final barrier in settings.gateEquipmentSource.available)
        DropdownMenuItem(
          value: barrier.id,
          enabled: barrier.id != otherId,
          child: Text('${barrier.name} (simulada)'),
        ),
    ],
    onChanged: onChanged,
  );

  void _assignGate(GateSlot slot, String? id) {
    if (!settings.assignGate(slot, id)) {
      _message('Entrada e Saída devem usar cancelas diferentes.');
      setState(() {});
    }
  }
}
