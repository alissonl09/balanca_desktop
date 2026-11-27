import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ticket/printer_service.dart';
import '../ticket/ticket_mapper.dart';
import '../ticket/ticket_pesagem.dart';
import '../ticket/ticket_preview.dart';
import '../ticket/ticket_print_renderer.dart';
import '../ticket/ticket_session.dart';
import 'print_layout_preview.dart';
import 'settings_models.dart';
import 'settings_widgets.dart';

class PrintingSettings extends StatefulWidget {
  const PrintingSettings({
    super.key,
    required this.settings,
    required this.ticketSession,
  });
  final SettingsState settings;
  final TicketSession ticketSession;

  @override
  State<PrintingSettings> createState() => _PrintingSettingsState();
}

class _PrintingSettingsState extends State<PrintingSettings> {
  SettingsState get settings => widget.settings;
  PrintSettings get printing => settings.printing;
  PrinterService get service => settings.printerService;
  Future<List<String>>? _queues;
  final _queueDetails = <String, Future<PrinterQueueInfo>>{};

  void _refresh() {
    setState(() {
      _queueDetails.clear();
      _queues = service.queues();
    });
  }

  Future<void> _changeLogo() async {
    final logo = await showDialog<TicketLogo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Imagem do ticket'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, TicketLogo.standard),
            child: const Text('Logomarca padrão'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, TicketLogo.demonstration),
            child: const Text('Imagem de demonstração'),
          ),
        ],
      ),
    );
    if (mounted && logo != null) settings.update(() => printing.logo = logo);
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _test(PrinterFormat format) async {
    final draft = PrintSettings.fromJson(printing.toJson());
    final destination = draft.destination(format);
    final station = settings.indicatorStationId;
    _message(
      draft.simulated
          ? 'Executando teste simulado…'
          : 'Preparando teste de impressão…',
    );
    final result = await service.print(
      settings: draft,
      format: format,
      test: true,
      document: () => PrintDocument.test(
        station: '${Platform.localHostname} ($station)',
        queue: destination.queue!,
        paper: format == PrinterFormat.a4 ? 'A4' : destination.paper!.label,
        time: DateTime.now(),
        logo: draft.logo == TicketLogo.standard
            ? TicketLogoKind.standard
            : TicketLogoKind.demonstration,
      ),
    );
    if (mounted) _message(result.message);
  }

  @override
  Widget build(BuildContext context) {
    if (!printing.simulated) _queues ??= service.queues();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Destinos de impressão',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (settings.printSettingsLoadFailed)
                const Text(
                  'Falha ao carregar a configuração de impressão desta estação.',
                ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 250),
                    child: SettingsToggle(
                      label: 'Modo simulado',
                      value: printing.simulated,
                      onChanged: (value) {
                        if (value) {
                          _queues = null;
                          _queueDetails.clear();
                        }
                        settings.update(() => printing.simulated = value);
                      },
                    ),
                  ),
                  if (printing.simulated)
                    const Text('Prévia e testes simulados, sem envio.')
                  else
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Atualizar impressoras'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<PrinterFormat>(
                key: ValueKey(('print-preferred', printing.preferred)),
                initialValue: printing.preferred,
                decoration: const InputDecoration(
                  labelText: 'Destino preferencial',
                ),
                items: [
                  for (final format in PrinterFormat.values)
                    DropdownMenuItem(value: format, child: Text(format.label)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    settings.update(() => printing.preferred = value);
                  }
                },
              ),
            ],
          ),
        ),
        if (printing.simulated)
          _destinations(const [])
        else
          FutureBuilder<List<String>>(
            future: _queues,
            builder: (context, snapshot) {
              final waiting = snapshot.connectionState != ConnectionState.done;
              final queues = waiting ? const <String>[] : snapshot.data ?? [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (waiting)
                    const LinearProgressIndicator()
                  else if (snapshot.hasError)
                    const Text('Não foi possível listar as filas do Windows.')
                  else if (queues.isEmpty)
                    const Text(
                      'Nenhuma fila de impressão instalada no Windows.',
                    ),
                  _destinations(
                    queues,
                    checked: !waiting && !snapshot.hasError,
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Impressão automática na pesagem',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Usa o destino preferencial e a quantidade de vias desse destino. '
                'Desativar interrompe a impressão automática imediatamente. '
                'Salve para manter a mudança ou ativar a impressão.',
              ),
              const SizedBox(height: 8),
              SettingsFields(
                children: [
                  SettingsToggle(
                    key: const ValueKey('print-auto-entry'),
                    label: 'Imprimir na abertura (primeira pesagem)',
                    value: printing.emitEntry,
                    onChanged: (value) =>
                        settings.update(() => printing.emitEntry = value),
                  ),
                  SettingsToggle(
                    key: const ValueKey('print-auto-exit'),
                    label: 'Imprimir no fechamento (segunda pesagem)',
                    value: printing.emitExit,
                    onChanged: (value) =>
                        settings.update(() => printing.emitExit = value),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Identificação do ticket',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TicketLogoPreview(logo: printing.logo),
                  OutlinedButton.icon(
                    onPressed: _changeLogo,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('Alterar imagem'),
                  ),
                  TextButton(
                    onPressed: printing.logo == TicketLogo.standard
                        ? null
                        : () => settings.update(
                            () => printing.logo = TicketLogo.standard,
                          ),
                    child: const Text('Restaurar padrão'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('ticket-company-name'),
                initialValue: printing.companyName,
                decoration: const InputDecoration(
                  labelText: 'Texto ao lado da logomarca',
                  helperText: 'Em branco, usa o nome padrão da Cooxupé.',
                ),
                onChanged: (value) => printing.companyName = value,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Cabeçalho e rodapé do ticket',
          child: SettingsFields(
            children: [
              TicketTextField(
                label: 'Texto do Cabeçalho',
                fieldKey: 'ticket-header',
                initialValue: printing.header,
                onChanged: (value) =>
                    settings.update(() => printing.header = value),
              ),
              TicketTextField(
                label: 'Texto do Rodapé',
                fieldKey: 'ticket-footer',
                initialValue: printing.footer,
                onChanged: (value) =>
                    settings.update(() => printing.footer = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSection(
          title: 'Layouts de impressão',
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final format in PrinterFormat.values)
                OutlinedButton.icon(
                  onPressed: () => showTicketPreview(
                    context,
                    ticket: ticketFromSession(widget.ticketSession, settings),
                    format: format,
                  ),
                  icon: Icon(
                    format == PrinterFormat.ticket
                        ? Icons.receipt_long_outlined
                        : Icons.description_outlined,
                  ),
                  label: Text(
                    format == PrinterFormat.ticket
                        ? 'Visualizar Ticket'
                        : 'Visualizar A4',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _destinations(List<String> queues, {bool checked = false}) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 780;
          final width = columns
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            children: [
              for (final format in PrinterFormat.values)
                SizedBox(
                  width: width,
                  child: _destination(format, queues, checked: checked),
                ),
            ],
          );
        },
      );

  Widget _destination(
    PrinterFormat format,
    List<String> queues, {
    bool checked = false,
  }) {
    final destination = printing.destination(format);
    final queue = destination.queue;
    final installed = queues.contains(queue);
    final missing = checked && queue != null && !installed;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SettingsSection(
        title: format == PrinterFormat.ticket ? 'Cupom' : 'A4',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsToggle(
              key: ValueKey(('print-enabled', format)),
              label: 'Usar na pesagem',
              enabledLabel:
                  'Disponível para Impr. Pesagem e emissão automática',
              disabledLabel: 'Emissão pela tela de pesagem desativada',
              value: destination.enabled,
              onChanged: (enabled) => settings.update(() {
                destination.enabled = enabled;
                final otherEnabled = printing
                    .destination(format.alternative)
                    .enabled;
                if (enabled && !otherEnabled) {
                  printing.preferred = format;
                } else if (!enabled &&
                    otherEnabled &&
                    printing.preferred == format) {
                  printing.preferred = format.alternative;
                }
              }),
            ),
            SettingsFields(
              children: [
                if (!printing.simulated)
                  DropdownButtonFormField<String>(
                    key: ValueKey(('print-queue', format, queue, missing)),
                    initialValue: queue,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Impressora Windows',
                    ),
                    items: [
                      if (queue != null)
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Limpar seleção'),
                        ),
                      if (queue != null && !installed)
                        DropdownMenuItem(
                          value: queue,
                          enabled: false,
                          child: Text(
                            missing ? '$queue (fila não localizada)' : queue,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      for (final name in queues)
                        DropdownMenuItem(
                          value: name,
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) => settings.update(() {
                      destination.queue = value == '' ? null : value;
                      destination.paper = null;
                    }),
                  ),
                TextFormField(
                  key: ValueKey(('print-copies', format)),
                  initialValue: '${destination.copies}',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Quantidade de vias',
                  ),
                  validator: (value) => (int.tryParse(value ?? '') ?? 0) < 1
                      ? 'Informe pelo menos uma cópia.'
                      : null,
                  onChanged: (value) =>
                      destination.copies = int.tryParse(value) ?? 0,
                ),
              ],
            ),
            if (installed && queue != null)
              FutureBuilder<PrinterQueueInfo>(
                key: ValueKey(queue),
                future: _queueDetails.putIfAbsent(
                  queue,
                  () => service.inspect(queue),
                ),
                builder: (context, snapshot) =>
                    _paper(format, destination, snapshot),
              )
            else if (format == PrinterFormat.a4)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Papel A4 · Retrato'),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: ListenableBuilder(
                listenable: service,
                builder: (context, _) => OutlinedButton.icon(
                  onPressed: service.busy ? null : () => _test(format),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(
                    service.busy
                        ? 'Impressão em andamento…'
                        : 'Testar impressão',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paper(
    PrinterFormat format,
    PrintDestination destination,
    AsyncSnapshot<PrinterQueueInfo> snapshot,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const LinearProgressIndicator();
    }
    if (!snapshot.hasData) {
      return const Text('Não foi possível consultar o driver.');
    }
    final info = snapshot.requireData;
    final saved = destination.paper;
    final rolls = info.papers.where((paper) => paper.isRoll).toList();
    final current = rolls
        .where((paper) => saved?.matches(paper) == true)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        if (info.status case final status?) Text(status),
        if (format == PrinterFormat.a4)
          Text(
            info.papers.any((paper) => paper.isA4)
                ? 'Papel A4 · Retrato'
                : 'O driver não informa suporte a A4.',
          )
        else if (rolls.isEmpty)
          const Text('O driver não informa formatos de bobina.')
        else
          DropdownButtonFormField<PrinterPaper>(
            key: ValueKey((snapshot.data, current)),
            isExpanded: true,
            initialValue: current,
            decoration: InputDecoration(
              labelText: 'Papel da bobina',
              helperText: saved != null && current == null
                  ? 'O formato salvo não foi localizado no driver.'
                  : null,
            ),
            items: [
              for (final paper in rolls)
                DropdownMenuItem(
                  value: paper,
                  child: Text(paper.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) =>
                settings.update(() => destination.paper = value),
          ),
      ],
    );
  }
}
