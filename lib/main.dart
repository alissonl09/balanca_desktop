import 'package:flutter/material.dart';

import 'app/balanca_app.dart';
import 'features/pesagem/manual_capture/manual_capture_services.dart';
import 'core/libra/libra_settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ManualCaptureServices.current.loadConfiguration();
  final libraStore = LocalLibraSettingsStore();
  LibraSettingsData libraSettings;
  try {
    libraSettings = await libraStore.load();
  } catch (_) {
    // Não imprime arquivo, conteúdo ou exceção que possa conter credenciais.
    libraSettings = LibraSettingsData()..loadFailed = true;
  }
  runApp(BalancaApp(libraStore: libraStore, libraSettings: libraSettings));
}
