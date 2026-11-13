import 'dart:convert';
import 'dart:io';

import 'package:path_provider_windows/path_provider_windows.dart';

class LibraEnvironmentSettings {
  String baseUrl = '', authKey = 'x-api-key', authValue = '';
  // Uma edição local, inclusive para limpar os campos, substitui o fallback.
  bool authOverride = false;

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'authKey': authKey,
    'authValue': authValue,
    'authOverride': authOverride,
  };
  LibraEnvironmentSettings();
  LibraEnvironmentSettings.fromJson(Map<String, dynamic> json) {
    baseUrl = json['baseUrl'] as String? ?? '';
    authKey = json['authKey'] as String? ?? 'x-api-key';
    authValue = json['authValue'] as String? ?? '';
    authOverride = json['authOverride'] as bool? ?? false;
  }
}

class LibraSettingsData {
  bool loadFailed = false;
  String selectedEnvironment = 'homologacao';
  final Map<String, LibraEnvironmentSettings> environments = {};
  LibraEnvironmentSettings forEnvironment(String name) =>
      environments.putIfAbsent(name, LibraEnvironmentSettings.new);
  Map<String, dynamic> toJson() => {
    'environment': selectedEnvironment,
    'environments': environments.map((k, v) => MapEntry(k, v.toJson())),
  };
  LibraSettingsData();
  LibraSettingsData.fromJson(Map<String, dynamic> json) {
    selectedEnvironment = json['environment'] as String? ?? 'homologacao';
    final rows = json['environments'] as Map<String, dynamic>? ?? {};
    for (final entry in rows.entries) {
      environments[entry.key] = LibraEnvironmentSettings.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
  }
}

abstract interface class LibraSettingsStore {
  Future<LibraSettingsData> load();
  Future<void> save(LibraSettingsData data);
}

class MemoryLibraSettingsStore implements LibraSettingsStore {
  Map<String, dynamic>? _json;
  @override
  Future<LibraSettingsData> load() async => _json == null
      ? LibraSettingsData()
      : LibraSettingsData.fromJson(
          jsonDecode(jsonEncode(_json)) as Map<String, dynamic>,
        );
  @override
  Future<void> save(LibraSettingsData data) async {
    _json = jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>;
  }
}

/// TEMPORÁRIO: texto simples no perfil local, somente para testes controlados.
/// Segue o mesmo diretório/padrão de escrita da configuração local de webcam.
class LocalLibraSettingsStore implements LibraSettingsStore {
  LocalLibraSettingsStore({Future<Directory> Function()? directory})
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
    return File('${root.path}/libra-settings.json');
  }

  @override
  Future<LibraSettingsData> load() async {
    final file = await _file();
    if (!await file.exists()) return LibraSettingsData();
    return LibraSettingsData.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> save(LibraSettingsData data) async {
    final file = await _file();
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(data.toJson()), flush: true);
    await pending.rename(file.path);
  }
}
