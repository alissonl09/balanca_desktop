import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/tesseract_runtime.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ocr_runtime_');
  });
  tearDown(() async => root.delete(recursive: true));

  Future<String> executable(String relative) async {
    final file = File('${root.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([]);
    return file.path;
  }

  test('bundled engine wins over developer and installed copies', () async {
    final bundled = await executable('app/ocr/tesseract.exe');
    await executable('dev/runtime/windows/tesseract/tesseract.exe');
    final runtime = TesseractRuntime.resolve(
      windows: true,
      environment: {},
      applicationDirectory: '${root.path}/app',
      workingDirectory: '${root.path}/dev',
    );
    expect(File(runtime.executable).absolute.path, File(bundled).absolute.path);
    expect(runtime.tessdataDirectory, endsWith('/ocr/tessdata'));
  });
  test('explicit engine override does not silently use another engine', () {
    expect(
      TesseractRuntime.resolve(executable: 'missing_test_engine').executable,
      'missing_test_engine',
    );
  });
  test('developer runtime and standard install do not require PATH', () async {
    final dev = await executable('dev/runtime/windows/tesseract/tesseract.exe');
    final installed = await executable('programs/Tesseract-OCR/tesseract.exe');
    TesseractRuntime resolve(String cwd) => TesseractRuntime.resolve(
      windows: true,
      applicationDirectory: '${root.path}/empty',
      workingDirectory: cwd,
      environment: {'ProgramFiles': '${root.path}/programs'},
    );
    expect(File(resolve('${root.path}/dev').executable).path, File(dev).path);
    expect(
      File(resolve('${root.path}/empty').executable).path,
      File(installed).path,
    );
  });
  test('missing bundled model reports actionable failure', () async {
    final exe = await executable('app/ocr/tesseract.exe');
    final result = await TesseractWeightOcrService(
      runtime: TesseractRuntime(
        exe,
        tessdataDirectory: '${root.path}/app/ocr/tessdata',
      ),
    ).recognize(Uint8List(0));
    expect(result.error, 'OCR_MODELO_INDISPONIVEL');
    expect(result.weight, isNull);
  });
}
