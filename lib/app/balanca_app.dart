import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'app_shell.dart';
import '../features/pesagem/operation_lookup.dart';
import '../core/libra/libra_settings_store.dart';
import '../core/database/database_manager.dart';

class BalancaApp extends StatelessWidget {
  const BalancaApp({
    super.key,
    this.lookupService,
    this.libraStore,
    this.libraSettings,
    this.database,
  });
  final OperationLookupService? lookupService;
  final LibraSettingsStore? libraStore;
  final LibraSettingsData? libraSettings;
  final DatabaseManager? database;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Balanca',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: AppShell(
      lookupService: lookupService,
      libraStore: libraStore,
      libraSettings: libraSettings,
      database: database,
    ),
  );
}
