import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'indicator_driver.dart';
import 'indicator_models.dart';

/// Uma instância por tentativa. Toda operação sobre o handle ocorre no worker.
class WindowsSerialTransport implements IndicatorTransport {
  final _bytes = StreamController<List<int>>();
  final _opened = Completer<void>();
  final _exited = Completer<void>();
  ReceivePort? _events;
  SendPort? _commands;
  bool _closing = false;

  static Future<List<String>> availablePorts() async {
    if (!Platform.isWindows) return [];
    return Isolate.run(_enumerate);
  }

  static List<String> _enumerate() => using((arena) {
    final count = arena<Uint32>();
    var capacity = 32;
    for (var attempt = 0; attempt < 4; attempt++) {
      final ports = arena<Uint32>(capacity);
      final code = GetCommPorts(ports, capacity, count);
      if (code == ERROR_FILE_NOT_FOUND) return [];
      if (code == ERROR_SUCCESS) {
        final numbers = ports.asTypedList(count.value).toSet().toList()..sort();
        return [for (final number in numbers) 'COM$number'];
      }
      if (code != ERROR_MORE_DATA) {
        throw _SerialFault('Falha ao enumerar portas COM (Win32 $code).');
      }
      capacity = count.value;
    }
    throw const _SerialFault(
      'A lista de portas COM mudou. Atualize novamente.',
    );
  });

  @override
  Stream<List<int>> get bytes => _bytes.stream;

  @override
  Future<void> connect(IndicatorInstallation installation) async {
    if (!Platform.isWindows) {
      throw const _SerialFault('A comunicação COM está disponível no Windows.');
    }
    if (!RegExp(r'^COM[1-9][0-9]*$').hasMatch(installation.comPort)) {
      throw const _SerialFault('Porta COM inválida.');
    }
    final events = _events = ReceivePort();
    events.listen(_handleEvent);
    await Future.wait<void>([
      _opened.future,
      Isolate.spawn(
        _runWorker,
        (events.sendPort, installation.toJson()),
        onExit: events.sendPort,
        onError: events.sendPort,
        debugName: 'Indicador ${installation.comPort}',
      ).then<void>((_) {}, onError: (Object _) => _handleEvent(null)),
    ]);
  }

  void _handleEvent(Object? event) {
    switch (event) {
      case SendPort():
        _commands = event;
        _opened.complete();
        event.send(!_closing);
      case Uint8List():
        if (!_closing && event.isNotEmpty) _bytes.add(event);
        // Só solicita o próximo lote depois de receber este.
        if (!_closing) _commands?.send(true);
      case _SerialFault():
        if (!_opened.isCompleted) {
          _opened.completeError(event);
        } else if (!_closing) {
          _bytes.addError(event);
        }
      case null:
        if (!_opened.isCompleted) {
          _opened.completeError(
            const _SerialFault('O leitor serial encerrou durante a abertura.'),
          );
        }
        _events?.close();
        unawaited(_bytes.close());
        _exited.complete();
    }
  }

  @override
  Future<void> disconnect() async {
    if (_events == null) return;
    if (!_closing) {
      _closing = true;
      _commands?.send(false);
    }
    await _exited.future;
  }

  static Future<void> _runWorker(
    (SendPort, Map<String, Object?>) request,
  ) async {
    final (events, json) = request;
    final item = IndicatorInstallation.fromJson(json);
    final commands = ReceivePort();
    final arena = Arena();
    HANDLE? handle;
    try {
      final path = arena.pcwstr(r'\\.\' + item.comPort);
      final opened = CreateFile(
        path,
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_MODE(0),
        null,
        OPEN_EXISTING,
        FILE_FLAGS_AND_ATTRIBUTES(0),
        null,
      );
      if (opened.value == INVALID_HANDLE_VALUE) {
        throw _SerialFault.open(item.comPort, opened.error);
      }
      handle = opened.value;
      _configure(handle, item, arena);
      final buffer = arena<Uint8>(1024);
      final received = arena<Uint32>();
      final lineErrors = arena<Uint32>();
      events.send(commands.sendPort);
      await for (final read in commands) {
        if (read != true) break;
        _check(ReadFile(handle, buffer, 1024, received, null), 'Leitura');
        _check(ClearCommError(handle, lineErrors, null), 'Estado da linha');
        if (lineErrors.value != 0) {
          throw _SerialFault(
            'Erro na linha serial (máscara 0x${lineErrors.value.toRadixString(16)}). Confira cabo e parâmetros.',
          );
        }
        events.send(Uint8List.fromList(buffer.asTypedList(received.value)));
      }
    } on _SerialFault catch (error) {
      events.send(error);
    } catch (_) {
      events.send(
        const _SerialFault('Falha inesperada do leitor serial do Windows.'),
      );
    } finally {
      if (handle != null) CloseHandle(handle);
      commands.close();
      arena.releaseAll();
    }
  }

  static void _configure(
    HANDLE handle,
    IndicatorInstallation item,
    Arena arena,
  ) {
    final dcb = arena<DCB>();
    dcb.ref.DCBlength = sizeOf<DCB>();
    _check(GetCommState(handle, dcb), 'Configuração atual da porta');
    final softwareFlow = item.flowControl == 'XON/XOFF' ? 1 : 0;
    dcb.ref
      ..bitfield = 0
      ..fBinary = 1
      ..fParity = item.parity == 'None' ? 0 : 1
      ..fOutX = softwareFlow
      ..fInX = softwareFlow
      ..XonChar = CHAR(0x11)
      ..XoffChar = CHAR(0x13)
      ..BaudRate = item.baudRate!
      ..ByteSize = item.dataBits!
      ..Parity = switch (item.parity) {
        'Even' => EVENPARITY,
        'Odd' => ODDPARITY,
        _ => NOPARITY,
      }
      ..StopBits = item.stopBits == 2 ? TWOSTOPBITS : ONESTOPBIT;
    _check(SetCommState(handle, dcb), 'Parâmetros da porta');
    final timeouts = arena<COMMTIMEOUTS>();
    timeouts.ref.ReadTotalTimeoutConstant = 50;
    _check(SetCommTimeouts(handle, timeouts), 'Timeout do driver');
  }

  static void _check(Win32Result<bool> result, String operation) {
    if (!result.value) {
      final error = result.error;
      if (error == ERROR_DEVICE_NOT_CONNECTED ||
          error == ERROR_INVALID_HANDLE) {
        throw _SerialFault('Porta serial desconectada (Win32 $error).');
      }
      throw _SerialFault('$operation: falha no driver serial (Win32 $error).');
    }
  }
}

class _SerialFault implements Exception {
  const _SerialFault(this.message);
  final String message;

  factory _SerialFault.open(
    String port,
    WIN32_ERROR error,
  ) => _SerialFault(switch (error) {
    ERROR_FILE_NOT_FOUND ||
    ERROR_PATH_NOT_FOUND ||
    ERROR_DEVICE_NOT_CONNECTED =>
      '$port inexistente ou desconectada (Win32 $error).',
    ERROR_SHARING_VIOLATION || ERROR_LOCK_VIOLATION =>
      '$port ocupada (Win32 $error). Feche o ComTool, a Portaria ou outro leitor.',
    ERROR_ACCESS_DENIED =>
      'Acesso negado a $port (Win32 $error). O driver também pode usar esse código '
          'para porta ocupada. Confira permissões e feche o ComTool, a Portaria ou outro leitor.',
    _ => 'Falha do driver ao abrir $port (Win32 $error).',
  });

  @override
  String toString() => message;
}
