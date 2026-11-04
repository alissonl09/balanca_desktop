import 'dart:async';

import 'package:balanca_desktop/features/pesagem/manual_capture/manual_capture_services.dart';

import 'support/manual_capture_mocks.dart';

/// Widget regression tests never open hardware or write operational evidence.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ManualCaptureServices.current = mockCaptureServices();
  await testMain();
}
