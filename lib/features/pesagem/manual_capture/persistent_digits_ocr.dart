import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'capture_models.dart';
import 'decimal_detector.dart';
import 'tesseract_runtime.dart';

/// One native Tesseract handle, one worker isolate, serialized requests. Model
/// remains loaded across frames and sessions. No subprocess/Python per frame.
class PersistentDigitsOcr {
  static final shared = PersistentDigitsOcr();
  Isolate? _isolate;
  SendPort? _port;
  Future<void> _tail = Future.value();
  Future<WeightOcrResult> recognize(Uint8List image, {bool prepared = false}) {
    final result = Completer<WeightOcrResult>();
    _tail = _tail.then((_) async {
      final replies = ReceivePort();
      try {
        if (_port == null) {
          final ready = ReceivePort();
          final runtime = TesseractRuntime.resolve();
          _isolate = await Isolate.spawn(_worker, [
            ready.sendPort,
            File(runtime.executable).absolute.parent.path,
            runtime.tessdataDirectory ??
                TesseractRuntime.resolveModelDirectory(),
          ]);
          _port =
              await ready.first.timeout(const Duration(seconds: 8)) as SendPort;
          ready.close();
        }
        _port!.send([image, replies.sendPort, prepared]);
        result.complete(
          await replies.first.timeout(const Duration(seconds: 5))
              as WeightOcrResult,
        );
      } catch (error) {
        _isolate?.kill(priority: Isolate.immediate);
        _isolate = null;
        _port = null;
        result.complete(
          WeightOcrResult(
            error: error is TimeoutException
                ? 'OCR_TIMEOUT'
                : 'OCR_ENGINE_INDISPONIVEL',
            engineMessage: error.toString(),
          ),
        );
      } finally {
        replies.close();
      }
    });
    return result.future;
  }

  Future<void> close() async {
    await _tail;
    if (_port != null) {
      final reply = ReceivePort();
      _port!.send(['close', reply.sendPort]);
      try {
        await reply.first.timeout(const Duration(seconds: 3));
      } finally {
        reply.close();
        _isolate?.kill(priority: Isolate.immediate);
      }
    }
    _port = null;
    _isolate = null;
  }
}

void _worker(List<Object> args) {
  final input = ReceivePort();
  (args[0] as SendPort).send(input.sendPort);
  _NativeDigits? engine;
  input.listen((message) {
    if (message is List && message.first == 'close') {
      engine?.close();
      input.close();
      (message[1] as SendPort).send(true);
      return;
    }
    final request = message as List;
    final timer = Stopwatch()..start();
    WeightOcrResult result;
    try {
      engine ??= _NativeDigits(args[1] as String, args[2] as String);
      result = engine!
          .read(request[0] as Uint8List, prepared: request[2] as bool)
          .copyWith(elapsedMs: timer.elapsedMilliseconds);
    } catch (error) {
      result = WeightOcrResult(
        error: 'OCR_ENGINE_INDISPONIVEL',
        engineMessage: error.toString(),
      );
    }
    (request[1] as SendPort).send(result);
  });
}

class _NativeDigits {
  _NativeDigits(String folder, String data) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows Tesseract DLL required');
    }
    lib = DynamicLibrary.open('$folder/libtesseract-5.dll');
    final crt = DynamicLibrary.open('msvcrt.dll');
    allocate = crt
        .lookupFunction<
          Pointer<Uint8> Function(IntPtr),
          Pointer<Uint8> Function(int)
        >('malloc');
    release = crt
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    handle = lib
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'TessBaseAPICreate',
        )();
    final path = string(data), language = string('eng');
    final init = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
          int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)
        >('TessBaseAPIInit3');
    final code = init(handle, path, language);
    release(path.cast());
    release(language.cast());
    if (code != 0) {
      close();
      throw StateError('Tesseract Init3 failed: $data');
    }
    final set = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
          int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)
        >('TessBaseAPISetVariable');
    for (final entry in {
      'tessedit_char_whitelist': '0123456789',
      'load_system_dawg': '0',
      'load_freq_dawg': '0',
    }.entries) {
      final key = string(entry.key), value = string(entry.value);
      final ok = set(handle, key, value);
      release(key.cast());
      release(value.cast());
      if (ok == 0) {
        close();
        throw StateError('Unsupported Tesseract variable ${entry.key}');
      }
    }
    lib.lookupFunction<
      Void Function(Pointer<Void>, Int32),
      void Function(Pointer<Void>, int)
    >('TessBaseAPISetPageSegMode')(handle, 7);
  }
  late final DynamicLibrary lib;
  late final Pointer<Void> handle;
  late final Pointer<Uint8> Function(int) allocate;
  late final void Function(Pointer<Void>) release;
  Pointer<Uint8> string(String value) {
    final bytes = utf8.encode(value);
    final pointer = allocate(bytes.length + 1);
    if (pointer == nullptr) throw StateError('Allocation failed');
    pointer.asTypedList(bytes.length + 1).setAll(0, [...bytes, 0]);
    return pointer;
  }

  WeightOcrResult read(Uint8List bytes, {bool prepared = false}) {
    var source = img.decodeImage(bytes);
    if (source == null) {
      return const WeightOcrResult(error: 'OCR_IMAGE_INVALID');
    }
    // Project the large character bodies without classifying digits or locating
    // a decimal. Avoid the old connected-component crop (holes inside zeros).
    final geometry = prepared
        ? const DisplayGeometry()
        : analyzeDisplayGeometry(bytes);
    final boxes = geometry.characters;
    if (boxes.length >= 2 &&
        geometry.digitHeight > 12 &&
        boxes.every(
          (b) =>
              b.top > 0 &&
              b.left > 0 &&
              b.bottom < source!.height &&
              b.right < source.width,
        )) {
      final margin = (geometry.digitHeight * .10).ceil();
      final left = math.max(
        0,
        boxes.map((b) => b.left).reduce(math.min) - margin,
      );
      final top = math.max(
        0,
        boxes.map((b) => b.top).reduce(math.min) - margin,
      );
      final right = math.min(
        source.width,
        boxes.map((b) => b.right).reduce(math.max) + margin,
      );
      final bottom = math.min(
        source.height,
        boxes.map((b) => b.bottom).reduce(math.max) + margin,
      );
      source = img.copyCrop(
        source,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );
    }
    // No automatic upscale or bank of variants.
    final scale = math.min(
      1.0,
      math.min(1200 / source.width, 180 / source.height),
    );
    final image = img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
    );
    final gray = prepared
        ? img.grayscale(image)
        : img.invert(img.normalize(img.grayscale(image), min: 0, max: 255));
    final pixels = allocate(gray.width * gray.height);
    if (pixels == nullptr) throw StateError('Allocation failed');
    Pointer<Uint8> text = nullptr;
    final monitor = lib
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'TessMonitorCreate',
        )();
    try {
      final buffer = pixels.asTypedList(gray.width * gray.height);
      for (final p in gray) {
        buffer[p.y * gray.width + p.x] = p.r.toInt();
      }
      lib.lookupFunction<
        Void Function(
          Pointer<Void>,
          Pointer<Uint8>,
          Int32,
          Int32,
          Int32,
          Int32,
        ),
        void Function(Pointer<Void>, Pointer<Uint8>, int, int, int, int)
      >('TessBaseAPISetImage')(
        handle,
        pixels,
        gray.width,
        gray.height,
        1,
        gray.width,
      );
      lib.lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('TessMonitorSetDeadlineMSecs')(monitor, 1500);
      final code = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Void>),
            int Function(Pointer<Void>, Pointer<Void>)
          >('TessBaseAPIRecognize')(handle, monitor);
      if (code != 0) return const WeightOcrResult(error: 'OCR_TIMEOUT');
      text = lib
          .lookupFunction<
            Pointer<Uint8> Function(Pointer<Void>),
            Pointer<Uint8> Function(Pointer<Void>)
          >('TessBaseAPIGetUTF8Text')(handle);
      final output = <int>[];
      if (text != nullptr) {
        for (var i = 0; i < 4096 && text[i] != 0; i++) {
          output.add(text[i]);
        }
      }
      final confidence =
          lib.lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('TessBaseAPIMeanTextConf')(handle) /
          100;
      final stage = Uint8List.fromList(img.encodePng(gray));
      final result = WeightOcrResult(
        rawText: utf8.decode(output).trim(),
        confidence: confidence,
        model: 'eng',
        strategy: 'persistent_digits',
        diagnostics: {
          'persistent': true,
          'inputWidth': gray.width,
          'inputHeight': gray.height,
          'whitelist': '0123456789',
        },
      );
      return result.copyWith(
        attempts: [OcrAttempt('persistent_digits', stage, result)],
      );
    } finally {
      if (text != nullptr) {
        lib.lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('TessDeleteText')(text);
      }
      lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('TessMonitorDelete')(monitor);
      lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('TessBaseAPIClear')(handle);
      release(pixels.cast());
    }
  }

  void close() =>
      lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('TessBaseAPIDelete')(handle);
}
