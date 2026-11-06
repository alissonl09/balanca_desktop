import 'dart:async';

import 'camera_service.dart';
import 'capture_models.dart';
import 'image_processor.dart';
import 'weight_ocr_service.dart';
import 'weight_recognition_validation.dart';

/// Samples original camera photographs, never the rendered preview. Serial
/// polling provides backpressure: no queued OCR or overlapping camera calls.
class LiveWeightReader {
  LiveWeightReader({
    required this.camera,
    required this.processor,
    required this.ocr,
    required this.configuration,
    required this.onChanged,
    this.interval = const Duration(milliseconds: 250),
    this.freshness = const Duration(seconds: 2),
  }) : consensus = WeightTemporalConsensus(
         requiredReadings: configuration.requiredReadings,
       );
  final WeighingCameraService camera;
  final CaptureImageProcessor processor;
  final WeightOcrService ocr;
  final WebcamConfiguration configuration;
  final void Function() onChanged;
  final Duration interval, freshness;
  WeightTemporalConsensus consensus;
  WeightOcrResult result = const WeightOcrResult();
  CapturedPhoto? photo;
  DateTime? _acceptedAt;
  DateTime? _lastObservedAt;
  Timer? _next, _expiry;
  Future<void>? _pending;
  bool _running = false;
  int _generation = 0;
  bool get ready =>
      _running &&
      photo != null &&
      result.success &&
      result.consensus &&
      _acceptedAt != null &&
      DateTime.now().difference(_acceptedAt!) < freshness;
  void start() {
    if (_running) return;
    _running = true;
    _generation++;
    _pending = _read(_generation);
  }

  Future<void> _read(int generation) async {
    bool current() => _running && generation == _generation;
    try {
      final frame = await camera.capture();
      if (!current()) return;
      final capture = processor is OcrFrameImageProcessor
          ? await (processor as OcrFrameImageProcessor).processOcrFrame(
              frame,
              configuration.region,
            )
          : await processor.process(frame, configuration.region);
      if (!current()) return;
      final reading = await ocr.recognize(capture.ocrInput);
      if (!current()) return;
      final observedAt = DateTime.now();
      if (_lastObservedAt != null &&
          observedAt.difference(_lastObservedAt!) > freshness) {
        consensus = WeightTemporalConsensus(
          requiredReadings: configuration.requiredReadings,
        );
      }
      _lastObservedAt = observedAt;
      final validated = WeightRecognitionRules(
        minimum: configuration.minimumWeight,
        maximum: configuration.maximumWeight,
        expectedDecimalPlaces: configuration.expectedDecimalPlaces,
      ).validate(reading);
      result = consensus
          .observe(validated)
          .copyWith(
            diagnostics: {...reading.diagnostics, ...capture.dimensions},
          );
      photo = result.success && result.consensus ? frame : null;
      _acceptedAt = photo == null ? null : DateTime.now();
      _expiry?.cancel();
      if (photo != null) {
        _expiry = Timer(freshness, () {
          if (!current()) return;
          photo = null;
          _acceptedAt = null;
          result = const WeightOcrResult(error: 'OCR_LEITURA_EXPIRADA');
          consensus = WeightTemporalConsensus(
            requiredReadings: configuration.requiredReadings,
          );
          onChanged();
        });
      }
      onChanged();
    } catch (_) {
      if (current()) {
        photo = null;
        _acceptedAt = null;
        result = consensus.observe(
          const WeightOcrResult(error: 'OCR_CAPTURA_CONTINUA_FALHOU'),
        );
        onChanged();
      }
    } finally {
      if (current()) {
        _next = Timer(interval, () => _pending = _read(generation));
      }
    }
  }

  Future<void> stop() async {
    _running = false;
    _generation++;
    _next?.cancel();
    _expiry?.cancel();
    await _pending;
  }
}
