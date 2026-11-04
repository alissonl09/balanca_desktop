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
    this.mirrorHorizontally = false,
    this.region = const DisplayRegion(),
    this.minimumWeight = 0,
    this.maximumWeight = 100000,
    this.diagnostics = false,
  });
  final DisplayRegion region;
  final double minimumWeight, maximumWeight;
  final bool diagnostics;
  WebcamConfiguration copyWith({
    bool? enabled,
    String? cameraId,
    String? cameraName,
    bool? mirrorHorizontally,
    DisplayRegion? region,
    double? minimumWeight,
    double? maximumWeight,
    bool? diagnostics,
  }) => WebcamConfiguration(
    enabled: enabled ?? this.enabled,
    cameraId: cameraId ?? this.cameraId,
    cameraName: cameraName ?? this.cameraName,
    mirrorHorizontally: mirrorHorizontally ?? this.mirrorHorizontally,
    region: region ?? this.region,
    minimumWeight: minimumWeight ?? this.minimumWeight,
    maximumWeight: maximumWeight ?? this.maximumWeight,
    diagnostics: diagnostics ?? this.diagnostics,
  );
  final bool enabled;
  final bool mirrorHorizontally;
  final String? cameraId, cameraName;
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'cameraId': cameraId,
    'cameraName': cameraName,
    'mirrorHorizontally': mirrorHorizontally,
    'region': region.toJson(),
    'minimumWeight': minimumWeight,
    'maximumWeight': maximumWeight,
    'diagnostics': diagnostics,
  };
  factory WebcamConfiguration.fromJson(Map<String, dynamic> json) =>
      WebcamConfiguration(
        enabled: json['enabled'] == true,
        cameraId: json['cameraId'] as String?,
        cameraName: json['cameraName'] as String?,
        mirrorHorizontally: json['mirrorHorizontally'] == true,
        region: json['region'] is Map
            ? DisplayRegion.fromJson(Map<String, dynamic>.from(json['region']))
            : const DisplayRegion(),
        minimumWeight: (json['minimumWeight'] as num?)?.toDouble() ?? 0,
        maximumWeight: (json['maximumWeight'] as num?)?.toDouble() ?? 100000,
        diagnostics: json['diagnostics'] == true,
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
  const CapturedPhoto(
    this.bytes,
    this.capturedAt, {
    this.mirrorHorizontally = false,
  });
  final Uint8List bytes;
  final DateTime capturedAt;

  /// Explicit station correction for a driver that mirrors captured pixels.
  /// Applied after EXIF, independently of the plugin's preview-only mirror.
  final bool mirrorHorizontally;
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
  bool get valid =>
      [left, top, width, height].every((v) => v.isFinite) &&
      left >= 0 &&
      top >= 0 &&
      width >= .02 &&
      height >= .02 &&
      left + width <= 1.000001 &&
      top + height <= 1.000001;
  factory DisplayRegion.fromJson(Map<String, dynamic> json) {
    final region = DisplayRegion(
      left: (json['left'] as num?)?.toDouble() ?? .1,
      top: (json['top'] as num?)?.toDouble() ?? .25,
      width: (json['width'] as num?)?.toDouble() ?? .8,
      height: (json['height'] as num?)?.toDouble() ?? .5,
    );
    return region.valid ? region : const DisplayRegion();
  }
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
    this.attempts = const [],
    this.strategy = '',
    this.engineMessage,
  });
  final List<OcrAttempt> attempts;
  final String strategy;
  final String? engineMessage;
  final String rawText;
  final double? weight;
  final double confidence;
  final String? error;
  static const threshold = .90;
  bool get success =>
      error == null &&
      weight != null &&
      weight!.isFinite &&
      confidence.isFinite &&
      confidence >= threshold &&
      confidence <= 1;
}

class OcrAttempt {
  const OcrAttempt(this.strategy, this.image, this.result);
  final String strategy;
  final Uint8List image;
  final WeightOcrResult result;
  Map<String, Object?> toJson() => {
    'strategy': strategy,
    'rawText': result.rawText,
    'confidence': result.confidence,
    'parsedWeight': result.weight,
    'failureReason': result.error,
    'engineMessage': result.engineMessage,
  };
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
    this.stableReadings = 0,
  });
  final int stableReadings;
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
    'ocrStrategy': ocr.strategy,
    'ocrAttempts': ocr.attempts.map((a) => a.toJson()).toList(),
    'finalWeight': finalWeight,
    'weightSource': source.code,
    'failureReason': failureReason,
    'photoFailureReason': photoFailureReason,
    'authorizer': authorizer,
    'justification': justification,
    'region': region.toJson(),
    'ocrStableReadings': stableReadings,
    'ocrRequiredReadings': 3,
    'ocrEngineMessage': ocr.engineMessage,
  };
}

String localTimestamp(DateTime value) {
  final t = value.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(t.day)}/${pad(t.month)}/${t.year} ${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}';
}
