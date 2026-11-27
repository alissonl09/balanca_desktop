import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'print_settings.dart';
import 'ticket_print_renderer.dart';

enum PrintStatus {
  notConfigured('Selecione a impressora Windows em Configurações > Impressão.'),
  disabled('Ative “Usar na pesagem” em Configurações > Impressão e salve.'),
  submissionCancelled('Envio cancelado antes da impressão.'),
  queueMissing('A fila configurada não foi localizada no Windows.'),
  queueUnavailable('A fila está indisponível antes do envio.'),
  unsupportedPaper('O driver não confirmou o papel selecionado.'),
  invalidCopies('Informe um número inteiro de cópias maior ou igual a 1.'),
  generationError('Não foi possível gerar o documento de impressão.'),
  accepted('Trabalho aceito pelo spooler do Windows.'),
  sendError('O Windows recusou o trabalho de impressão.'),
  unknown('Resultado do envio desconhecido. Confira a fila antes de repetir.'),
  busy('Já há um trabalho de impressão em processamento.'),
  simulated('Teste simulado de impressão.');

  const PrintStatus(this.message);
  final String message;
}

class PrintResult {
  const PrintResult(this.status, {this.detail, this.jobId});
  final PrintStatus status;
  final String? detail;
  final int? jobId;

  String get message => [
    status.message,
    if (jobId != null) 'Trabalho nº $jobId.',
    ?detail,
  ].join(' ');

  bool get canOfferAlternative => switch (status) {
    PrintStatus.notConfigured ||
    PrintStatus.disabled ||
    PrintStatus.queueMissing ||
    PrintStatus.queueUnavailable ||
    PrintStatus.unsupportedPaper => true,
    _ => false,
  };
}

class PrinterException implements Exception {
  const PrinterException(this.result);
  final PrintResult result;
}

class PrinterQueueInfo {
  const PrinterQueueInfo(this.papers, {this.status});
  final List<PrinterPaper> papers;
  final String? status;
}

class PrintTarget {
  const PrintTarget(this.queue, this.format, this.paper, this.copies);
  final String queue;
  final PrinterFormat format;
  final PrinterPaper? paper;
  final int copies;

  factory PrintTarget.fromJson(Map<String, dynamic> json) => PrintTarget(
    json['queue'] as String,
    PrinterFormat.values.byName(json['format'] as String),
    json['paper'] == null
        ? null
        : PrinterPaper.fromJson(json['paper'] as Map<String, dynamic>),
    json['copies'] as int,
  );

  Map<String, Object?> toJson() => {
    'queue': queue,
    'format': format.name,
    'paper': paper?.toJson(),
    'copies': copies,
  };
}

abstract interface class PrinterAdapter {
  Future<List<String>> queues();
  Future<PrinterQueueInfo> inspect(String queue);
}

abstract interface class PrintJobAdapter implements PrinterAdapter {
  Future<PrintResult> printJob(
    PrintTarget target,
    PrintDocument document,
    Duration timeout,
  );
}

abstract interface class RasterPrinterAdapter implements PrinterAdapter {
  Future<PrintableArea> prepare(PrintTarget target);
  Future<PrintResult> send(
    PrintTarget target,
    PrintableArea area,
    String title,
    List<PrintPage> pages,
  );
}

class PrinterService extends ChangeNotifier {
  PrinterService(
    this.adapter, {
    this.timeout = const Duration(seconds: 20),
    this.log,
  });

  final PrinterAdapter adapter;
  final Duration timeout;
  final void Function(Map<String, Object?>)? log;
  bool _busy = false, _disposed = false;
  bool get busy => _busy;

  Future<List<String>> queues() => adapter.queues().timeout(timeout);
  Future<PrinterQueueInfo> inspect(String queue) =>
      adapter.inspect(queue).timeout(timeout);

  Future<PrintResult> print({
    required PrintSettings settings,
    required PrinterFormat format,
    required FutureOr<PrintDocument> Function() document,
    String? ticketId,
    bool test = false,
    bool Function()? canSubmit,
  }) async {
    final destination = settings.destination(format);
    final queue = destination.queue;
    PrintResult report(PrintResult result) {
      final now = DateTime.now();
      log?.call({
        'horario': now.toIso8601String(),
        'formato': format.name,
        'fila': queue,
        'ticket': ticketId,
        'teste': test,
        'resultado': result.status.name,
        'trabalho': result.jobId,
        if (result.detail != null) 'detalhe': result.detail,
      });
      developer.log(
        'destino=${format.name} fila=${queue ?? "-"} '
        'ticket=${ticketId ?? "-"} teste=$test resultado=${result.status.name} '
        'trabalho=${result.jobId ?? "-"}',
        name: 'balanca.impressao',
        time: now,
      );
      return result;
    }

    if (_busy) return report(const PrintResult(PrintStatus.busy));
    if (settings.simulated) {
      return report(const PrintResult(PrintStatus.simulated));
    }
    if (queue == null || queue.isEmpty) {
      return report(const PrintResult(PrintStatus.notConfigured));
    }
    if (!test && !destination.enabled) {
      return report(const PrintResult(PrintStatus.disabled));
    }
    if (destination.copies < 1) {
      return report(const PrintResult(PrintStatus.invalidCopies));
    }
    final target = PrintTarget(
      queue,
      format,
      destination.paper,
      destination.copies,
    );
    if (format == PrinterFormat.ticket && (target.paper?.isRoll != true)) {
      return report(const PrintResult(PrintStatus.unsupportedPaper));
    }
    _setBusy(true);
    var pendingSend = false;
    try {
      final driver = adapter;
      if (driver is PrintJobAdapter) {
        late PrintDocument data;
        try {
          data = await Future.sync(document).timeout(timeout);
        } catch (_) {
          return report(const PrintResult(PrintStatus.generationError));
        }
        if (canSubmit?.call() == false) {
          return report(const PrintResult(PrintStatus.submissionCancelled));
        }
        return report(await driver.printJob(target, data, timeout));
      }
      if (driver is! RasterPrinterAdapter) {
        return report(const PrintResult(PrintStatus.queueUnavailable));
      }
      late PrintableArea area;
      try {
        final installed = await queues();
        if (!installed.contains(queue)) {
          return report(const PrintResult(PrintStatus.queueMissing));
        }
        area = await driver.prepare(target).timeout(timeout);
      } on PrinterException catch (error) {
        return report(error.result);
      } catch (_) {
        return report(const PrintResult(PrintStatus.queueUnavailable));
      }

      late PrintDocument data;
      late List<PrintPage> pages;
      try {
        data = await Future.sync(document).timeout(timeout);
        pages = await renderPrintDocument(
          data,
          area,
          a4: format == PrinterFormat.a4,
        ).timeout(timeout);
        if (pages.isEmpty) throw StateError('Documento vazio.');
      } catch (_) {
        return report(const PrintResult(PrintStatus.generationError));
      }
      if (canSubmit?.call() == false) {
        return report(const PrintResult(PrintStatus.submissionCancelled));
      }
      // Não libera um novo trabalho enquanto uma chamada nativa vencida puder enviar.
      final send = Future.sync(
        () => driver.send(target, area, data.title, pages),
      );
      pendingSend = true;
      var lateResult = false;
      unawaited(
        send.then(
          (result) {
            _setBusy(false);
            if (lateResult) report(result);
          },
          onError: (Object _) {
            _setBusy(false);
          },
        ),
      );
      try {
        return report(await send.timeout(timeout));
      } catch (_) {
        lateResult = true;
        return report(const PrintResult(PrintStatus.unknown));
      }
    } finally {
      if (!pendingSend) _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
