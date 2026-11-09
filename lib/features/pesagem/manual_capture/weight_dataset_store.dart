import 'dart:convert';
import 'dart:io';

import 'package:path_provider_windows/path_provider_windows.dart';

import 'capture_models.dart';
import 'image_processor.dart';

class WeightDatasetStore {
  const WeightDatasetStore({this.directory});
  final Directory? directory;
  Future<String> save(
    CapturedPhoto photo,
    DisplayRegion region,
    String indicatorModel,
  ) async {
    if (!['ind560', 'ind570'].contains(indicatorModel)) {
      throw const FormatException('Selecione IND560 ou IND570 para a amostra.');
    }
    if (!region.calibrated || !region.valid) {
      throw const FormatException('Calibre a ROI antes de coletar.');
    }
    final capture = await LocalCaptureImageProcessor().process(photo, region);
    final support = directory == null
        ? await PathProviderWindows().getApplicationSupportPath()
        : null;
    if (directory == null && support == null) {
      throw const FileSystemException('Diretório local indisponível');
    }
    final base = directory ?? Directory('$support/weight_vision/dataset');
    await base.create(recursive: true);
    final sample = await base.createTemp('${indicatorModel}_');
    // Raw driver file retained separately; normalized PNG has no drawn stamp.
    await File('${sample.path}/camera_original.bin').writeAsBytes(photo.bytes);
    await File('${sample.path}/original.png').writeAsBytes(capture.original!);
    await File('${sample.path}/roi_original.png').writeAsBytes(capture.rawRoi!);
    await File('${sample.path}/roi.png').writeAsBytes(capture.ocrInput);
    await File('${sample.path}/metadata.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'capturedAt': photo.capturedAt.toUtc().toIso8601String(),
        'indicatorModel': indicatorModel.toUpperCase(),
        'region': region.toJson(),
        'dimensions': capture.dimensions,
        'expected': null,
        'expectedSequence': null,
        'annotationImage': 'roi.png',
        'timestampDrawn': false,
        'sessionId': null,
        'split': null,
      }),
    );
    return sample.path;
  }
}
