import 'dart:convert';
import 'dart:io';

import 'package:path_provider_windows/path_provider_windows.dart';

class IndicatorSettingsData {
  const IndicatorSettingsData({
    this.stations = const {},
    this.units = const {},
    this.models,
    this.loadFailed = false,
  });

  final Map<String, Map<String, dynamic>> stations;
  final Map<String, int> units;
  final List<Map<String, dynamic>>? models;
  final bool loadFailed;

  factory IndicatorSettingsData.fromJson(Map<String, dynamic> json) =>
      IndicatorSettingsData(
        stations: Map<String, Map<String, dynamic>>.from(
          json['stations'] as Map? ?? const {},
        ),
        models: (json['models'] as List?)?.cast<Map<String, dynamic>>(),
        units: Map<String, int>.from(json['units'] as Map? ?? const {}),
      );

  Map<String, Object?> toJson() => {
    'stations': stations,
    'models': models,
    'units': units,
  };
}

/// Mesmo diretório local e escrita por substituição da configuração Libra.
class LocalIndicatorSettingsStore {
  LocalIndicatorSettingsStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _applicationDirectory;

  final Future<Directory> Function() _directory;

  static Future<Directory> _applicationDirectory() async {
    final path = await PathProviderWindows().getApplicationSupportPath();
    if (path == null) {
      throw const FileSystemException('Diretório local indisponível.');
    }
    return Directory(path);
  }

  Future<File> _file() async {
    final root = await _directory();
    await root.create(recursive: true);
    return File('${root.path}/indicator-settings.json');
  }

  Future<IndicatorSettingsData> load() async {
    final file = await _file();
    if (!await file.exists()) return const IndicatorSettingsData();
    return IndicatorSettingsData.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<void> save(IndicatorSettingsData data) async {
    final file = await _file();
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(data.toJson()), flush: true);
    await pending.rename(file.path);
  }
}
