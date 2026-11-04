import 'dart:io';

/// Prefer the engine shipped with the app. PATH is only a compatibility fallback.
class TesseractRuntime {
  const TesseractRuntime(this.executable, {this.tessdataDirectory});
  final String executable;
  final String? tessdataDirectory;

  static TesseractRuntime resolve({
    String? executable,
    String? applicationDirectory,
    String? workingDirectory,
    Map<String, String>? environment,
    bool? windows,
  }) {
    final env = environment ?? Platform.environment;
    const definedPath = String.fromEnvironment('TESSERACT_PATH');
    final override =
        executable ??
        (definedPath.isNotEmpty ? definedPath : env['TESSERACT_PATH']);
    TesseractRuntime at(String path, {bool bundled = false}) {
      final data = '${File(path).parent.path}/tessdata';
      return TesseractRuntime(
        path,
        tessdataDirectory: bundled || File('$data/eng.traineddata').existsSync()
            ? data
            : null,
      );
    }

    if (override != null && override.isNotEmpty) return at(override);
    if (!(windows ?? Platform.isWindows)) {
      return const TesseractRuntime('tesseract');
    }
    final app =
        applicationDirectory ?? File(Platform.resolvedExecutable).parent.path;
    final cwd = workingDirectory ?? Directory.current.path;
    for (final path in [
      '$app/ocr/tesseract.exe',
      '$cwd/runtime/windows/tesseract/tesseract.exe',
    ]) {
      if (File(path).existsSync()) return at(path, bundled: true);
    }
    for (final base in [
      env['ProgramW6432'],
      env['ProgramFiles'],
      env['ProgramFiles(x86)'],
      if (env['LOCALAPPDATA'] != null) '${env['LOCALAPPDATA']}/Programs',
    ]) {
      if (base == null) continue;
      final path = '$base/Tesseract-OCR/tesseract.exe';
      if (File(path).existsSync()) return at(path);
    }
    return const TesseractRuntime('tesseract');
  }
}

String ocrFailureMessage(String? code) => switch (code) {
  'OCR_ENGINE_INDISPONIVEL' => 'O motor OCR não foi encontrado. Reinstale a pasta completa do aplicativo, incluindo a pasta ocr.',
  'OCR_MODELO_INDISPONIVEL' => 'O modelo OCR está ausente. Verifique o arquivo ocr/tessdata/eng.traineddata.',
  'OCR_ENGINE_ERRO' => 'O motor OCR não conseguiu executar. Verifique a engine, suas DLLs e o modelo inglês.',
  'OCR_TIMEOUT' => 'O motor OCR excedeu o tempo de análise.',
  'OCR_BAIXA_CONFIANCA' =>
    'O OCR encontrou dígitos com baixa confiança. Ajuste foco e enquadramento.',
  'OCR_LEITURA_INSTAVEL' =>
    'O peso mudou entre as capturas. Aguarde estabilizar e tente novamente.',
  'OCR_VARIANTES_DIVERGENTES' || 'OCR_SEM_CONSENSO' => 'As análises do visor não concordaram. Ajuste a região dos dígitos e tente novamente.',
  'OCR_FORA_DA_FAIXA' => 'A leitura está fora da faixa de peso configurada.',
  _ => 'Não foi possível ler os dígitos. Enquadre somente o peso principal na região marcada.',
};
