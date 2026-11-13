import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'app_shell.dart';
import '../features/pesagem/operation_lookup.dart';
import '../core/libra/libra_settings_store.dart';

class BalancaApp extends StatelessWidget {
  const BalancaApp({
    super.key,
    this.lookupService,
    this.libraStore,
    this.libraSettings,
  });
  final OperationLookupService? lookupService;
  final LibraSettingsStore? libraStore;
  final LibraSettingsData? libraSettings;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Balanca',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: AppShell(
      lookupService: lookupService,
      libraStore: libraStore,
      libraSettings: libraSettings,
    ),
  );
}
