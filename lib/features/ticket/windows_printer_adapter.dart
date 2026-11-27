import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'print_settings.dart';
import 'printer_service.dart';
import 'ticket_print_renderer.dart';

const windowsPrintWorkerArgument = '--balanca-print-worker';

/// Mantém o driver e a rasterização em um processo separado da tela de pesagem.
class WindowsPrinterAdapter implements PrintJobAdapter {
  WindowsPrinterAdapter({String? executable})
    : _executable = executable ?? Platform.resolvedExecutable;

  final String _executable;
  bool _waitingForWorkerExit = false;

  @override
  Future<List<String>> queues() async {
    final response = await _request('queues', const {}, _queryTimeout);
    return List<String>.from(response['queues'] as List);
  }

  @override
  Future<PrinterQueueInfo> inspect(String queue) async {
    final response = await _request('inspect', {'queue': queue}, _queryTimeout);
    return PrinterQueueInfo([
      for (final paper in response['papers'] as List)
        PrinterPaper.fromJson(paper as Map<String, dynamic>),
    ], status: response['status'] as String?);
  }

  @override
  Future<PrintResult> printJob(
    PrintTarget target,
    PrintDocument document,
    Duration timeout,
  ) async {
    if (_waitingForWorkerExit) return const PrintResult(PrintStatus.busy);
    try {
      final response = await _request('print', {
        'target': target.toJson(),
        'document': document.toJson(),
      }, timeout);
      return _resultFromJson(response);
    } on PrinterException catch (error) {
      return error.result;
    } catch (_) {
      return const PrintResult(PrintStatus.unknown);
    }
  }

  static const _queryTimeout = Duration(seconds: 12);

  Future<Map<String, dynamic>> _request(
    String operation,
    Map<String, Object?> data,
    Duration timeout,
  ) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Impressão disponível no Windows.');
    }
    Directory? job;
    var cleanupHere = true;
    try {
      job = await Directory.systemTemp.createTemp('balanca-print-');
      final directory = job;
      final budget = Stopwatch()..start();
      await _workerFile(directory, 'request.json').writeAsString(
        jsonEncode({
          'operation': operation,
          'deadline': DateTime.now().add(timeout).millisecondsSinceEpoch,
          ...data,
        }),
        flush: true,
      );
      final process = await Process.start(_executable, [
        windowsPrintWorkerArgument,
        directory.path,
      ], workingDirectory: File(_executable).parent.path);
      unawaited(
        process.stdin.close().then<void>((_) {}, onError: (Object _) {}),
      );
      unawaited(process.stdout.drain<void>().catchError((Object _) {}));
      unawaited(process.stderr.drain<void>().catchError((Object _) {}));
      final remaining = timeout - budget.elapsed;
      final exited = await process.exitCode
          .then<int?>((value) => value)
          .timeout(
            remaining.isNegative ? Duration.zero : remaining,
            onTimeout: () => null,
          );
      if (exited == null) {
        process.kill();
        final stopped = await process.exitCode
            .then<int?>((value) => value)
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
        if (stopped == null) {
          cleanupHere = false;
          if (operation == 'print') _waitingForWorkerExit = true;
          unawaited(
            process.exitCode.then((_) async {
              if (operation == 'print') _waitingForWorkerExit = false;
              await _cleanupWorker(directory);
            }),
          );
          throw const PrinterException(
            PrintResult(
              PrintStatus.unknown,
              detail: 'O processo de impressão ainda não encerrou.',
            ),
          );
        }
      }

      try {
        final response = await _readWorkerJson(directory, 'response.json');
        if (response['error'] case final Map<String, dynamic> error) {
          throw PrinterException(_resultFromJson(error));
        }
        return response;
      } on PrinterException {
        rethrow;
      } catch (_) {
        throw PrinterException(
          await _workerFailure(directory, timedOut: exited == null),
        );
      }
    } on PrinterException {
      rethrow;
    } catch (_) {
      if (job != null) throw PrinterException(await _workerFailure(job));
      throw const PrinterException(
        PrintResult(
          PrintStatus.queueUnavailable,
          detail: 'Não foi possível iniciar o processo de impressão.',
        ),
      );
    } finally {
      if (cleanupHere && job != null) await _cleanupWorker(job);
    }
  }
}

File _workerFile(Directory directory, String name) =>
    File('${directory.path}/$name');

Future<Map<String, dynamic>> _readWorkerJson(
  Directory directory,
  String name,
) async =>
    jsonDecode(await _workerFile(directory, name).readAsString())
        as Map<String, dynamic>;

Future<void> _cleanupWorker(Directory directory) async {
  try {
    await directory.delete(recursive: true);
  } on FileSystemException {
    // A pasta é privada desta tentativa. Falhas de limpeza não mudam o envio.
  }
}

Future<PrintResult> _workerFailure(
  Directory directory, {
  bool timedOut = false,
}) async {
  final progress = timedOut ? 'Tempo limite excedido' : 'Processo interrompido';
  try {
    if (await _workerFile(directory, 'sending').exists()) {
      int? jobId;
      final job = _workerFile(directory, 'job-id');
      if (await job.exists()) jobId = int.tryParse(await job.readAsString());
      return PrintResult(
        PrintStatus.unknown,
        detail: '$progress durante o envio.',
        jobId: jobId,
      );
    }
    if (await _workerFile(directory, 'rendering').exists()) {
      return PrintResult(
        PrintStatus.generationError,
        detail: '$progress durante a geração do ticket.',
      );
    }
    return PrintResult(
      PrintStatus.queueUnavailable,
      detail: '$progress ao consultar o driver.',
    );
  } on FileSystemException {
    return const PrintResult(PrintStatus.unknown);
  }
}

Map<String, Object?> _resultJson(PrintResult result) => {
  'result': result.status.name,
  'detail': result.detail,
  'jobId': result.jobId,
};

PrintResult _resultFromJson(Map<String, dynamic> data) => PrintResult(
  PrintStatus.values.byName(data['result'] as String),
  detail: data['detail'] as String?,
  jobId: data['jobId'] as int?,
);

Future<void> runWindowsPrintWorker(Directory directory) async {
  Map<String, Object?> response;
  try {
    final request = await _readWorkerJson(directory, 'request.json');
    response = switch (request['operation']) {
      'queues' => {'queues': await Isolate.run(_queues)},
      'inspect' => await Isolate.run(
        () => _inspectResponse(request['queue'] as String),
      ),
      'render' => {
        'pages': (await _renderInWorker(
          directory,
          _workerDocument(request),
          PrintableArea(
            (request['widthMm'] as num).toDouble(),
            (request['heightMm'] as num).toDouble(),
            request['dpi'] as int,
          ),
          a4: request['a4'] == true,
        )).length,
      },
      'print' => _resultJson(await _printInWorker(directory, request)),
      _ => throw const FormatException('Operação de impressão inválida.'),
    };
  } on PrinterException catch (error) {
    response = {'error': _resultJson(error.result)};
  } catch (_) {
    response = {'error': _resultJson(await _workerFailure(directory))};
  }
  await _workerFile(
    directory,
    'response.json',
  ).writeAsString(jsonEncode(response), flush: true);
}

Map<String, Object?> _inspectResponse(String queue) {
  final info = _inspect(queue);
  return {
    'papers': [for (final paper in info.papers) paper.toJson()],
    'status': info.status,
  };
}

Future<PrintResult> _printInWorker(
  Directory directory,
  Map<String, dynamic> request,
) async {
  final target = PrintTarget.fromJson(
    request['target'] as Map<String, dynamic>,
  );
  final area = await Isolate.run(
    () => _queues().contains(target.queue) ? _prepare(target) : null,
  );
  if (area == null) return const PrintResult(PrintStatus.queueMissing);
  final document = _workerDocument(request);
  final pages = await _renderInWorker(
    directory,
    document,
    area,
    a4: target.format == PrinterFormat.a4,
  );
  if (pages.isEmpty) return const PrintResult(PrintStatus.generationError);
  final deadline = request['deadline'] as int;
  if (DateTime.now().millisecondsSinceEpoch >= deadline) {
    return const PrintResult(
      PrintStatus.generationError,
      detail: 'Tempo limite excedido antes do envio.',
    );
  }
  await _workerFile(directory, 'sending').create();
  return Isolate.run(
    () => _send(target, area, document.title, pages, directory, deadline),
  );
}

PrintDocument _workerDocument(Map<String, dynamic> request) =>
    PrintDocument.fromJson(request['document'] as Map<String, dynamic>);

Future<List<PrintPage>> _renderInWorker(
  Directory directory,
  PrintDocument document,
  PrintableArea area, {
  required bool a4,
}) async {
  await _workerFile(directory, 'rendering').create();
  return renderPrintDocument(document, area, a4: a4);
}

List<String> _queues() => using((arena) {
  const flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
  final needed = arena<Uint32>();
  final returned = arena<Uint32>();
  final first = EnumPrinters(flags, null, 4, null, 0, needed, returned);
  if (first.value && needed.value == 0) return [];
  if (!first.value && first.error != ERROR_INSUFFICIENT_BUFFER) {
    throw _winError('EnumPrinters', first.error);
  }
  for (var attempt = 0; attempt < 3; attempt++) {
    final size = needed.value;
    final buffer = arena<Uint8>(size);
    final result = EnumPrinters(flags, null, 4, buffer, size, needed, returned);
    if (result.value) {
      final entries = buffer.cast<PRINTER_INFO_4>();
      return {
        for (var i = 0; i < returned.value; i++)
          entries[i].pPrinterName.toDartString(),
      }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    if (result.error != ERROR_INSUFFICIENT_BUFFER || needed.value <= size) {
      throw _winError('EnumPrinters', result.error);
    }
  }
  throw const PrinterException(PrintResult(PrintStatus.queueUnavailable));
});

PrinterException _winError(String operation, WIN32_ERROR code) =>
    PrinterException(
      PrintResult(
        code == ERROR_INVALID_PRINTER_NAME
            ? PrintStatus.queueMissing
            : PrintStatus.queueUnavailable,
        detail: '$operation (Win32 $code).',
      ),
    );

PrinterQueueInfo _inspect(String queue) => _withPrinter(
  queue,
  (printer) => PrinterQueueInfo(printer.papers(), status: printer.status),
);

PrintableArea _prepare(PrintTarget target) =>
    _withPrinter(target.queue, (printer) {
      final (mode, paper) = printer.selectPaper(target);
      return printer.withDevice(mode, paper, _printableArea);
    });

PrintResult _send(
  PrintTarget target,
  PrintableArea area,
  String title,
  List<PrintPage> pages,
  Directory directory,
  int deadline,
) {
  PrintResult submit(HDC device) {
    if (DateTime.now().millisecondsSinceEpoch >= deadline) {
      return const PrintResult(
        PrintStatus.queueUnavailable,
        detail: 'Tempo limite do driver excedido antes de iniciar o trabalho.',
      );
    }
    return _submit(device, title, pages, target.copies, directory);
  }

  try {
    return _withPrinter(target.queue, (printer) {
      final (mode, paper) = printer.selectPaper(target);
      if (target.format == PrinterFormat.ticket && pages.length == 1) {
        final result = printer.tryShortRoll(
          area,
          mode,
          paper,
          pages.single,
          submit,
        );
        if (result != null) return result;
      }
      return printer.withDevice(mode, paper, (device) {
        if (!area.fits(_printableArea(device))) {
          return const PrintResult(
            PrintStatus.unsupportedPaper,
            detail: 'A área imprimível mudou. Atualize a configuração.',
          );
        }
        return submit(device);
      });
    });
  } on PrinterException catch (error) {
    return error.result;
  }
}

T _withPrinter<T>(String queue, T Function(_Printer) operation) =>
    using((arena) {
      final name = PCWSTR(queue.toNativeUtf16(allocator: arena));
      final handle = arena<Pointer>();
      final open = OpenPrinter(name, handle, null);
      if (!open.value) throw _winError('OpenPrinter', open.error);
      final printer = PRINTER_HANDLE(handle.value);
      try {
        final needed = arena<Uint32>();
        final size = GetPrinter(printer, 2, null, 0, needed);
        if (needed.value == 0) throw _winError('GetPrinter', size.error);
        final buffer = arena<Uint8>(needed.value);
        final info = GetPrinter(printer, 2, buffer, needed.value, needed);
        if (!info.value) throw _winError('GetPrinter', info.error);
        return operation(
          _Printer(printer, name, buffer.cast<PRINTER_INFO_2>().ref, arena),
        );
      } finally {
        ClosePrinter(printer);
      }
    });

class _Printer {
  _Printer(this.handle, this.name, this.info, this.arena);
  final PRINTER_HANDLE handle;
  final PCWSTR name;
  final PRINTER_INFO_2 info;
  final Arena arena;

  String? get status {
    final port = info.pPortName.toDartString().toUpperCase().split(',');
    if (port.any(
      (name) => name.trim() == 'PORTPROMPT:' || name.trim() == 'FILE:',
    )) {
      return 'A fila está configurada para solicitar um arquivo.';
    }
    final flags = info.Status;
    if (flags & 0x1 != 0) return 'O Windows informa que a fila está pausada.';
    if (flags & 0x80 != 0 || info.Attributes & 0x400 != 0) {
      return 'O Windows informa que a fila está offline.';
    }
    if (flags & 0x10 != 0) return 'O driver informa falta de papel.';
    if (flags & 0x8 != 0) return 'O driver informa atolamento de papel.';
    if (flags & (0x2 | 0x4 | 0x1000 | 0x100000) != 0) {
      return 'O driver informa uma condição que exige intervenção.';
    }
    return null;
  }

  int capabilities(int index, [Pointer? output]) => _deviceCapabilities(
    name,
    info.pPortName,
    index,
    output ?? nullptr,
    nullptr,
  );

  List<PrinterPaper> papers() {
    const idsIndex = 2, sizesIndex = 3, namesIndex = 16;
    final count = capabilities(idsIndex);
    if (count <= 0 ||
        count > 4096 ||
        capabilities(sizesIndex) != count ||
        capabilities(namesIndex) != count) {
      return [];
    }
    // A API não recebe o tamanho do buffer. Reserva espaço para alterações
    // da lista de formulários entre a contagem e a leitura.
    const capacity = 4096;
    final ids = arena<Uint16>(capacity);
    final sizes = arena<POINT>(capacity);
    final names = arena<Uint16>(capacity * 64);
    if (capabilities(idsIndex, ids) != count ||
        capabilities(sizesIndex, sizes) != count ||
        capabilities(namesIndex, names) != count) {
      return [];
    }
    return [
      for (var i = 0; i < count; i++)
        PrinterPaper(
          ids[i],
          String.fromCharCodes(
            names
                .asTypedList(count * 64)
                .skip(i * 64)
                .take(64)
                .takeWhile((unit) => unit != 0),
          ),
          sizes[i].x,
          sizes[i].y,
        ),
    ];
  }

  (Pointer<DEVMODE>, PrinterPaper) selectPaper(PrintTarget target) {
    if (status case final issue?) {
      throw PrinterException(
        PrintResult(PrintStatus.queueUnavailable, detail: issue),
      );
    }
    final available = papers();
    final paper = target.format == PrinterFormat.a4
        ? available.where((paper) => paper.isA4 && paper.id == 9).firstOrNull ??
              available.where((paper) => paper.isA4).firstOrNull
        : available
              .where((paper) => target.paper?.matches(paper) == true)
              .firstOrNull;
    if (paper == null) throw _paperError;

    final size = DocumentProperties(null, handle, name, null, null, 0);
    if (size < sizeOf<DEVMODE>()) throw _paperError;
    final mode = arena<Uint8>(size).cast<DEVMODE>();
    if (DocumentProperties(null, handle, name, mode, null, DM_OUT_BUFFER) !=
        1) {
      throw _paperError;
    }
    final options = mode.ref;
    options.dmFields =
        (options.dmFields & ~(DM_PAPERLENGTH | DM_PAPERWIDTH | DM_FORMNAME)) |
        DM_ORIENTATION |
        DM_PAPERSIZE;
    options.dmOrientation = 1; // DMORIENT_PORTRAIT
    options.dmPaperSize = paper.id.toSigned(16);
    options.dmCopies = 1;
    options.dmDuplex = DMDUP_SIMPLEX;
    if (!_validate(mode)) throw _paperError;
    return (mode, paper);
  }

  bool _validate(Pointer<DEVMODE> mode) =>
      DocumentProperties(
        null,
        handle,
        name,
        mode,
        mode,
        DM_IN_BUFFER | DM_OUT_BUFFER,
      ) ==
      1;

  T withDevice<T>(
    Pointer<DEVMODE> mode,
    PrinterPaper paper,
    T Function(HDC) use,
  ) {
    final device = CreateDC(null, name, null, mode);
    if (device == nullptr) throw _paperError;
    try {
      if (!_matchesPhysicalSize(device, paper)) throw _paperError;
      if (GetDeviceCaps(device, RASTERCAPS) & RC_STRETCHDIB == 0) {
        throw const PrinterException(
          PrintResult(
            PrintStatus.queueUnavailable,
            detail: 'O driver não oferece impressão gráfica.',
          ),
        );
      }
      return use(device);
    } finally {
      DeleteDC(device);
    }
  }

  /// Drivers que aceitam comprimento personalizado podem terminar perto do conteúdo.
  /// A forma selecionada continua válida quando o driver ignora o ajuste.
  PrintResult? tryShortRoll(
    PrintableArea original,
    Pointer<DEVMODE> mode,
    PrinterPaper paper,
    PrintPage page,
    PrintResult Function(HDC) use,
  ) {
    const minExtent = 4, maxExtent = 5;
    final min = capabilities(minExtent);
    final max = capabilities(maxExtent);
    if (min == -1 ||
        max == -1 ||
        paper.width < (min & 0xffff) ||
        paper.width > (max & 0xffff)) {
      return null;
    }
    final hardMargins = math.max(0, paper.height - original.heightMm * 10);
    final length = math.max(
      (min >> 16) & 0xffff,
      (page.height * 254 / page.dpi + hardMargins + 10).ceil(),
    );
    if (length >= paper.height - 20 ||
        length > ((max >> 16) & 0xffff) ||
        length > 32767 ||
        paper.width > 32767) {
      return null;
    }
    final options = mode.ref;
    options.dmFields =
        (options.dmFields & ~(DM_PAPERSIZE | DM_FORMNAME)) |
        DM_PAPERLENGTH |
        DM_PAPERWIDTH;
    options.dmPaperSize = 0;
    options.dmPaperLength = length;
    options.dmPaperWidth = paper.width;
    if (!_validate(mode)) return null;
    final device = CreateDC(null, name, null, mode);
    if (device == nullptr) return null;
    try {
      final area = _printableArea(device);
      if (!_matchesPhysicalSize(
            device,
            PrinterPaper(0, paper.name, paper.width, length),
          ) ||
          (area.widthMm - original.widthMm).abs() >= 0.15 ||
          page.height * 25.4 / page.dpi > area.heightMm ||
          GetDeviceCaps(device, RASTERCAPS) & RC_STRETCHDIB == 0) {
        return null;
      }
      return use(device);
    } finally {
      DeleteDC(device);
    }
  }
}

const _paperError = PrinterException(PrintResult(PrintStatus.unsupportedPaper));

PrintableArea _printableArea(HDC device) {
  final dpiX = GetDeviceCaps(device, LOGPIXELSX);
  final dpiY = GetDeviceCaps(device, LOGPIXELSY);
  if (dpiX <= 0 || dpiY <= 0) throw _paperError;
  return PrintableArea(
    GetDeviceCaps(device, HORZRES) * 25.4 / dpiX,
    GetDeviceCaps(device, VERTRES) * 25.4 / dpiY,
    math.max(dpiX, dpiY),
  );
}

bool _matchesPhysicalSize(HDC device, PrinterPaper paper) {
  final width =
      GetDeviceCaps(device, PHYSICALWIDTH) *
      254 /
      GetDeviceCaps(device, LOGPIXELSX);
  final height =
      GetDeviceCaps(device, PHYSICALHEIGHT) *
      254 /
      GetDeviceCaps(device, LOGPIXELSY);
  return (width - paper.width).abs() <= 15 &&
      (height - paper.height).abs() <= 15;
}

PrintResult _submit(
  HDC device,
  String title,
  List<PrintPage> pages,
  int copies,
  Directory directory,
) => using((arena) {
  final info = arena<_DocInfo>();
  info.ref
    ..size = sizeOf<_DocInfo>()
    ..name = title.toNativeUtf16(allocator: arena);
  final job = _startDoc(device, info);
  if (job <= 0) return const PrintResult(PrintStatus.sendError);
  try {
    _workerFile(directory, 'job-id').writeAsStringSync('$job', flush: true);
  } on FileSystemException {
    // Uma falha no registro do identificador não muda o envio já iniciado.
  }
  var accepted = false;
  try {
    for (var copy = 0; copy < copies; copy++) {
      for (final page in pages) {
        if (_startPage(device) <= 0 ||
            !_drawPage(device, page) ||
            _endPage(device) <= 0) {
          return PrintResult(PrintStatus.unknown, jobId: job);
        }
      }
    }
    accepted = _endDoc(device) > 0;
    return PrintResult(
      accepted ? PrintStatus.accepted : PrintStatus.unknown,
      jobId: job,
    );
  } finally {
    if (!accepted) _abortDoc(device);
  }
});

bool _drawPage(HDC device, PrintPage page) => using((arena) {
  final bitmap = arena<BITMAPINFO>();
  bitmap.ref.bmiHeader
    ..biSize = sizeOf<BITMAPINFOHEADER>()
    ..biWidth = page.width
    ..biHeight = -page.height
    ..biPlanes = 1
    ..biBitCount = 32
    ..biCompression = BI_RGB;
  final bytes = arena<Uint8>(page.pixels.length);
  final bgra = bytes.asTypedList(page.pixels.length);
  final rgba = page.pixels;
  for (var i = 0; i < rgba.length; i += 4) {
    bgra[i] = rgba[i + 2];
    bgra[i + 1] = rgba[i + 1];
    bgra[i + 2] = rgba[i];
  }
  SetStretchBltMode(device, HALFTONE);
  final result = StretchDIBits(
    device,
    0,
    0,
    (page.width * GetDeviceCaps(device, LOGPIXELSX) / page.dpi).floor(),
    (page.height * GetDeviceCaps(device, LOGPIXELSY) / page.dpi).floor(),
    0,
    0,
    page.width,
    page.height,
    bytes,
    bitmap,
    DIB_RGB_COLORS,
    SRCCOPY,
  );
  return result != 0 && result != -1;
});

final class _DocInfo extends Struct {
  @Int32()
  external int size;
  external Pointer<Utf16> name, output, dataType;
  @Uint32()
  external int type;
}

final _gdi = DynamicLibrary.open('gdi32.dll');
final _spooler = DynamicLibrary.open('winspool.drv');
final _deviceCapabilities = _spooler
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint16, Pointer, Pointer),
      int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer, Pointer)
    >('DeviceCapabilitiesW');
final _startDoc = _gdi
    .lookupFunction<
      Int32 Function(Pointer, Pointer<_DocInfo>),
      int Function(Pointer, Pointer<_DocInfo>)
    >('StartDocW');
typedef _NativePageCall = Int32 Function(Pointer);
typedef _PageCall = int Function(Pointer);
final _startPage = _gdi.lookupFunction<_NativePageCall, _PageCall>('StartPage');
final _endPage = _gdi.lookupFunction<_NativePageCall, _PageCall>('EndPage');
final _endDoc = _gdi.lookupFunction<_NativePageCall, _PageCall>('EndDoc');
final _abortDoc = _gdi.lookupFunction<_NativePageCall, _PageCall>('AbortDoc');
