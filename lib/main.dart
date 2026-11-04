import 'package:flutter/material.dart';

import 'app/balanca_app.dart';
import 'features/pesagem/manual_capture/manual_capture_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ManualCaptureServices.current.loadConfiguration();
  runApp(const BalancaApp());
}
