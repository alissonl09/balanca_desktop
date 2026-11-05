import 'dart:convert';
import 'dart:io';

import 'package:path_provider_windows/path_provider_windows.dart';

import 'capture_models.dart';
import 'image_processor.dart';

abstract interface class OcrDiagnosticsStore {
  Future<String?> save(
    ProcessedCapture capture,
    WeightOcrResult result,
    DisplayRegion region,
  );
}

/// Called only for an explicitly enabled debug diagnostic. Never in release.
/// Bounded to 10 sessions per application launch, with no automatic deletion.
class LocalOcrDiagnosticsStore implements OcrDiagnosticsStore {
  LocalOcrDiagnosticsStore({this.directory});
  final Future<Directory> Function()? directory;
  int _sessions = 0;
  @override
  Future<String?> save(
    ProcessedCapture capture,
    WeightOcrResult result,
    DisplayRegion region,
  ) async {
    if (_sessions >= 10) return null;
    _sessions++;
    Directory base;
    if (directory != null) {
      base = await directory!();
    } else {
      final path = await PathProviderWindows().getApplicationSupportPath();
      if (path == null) {
        throw const FileSystemException(
          'Diretório de diagnóstico indisponível.',
        );
      }
      base = Directory('$path/manual_weighing/diagnostics');
    }
    await base.create(recursive: true);
    final run = await base.createTemp('ocr_');
    if (capture.original != null) {
      await File('${run.path}/original.png').writeAsBytes(capture.original!);
    }
    await File('${run.path}/roi.png').writeAsBytes(capture.ocrInput);
    await File('${run.path}/evidence.jpg').writeAsBytes(capture.evidence);
    for (var i = 0; i < result.attempts.length; i++) {
      final attempt = result.attempts[i];
      if (attempt.image.isEmpty) continue;
      final label =
          '${attempt.result.model}_${attempt.result.psm}_${attempt.strategy}'
              .replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
      await File('${run.path}/${i}_$label.png').writeAsBytes(attempt.image);
    }
    await File('${run.path}/result.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'capturedLocallyAt': DateTime.now().toIso8601String(),
        'region': region.toJson(),
        'rawText': result.rawText,
        'weight': result.weight,
        'ocrConfidence': result.ocrConfidence,
        'finalConfidence': result.finalConfidence,
        'consensus': result.consensus,
        'model': result.model,
        'psm': result.psm,
        'pipeline': result.strategy,
        'elapsedMs': result.elapsedMs,
        'failure': result.error,
        'attempts': result.attempts.map((a) => a.toJson()).toList(),
      }),
    );
    return run.path;
  }
}
