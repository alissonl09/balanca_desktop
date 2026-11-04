import 'dart:typed_data';

class WeighingCamera {
  const WeighingCamera(this.id, this.name);
  final String id, name;
}

class WebcamConfiguration {
  const WebcamConfiguration({
    this.enabled = true,
    this.cameraId,
    this.cameraName,
  });
  final bool enabled;
  final String? cameraId, cameraName;
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'cameraId': cameraId,
    'cameraName': cameraName,
  };
  factory WebcamConfiguration.fromJson(Map<String, dynamic> json) =>
      WebcamConfiguration(
        enabled: json['enabled'] == true,
        cameraId: json['cameraId'] as String?,
        cameraName: json['cameraName'] as String?,
      );
}

enum CaptureStage {
  cameraInitializing,
  cameraReady,
  capturing,
  ocrProcessing,
  ocrSuccess,
  manualFallback,
  saving,
  confirmed,
}

enum WeightSource {
  cameraOcr('CAMERA_OCR'),
  manualFallback('MANUAL_FALLBACK');

  const WeightSource(this.code);
  final String code;
}

class CaptureFailure implements Exception {
  const CaptureFailure(this.code, this.message);
  final String code, message;
}

class CapturedPhoto {
  const CapturedPhoto(this.bytes, this.capturedAt);
  final Uint8List bytes;
  final DateTime capturedAt;
}

/// Normalized region, shared by the preview and image processor.
class DisplayRegion {
  const DisplayRegion({
    this.left = .1,
    this.top = .25,
    this.width = .8,
    this.height = .5,
  });
  final double left, top, width, height;
  Map<String, double> toJson() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };
}

class WeightOcrResult {
  const WeightOcrResult({
    this.rawText = '',
    this.weight,
    this.confidence = 0,
    this.error,
  });
  final String rawText;
  final double? weight;
  final double confidence;
  final String? error;
  static const threshold = .90;
  bool get success =>
      error == null &&
      weight != null &&
      weight!.isFinite &&
      weight! >= 0 &&
      confidence.isFinite &&
      confidence >= threshold &&
      confidence <= 1;
}

class ManualWeighingEvidence {
  const ManualWeighingEvidence({
    required this.id,
    required this.dateTime,
    required this.authorizer,
    required this.justification,
    required this.source,
    required this.finalWeight,
    this.cameraId,
    this.cameraName,
    this.imagePath,
    this.ocr = const WeightOcrResult(),
    this.failureReason,
    this.photoFailureReason,
    this.confirmedAt,
    this.plate = '',
    this.region = const DisplayRegion(),
  });
  final String id, authorizer, justification, plate;
  final DateTime dateTime;
  final DateTime? confirmedAt;
  final String? cameraId,
      cameraName,
      imagePath,
      failureReason,
      photoFailureReason;
  final double? finalWeight;
  final WeightSource source;
  final WeightOcrResult ocr;
  final DisplayRegion region;
  Map<String, Object?> toJson() => {
    'id': id,
    'dateTime': dateTime.toIso8601String(),
    'confirmedAt': confirmedAt?.toIso8601String(),
    'status': confirmedAt == null ? 'CAPTURE_ATTEMPT' : 'WEIGHT_REVIEWED',
    'plate': plate,
    'cameraId': cameraId,
    'cameraName': cameraName,
    'imagePath': imagePath,
    'ocrRawText': ocr.rawText,
    'ocrWeight': ocr.weight,
    'confidence': ocr.confidence,
    'ocrError': ocr.error,
    'finalWeight': finalWeight,
    'weightSource': source.code,
    'failureReason': failureReason,
    'photoFailureReason': photoFailureReason,
    'authorizer': authorizer,
    'justification': justification,
    'region': region.toJson(),
  };
}

String localTimestamp(DateTime value) {
  final t = value.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(t.day)}/${pad(t.month)}/${t.year} ${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}';
}
