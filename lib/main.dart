import 'package:flutter/material.dart';

import 'app/balanca_app.dart';
import 'features/pesagem/manual_capture/manual_capture_services.dart';
import 'core/libra/libra_settings_store.dart';
import 'core/database/database_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  late DatabaseManager database;
  try {
    database = await DatabaseManager.forWindows();
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Não foi possível localizar uma pasta local segura para o banco.',
                ),
                TextButton(
                  onPressed: main,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return;
  }
  try {
    await database.open();
  } catch (_) {
    /* Diagnóstico na manutenção, sem fallback volátil. */
  }
  await ManualCaptureServices.current.loadConfiguration();
  final libraStore = LocalLibraSettingsStore();
  LibraSettingsData libraSettings;
  try {
    libraSettings = await libraStore.load();
  } catch (_) {
    // Não imprime arquivo, conteúdo ou exceção que possa conter credenciais.
    libraSettings = LibraSettingsData()..loadFailed = true;
  }
  runApp(
    BalancaApp(
      libraStore: libraStore,
      libraSettings: libraSettings,
      database: database,
    ),
  );
}
