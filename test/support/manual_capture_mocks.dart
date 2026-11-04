import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/camera_service.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/capture_models.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/evidence_store.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/image_processor.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/manual_capture_services.dart';
import 'package:balanca_desktop/features/pesagem/manual_capture/weight_ocr_service.dart';

class MockWeighingCameraService implements WeighingCameraService {
  List<WeighingCamera> devices = [
    const WeighingCamera('usb-device-id', 'USB Camera'),
  ];
  int starts = 0, stops = 0, captures = 0;
  String? selected;
  bool unavailable = false, captureFails = false;
  CapturedPhoto photo = CapturedPhoto(
    Uint8List.fromList([1, 2, 3]),
    DateTime(2026, 11, 4, 12, 45, 31),
  );
  @override
  Future<List<WeighingCamera>> listCameras() async => devices;
  @override
  Future<void> start(String cameraId) async {
    starts++;
    selected = cameraId;
    if (unavailable) {
      throw const CaptureFailure('CAMERA_INDISPONIVEL', 'Câmera indisponível');
    }
  }

  @override
  Widget preview() => const ColoredBox(color: Color(0xff555555));
  @override
  Future<CapturedPhoto> capture() async {
    captures++;
    if (captureFails) {
      throw const CaptureFailure('ERRO_CAPTURA', 'Captura falhou');
    }
    return photo;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

class MockWeightOcrService implements WeightOcrService {
  WeightOcrResult result = const WeightOcrResult(
    rawText: '12190 kg',
    weight: 12190,
    confidence: .99,
  );
  Future<WeightOcrResult> Function()? pending;
  int calls = 0;
  final List<WeightOcrResult> sequence = [];
  Uint8List? lastImage;
  @override
  Future<WeightOcrResult> recognize(Uint8List image) async {
    calls++;
    lastImage = image;
    return sequence.isNotEmpty
        ? sequence.removeAt(0)
        : pending == null
        ? result
        : await pending!();
  }
}

class MockEvidenceStore
    implements ManualWeighingEvidenceStore, WebcamConfigurationStore {
  final records = <ManualWeighingEvidence>[];
  final photos = <String, Uint8List>{};
  WebcamConfiguration config = const WebcamConfiguration();
  bool failSave = false;
  @override
  Future<String> savePhoto(String attemptId, Uint8List stampedImage) async {
    if (failSave) throw StateError('disk full');
    final path = 'mock/$attemptId.jpg';
    photos[path] = stampedImage;
    return path;
  }

  @override
  Future<void> save(ManualWeighingEvidence evidence) async {
    if (failSave) throw StateError('disk full');
    records.add(evidence);
  }

  @override
  Future<WebcamConfiguration> load() async => config;
  @override
  Future<void> saveConfiguration(WebcamConfiguration configuration) async {
    config = configuration;
  }
}

class MockCaptureImageProcessor implements CaptureImageProcessor {
  @override
  Future<ProcessedCapture> process(
    CapturedPhoto photo,
    DisplayRegion region,
  ) async => ProcessedCapture(photo.bytes, photo.bytes);
}

ManualCaptureServices mockCaptureServices({
  WeighingCameraService Function()? cameraFactory,
  MockWeighingCameraService? camera,
  MockWeightOcrService? ocr,
  MockEvidenceStore? store,
  bool configured = false,
}) {
  final memory = store ?? MockEvidenceStore();
  final result = ManualCaptureServices(
    cameraFactory: cameraFactory ?? () => camera ?? MockWeighingCameraService(),
    ocr: ocr ?? MockWeightOcrService(),
    evidenceStore: memory,
    configurationStore: memory,
    processor: MockCaptureImageProcessor(),
  );
  if (configured) {
    result.configuration = const WebcamConfiguration(
      cameraId: 'usb-device-id',
      cameraName: 'USB Camera',
    );
  }
  return result;
}
