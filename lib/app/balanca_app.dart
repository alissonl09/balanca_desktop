import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'app_shell.dart';

class BalancaApp extends StatelessWidget {
  const BalancaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Balanca',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: const AppShell(),
  );
}
