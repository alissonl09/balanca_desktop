import 'dart:typed_data';

class WeighingCamera {
  const WeighingCamera(this.id, this.name);
  final String id, name;
}

class WebcamConfiguration {
  const WebcamConfiguration({
    this.enabled = true,
    this.ocrEnabled = false,
    this.cameraId,
    this.cameraName,
    this.mirrorHorizontally = false,
    this.region = const DisplayRegion(),
    this.minimumWeight = 0,
    this.maximumWeight = 100000,
    this.diagnostics = false,
    this.requiredReadings = 3,
    this.expectedDecimalPlaces,
    this.cameraRegions = const {},
  });
  final DisplayRegion region;
  final double minimumWeight, maximumWeight;
  final bool diagnostics;
  final int requiredReadings;

  /// Validation only: never inserts a separator or changes the numeric scale.
  final int? expectedDecimalPlaces;
  final Map<String, DisplayRegion> cameraRegions;
  WebcamConfiguration copyWith({
    bool? enabled,
    bool? ocrEnabled,
    String? cameraId,
    String? cameraName,
    bool? mirrorHorizontally,
    DisplayRegion? region,
    double? minimumWeight,
    double? maximumWeight,
    bool? diagnostics,
    int? requiredReadings,
    int? expectedDecimalPlaces,
    bool automaticDecimals = false,
  }) => WebcamConfiguration(
    enabled: enabled ?? this.enabled,
    ocrEnabled: ocrEnabled ?? this.ocrEnabled,
    cameraId: cameraId ?? this.cameraId,
    cameraName: cameraName ?? this.cameraName,
    mirrorHorizontally: mirrorHorizontally ?? this.mirrorHorizontally,
    region:
        region ??
        (cameraId != null && cameraId != this.cameraId
            ? cameraRegions[cameraId] ?? const DisplayRegion()
            : this.region),
    minimumWeight: minimumWeight ?? this.minimumWeight,
    maximumWeight: maximumWeight ?? this.maximumWeight,
    diagnostics: diagnostics ?? this.diagnostics,
    requiredReadings: requiredReadings ?? this.requiredReadings,
    expectedDecimalPlaces: automaticDecimals
        ? null
        : expectedDecimalPlaces ?? this.expectedDecimalPlaces,
    cameraRegions: {
      ...cameraRegions,
      if (this.cameraId != null) this.cameraId!: this.region,
      if (region != null && (cameraId ?? this.cameraId) != null)
        (cameraId ?? this.cameraId)!: region,
    },
  );
  final bool enabled;
  final bool ocrEnabled;
  final bool mirrorHorizontally;
  final String? cameraId, cameraName;
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'ocrEnabled': ocrEnabled,
    'cameraId': cameraId,
    'cameraName': cameraName,
    'mirrorHorizontally': mirrorHorizontally,
    'region': region.toJson(),
    'minimumWeight': minimumWeight,
    'maximumWeight': maximumWeight,
    'diagnostics': diagnostics,
    'requiredReadings': requiredReadings,
    'expectedDecimalPlaces': expectedDecimalPlaces,
    'cameraRegions': cameraRegions.map((id, r) => MapEntry(id, r.toJson())),
  };
  factory WebcamConfiguration.fromJson(Map<String, dynamic> json) =>
      WebcamConfiguration(
        enabled: json['enabled'] == true,
        ocrEnabled: json['ocrEnabled'] == true,
        cameraId: json['cameraId'] as String?,
        cameraName: json['cameraName'] as String?,
        mirrorHorizontally: json['mirrorHorizontally'] == true,
        region: json['region'] is Map
            ? DisplayRegion.fromJson(Map<String, dynamic>.from(json['region']))
            : const DisplayRegion(),
        minimumWeight: (json['minimumWeight'] as num?)?.toDouble() ?? 0,
        maximumWeight: (json['maximumWeight'] as num?)?.toDouble() ?? 100000,
        diagnostics: json['diagnostics'] == true,
        requiredReadings: (json['requiredReadings'] as int?)?.clamp(2, 5) ?? 3,
        expectedDecimalPlaces: [0, 1, 2].contains(json['expectedDecimalPlaces'])
            ? json['expectedDecimalPlaces'] as int
            : null,
        cameraRegions: {
          if (json['cameraRegions'] is Map)
            for (final entry in (json['cameraRegions'] as Map).entries)
              if (entry.value is Map)
                entry.key.toString(): DisplayRegion.fromJson(
                  Map<String, dynamic>.from(entry.value),
                ),
        },
      );
}

enum CaptureStage {
  cameraInitializing,
  cameraReady,
  capturing,
  ocrProcessing,
  ocrSuccess,
  manualFallback,
  manualEntry,
  saving,
  confirmed,
}

enum WeightSource {
  cameraOcr('CAMERA_OCR'),
  manualFallback('MANUAL_FALLBACK'),
  manualPhoto('MANUAL_WITH_PHOTO');

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
    this.deskewDegrees = 0,
  });
  final double left, top, width, height, deskewDegrees;
  bool get valid =>
      [left, top, width, height].every((v) => v.isFinite) &&
      left >= 0 &&
      top >= 0 &&
      width >= .02 &&
      height >= .02 &&
      deskewDegrees.isFinite &&
      deskewDegrees.abs() <= 6 &&
      left + width <= 1.000001 &&
      top + height <= 1.000001;
  factory DisplayRegion.fromJson(Map<String, dynamic> json) {
    final region = DisplayRegion(
      left: (json['left'] as num?)?.toDouble() ?? .1,
      top: (json['top'] as num?)?.toDouble() ?? .25,
      width: (json['width'] as num?)?.toDouble() ?? .8,
      height: (json['height'] as num?)?.toDouble() ?? .5,
      deskewDegrees: ((json['deskewDegrees'] as num?)?.toDouble() ?? 0),
    );
    return region.valid ? region : const DisplayRegion();
  }
  Map<String, double> toJson() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
    'deskewDegrees': deskewDegrees,
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
    this.model = '',
    this.psm = 7,
    this.elapsedMs = 0,
    this.consensusReadings = 0,
    this.requiredReadings = 3,
    this.normalizedText = '',
    this.decimalDetected = false,
    this.decimalPosition,
    this.characterPositions = const [],
    this.roiQuality = 1,
    this.structuralConfidence = 1,
    this.decimalConfidence = 1,
    this.temporalConfidence = 1,
    this.diagnostics = const {},
  });
  final String normalizedText;
  final bool decimalDetected;
  final int? decimalPosition;
  final List<Map<String, num>> characterPositions;
  final double roiQuality,
      structuralConfidence,
      decimalConfidence,
      temporalConfidence;
  final Map<String, Object?> diagnostics;
  String get recognitionKey => normalizedText.isNotEmpty
      ? normalizedText
      : rawText.isNotEmpty
      ? rawText
            .trim()
            .replaceAll(RegExp(r'\s*kg$', caseSensitive: false), '')
            .replaceAll(',', '.')
      : weight == null
      ? ''
      : weight == weight!.truncateToDouble()
      ? weight!.toStringAsFixed(0)
      : weight.toString();
  String get digitSequence => recognitionKey.replaceAll(RegExp(r'[^0-9]'), '');
  String get preprocessingPipeline => strategy;
  int get consensusCount => consensusReadings;
  String? get failureReason => error;
  double get candidateConfidence => [
    confidence,
    roiQuality,
    structuralConfidence,
    decimalConfidence,
    temporalConfidence,
  ].reduce((a, b) => a < b ? a : b);
  final List<OcrAttempt> attempts;
  final String strategy;
  final String? engineMessage;
  final String model;
  final int psm, elapsedMs, consensusReadings, requiredReadings;
  double get ocrConfidence => confidence;
  bool get consensus => consensusReadings >= requiredReadings;
  double get finalConfidence => success && consensus ? candidateConfidence : 0;
  WeightOcrResult copyWith({
    String? model,
    int? psm,
    int? elapsedMs,
    int? consensusReadings,
    int? requiredReadings,
    String? failure,
    List<OcrAttempt>? attempts,
    String? strategy,
    String? normalizedText,
    double? weight,
    double? confidence,
    bool? decimalDetected,
    int? decimalPosition,
    List<Map<String, num>>? characterPositions,
    double? roiQuality,
    double? structuralConfidence,
    double? decimalConfidence,
    double? temporalConfidence,
    Map<String, Object?>? diagnostics,
  }) => WeightOcrResult(
    rawText: rawText,
    weight: weight ?? this.weight,
    confidence: confidence ?? this.confidence,
    error: failure ?? error,
    engineMessage: engineMessage,
    model: model ?? this.model,
    psm: psm ?? this.psm,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    consensusReadings: consensusReadings ?? this.consensusReadings,
    requiredReadings: requiredReadings ?? this.requiredReadings,
    attempts: attempts ?? this.attempts,
    strategy: strategy ?? this.strategy,
    normalizedText: normalizedText ?? this.normalizedText,
    decimalDetected: decimalDetected ?? this.decimalDetected,
    decimalPosition: decimalPosition ?? this.decimalPosition,
    characterPositions: characterPositions ?? this.characterPositions,
    roiQuality: roiQuality ?? this.roiQuality,
    structuralConfidence: structuralConfidence ?? this.structuralConfidence,
    decimalConfidence: decimalConfidence ?? this.decimalConfidence,
    temporalConfidence: temporalConfidence ?? this.temporalConfidence,
    diagnostics: diagnostics ?? this.diagnostics,
  );
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
      candidateConfidence.isFinite &&
      candidateConfidence >= threshold &&
      confidence <= 1;
}

/// Shared result contract; existing callers retain WeightOcrResult compatibility.
typedef WeightRecognitionResult = WeightOcrResult;

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
    'model': result.model,
    'psm': result.psm,
    'elapsedMs': result.elapsedMs,
    'normalizedText': result.normalizedText,
    'decimalDetected': result.decimalDetected,
    'decimalPosition': result.decimalPosition,
    'characterPositions': result.characterPositions,
    'candidateConfidence': result.candidateConfidence,
    'diagnostics': result.diagnostics,
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
    this.ocrEnabled = true,
  });
  final int stableReadings;
  final bool ocrEnabled;
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
    'ocrRequiredReadings': ocr.requiredReadings,
    'ocrEngineMessage': ocr.engineMessage,
    'ocrModel': ocr.model,
    'ocrPsm': ocr.psm,
    'ocrConfidence': ocr.ocrConfidence,
    'ocrFinalConfidence': ocr.finalConfidence,
    'ocrConsensus': ocr.consensus,
    'ocrEnabled': ocrEnabled,
    'ocrNormalizedText': ocr.normalizedText,
    'ocrDecimalDetected': ocr.decimalDetected,
    'ocrDecimalPosition': ocr.decimalPosition,
    'ocrCharacterPositions': ocr.characterPositions,
    'ocrDiagnostics': ocr.diagnostics,
  };
}

String localTimestamp(DateTime value) {
  final t = value.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(t.day)}/${pad(t.month)}/${t.year} ${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}';
}
