import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider_windows/path_provider_windows.dart';

import 'capture_models.dart';

abstract interface class ManualWeighingEvidenceStore {
  Future<String> savePhoto(String attemptId, Uint8List stampedImage);
  Future<void> save(ManualWeighingEvidence evidence);
}

abstract interface class WebcamConfigurationStore {
  Future<WebcamConfiguration> load();
  Future<void> saveConfiguration(WebcamConfiguration configuration);
}

class LocalManualWeighingStore
    implements ManualWeighingEvidenceStore, WebcamConfigurationStore {
  LocalManualWeighingStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _stationDirectory;
  static Future<Directory> _stationDirectory() async {
    final path = await PathProviderWindows().getApplicationSupportPath();
    if (path == null) {
      throw const FileSystemException('Diretório local indisponível.');
    }
    return Directory(path);
  }

  final Future<Directory> Function() _directory;
  Future<Directory> _root() async {
    final base = await _directory();
    return Directory('${base.path}/manual_weighing').create(recursive: true);
  }

  Future<File> _newFile(String relative) async {
    final root = await _root();
    final file = File('${root.path}/$relative');
    await file.parent.create(recursive: true);
    // Exclusive create prevents silently replacing prior evidence.
    await file.create(exclusive: true);
    return file;
  }

  @override
  Future<String> savePhoto(String attemptId, Uint8List stampedImage) async {
    final file = await _newFile('evidence/pesagem_manual_$attemptId.jpg');
    await file.writeAsBytes(stampedImage, flush: true);
    return file.path;
  }

  @override
  Future<void> save(ManualWeighingEvidence evidence) async {
    final suffix = evidence.confirmedAt == null ? 'attempt' : 'confirmed';
    final file = await _newFile('evidence/${evidence.id}_$suffix.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(evidence.toJson()),
      flush: true,
    );
  }

  @override
  Future<WebcamConfiguration> load() async {
    final root = await _root();
    final file = File('${root.path}/webcam.json');
    if (!await file.exists()) return const WebcamConfiguration();
    return WebcamConfiguration.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> saveConfiguration(WebcamConfiguration configuration) async {
    final root = await _root();
    final file = File('${root.path}/webcam.json');
    // Configuration may change; evidence files are always immutable.
    final pending = File('${file.path}.pending');
    await pending.writeAsString(
      jsonEncode(configuration.toJson()),
      flush: true,
    );
    await pending.rename(file.path);
  }
}
