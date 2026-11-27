import 'dart:io';

import 'package:flutter/material.dart';

import 'app/balanca_app.dart';
import 'features/pesagem/manual_capture/manual_capture_services.dart';
import 'core/libra/libra_settings_store.dart';
import 'core/database/database_manager.dart';
import 'core/indicators/indicator_settings_store.dart';
import 'features/ticket/print_settings.dart';
import 'features/ticket/windows_printer_adapter.dart';

Future<void> main([List<String> arguments = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.firstOrNull == windowsPrintWorkerArgument) {
    if (arguments.length != 2) exit(1);
    try {
      await runWindowsPrintWorker(Directory(arguments[1]));
      exit(0);
    } catch (_) {
      exit(1);
    }
  }
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
  final indicatorStore = LocalIndicatorSettingsStore();
  IndicatorSettingsData indicatorSettings;
  try {
    indicatorSettings = await indicatorStore.load();
  } catch (_) {
    indicatorSettings = const IndicatorSettingsData(loadFailed: true);
  }
  final printStore = LocalPrintSettingsStore();
  Map<String, Map<String, dynamic>> printStations = {};
  var printSettingsLoadFailed = false;
  try {
    printStations = await printStore.load();
  } catch (_) {
    printSettingsLoadFailed = true;
  }
  runApp(
    BalancaApp(
      libraStore: libraStore,
      libraSettings: libraSettings,
      database: database,
      indicatorStore: indicatorStore,
      indicatorSettings: indicatorSettings,
      printStore: printStore,
      printStations: printStations,
      printSettingsLoadFailed: printSettingsLoadFailed,
    ),
  );
}
