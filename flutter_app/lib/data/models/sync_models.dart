/// Payload models for the sync upload and updates endpoints.

class SyncUploadPayload {
  const SyncUploadPayload({
    this.welds = const [],
    this.weldSteps = const [],
    this.weldErrors = const [],
    this.weldPhotos = const [],
    this.sensorLogBatches = const [],
  });

  final List<Map<String, dynamic>> welds;
  final List<Map<String, dynamic>> weldSteps;
  final List<Map<String, dynamic>> weldErrors;
  final List<Map<String, dynamic>> weldPhotos;
  final List<SensorLogBatchPayload> sensorLogBatches;

  Map<String, dynamic> toJson() => {
        'welds': welds,
        'weldSteps': weldSteps,
        'weldErrors': weldErrors,
        'weldPhotos': weldPhotos,
        'sensorLogBatches': sensorLogBatches.map((b) => b.toJson()).toList(),
      };
}

class SensorLogBatchPayload {
  const SensorLogBatchPayload({
    required this.weldId,
    required this.records,
  });

  final String weldId;
  final List<SensorLogPayload> records;

  Map<String, dynamic> toJson() => {
        'weldId': weldId,
        'records': records.map((r) => r.toJson()).toList(),
      };
}

class SensorLogPayload {
  const SensorLogPayload({
    required this.recordedAt,
    this.pressureBar,
    this.temperatureCelsius,
    this.phaseName,
    this.weldStepId,
  });

  final String recordedAt; // ISO 8601
  final double? pressureBar;
  final double? temperatureCelsius;
  final String? phaseName;
  final String? weldStepId;

  Map<String, dynamic> toJson() => {
        'recordedAt': recordedAt,
        if (pressureBar != null) 'pressureBar': pressureBar,
        if (temperatureCelsius != null) 'temperatureCelsius': temperatureCelsius,
        if (phaseName != null) 'phaseName': phaseName,
        if (weldStepId != null) 'weldStepId': weldStepId,
      };
}

class SyncUploadResult {
  const SyncUploadResult({
    required this.welds,
    required this.weldSteps,
    required this.weldErrors,
    required this.weldPhotos,
    required this.sensorLogs,
    required this.syncedAt,
  });

  final EntitySyncResult welds;
  final EntitySyncResult weldSteps;
  final EntitySyncResult weldErrors;
  final EntitySyncResult weldPhotos;
  final EntitySyncResult sensorLogs;
  final String syncedAt;

  bool get hasErrors =>
      welds.hasErrors ||
      weldSteps.hasErrors ||
      weldErrors.hasErrors ||
      sensorLogs.hasErrors;

  factory SyncUploadResult.fromJson(Map<String, dynamic> json) {
    final results = json['results'] as Map<String, dynamic>;
    return SyncUploadResult(
      welds: EntitySyncResult.fromJson(results['welds'] as Map<String, dynamic>),
      weldSteps: EntitySyncResult.fromJson(results['weldSteps'] as Map<String, dynamic>),
      weldErrors: EntitySyncResult.fromJson(results['weldErrors'] as Map<String, dynamic>),
      weldPhotos: EntitySyncResult.fromJson(
          results['weldPhotos'] as Map<String, dynamic>? ?? {'inserted': 0, 'errors': []}),
      sensorLogs: EntitySyncResult.fromJson(results['sensorLogs'] as Map<String, dynamic>),
      syncedAt: json['syncedAt'] as String,
    );
  }
}

class EntitySyncResult {
  const EntitySyncResult({required this.inserted, required this.errors});

  final int inserted;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;

  factory EntitySyncResult.fromJson(Map<String, dynamic> json) => EntitySyncResult(
        inserted: json['inserted'] as int? ?? 0,
        errors: (json['errors'] as List<dynamic>? ?? [])
            .cast<String>()
            .toList(),
      );
}

class SyncUpdatesResponse {
  const SyncUpdatesResponse({
    required this.projects,
    required this.projectUsers,
    required this.machines,
    required this.sensorCalibrations,
    required this.weldingStandards,
    required this.weldingParameters,
    required this.downloadedAt,
  });

  final List<Map<String, dynamic>> projects;
  final List<Map<String, dynamic>> projectUsers;
  final List<Map<String, dynamic>> machines;
  final List<Map<String, dynamic>> sensorCalibrations;
  final List<Map<String, dynamic>> weldingStandards;
  final List<Map<String, dynamic>> weldingParameters;
  final String downloadedAt;

  factory SyncUpdatesResponse.fromJson(Map<String, dynamic> json) =>
      SyncUpdatesResponse(
        projects: _castList(json['projects']),
        projectUsers: _castList(json['projectUsers']),
        machines: _castList(json['machines']),
        sensorCalibrations: _castList(json['sensorCalibrations']),
        weldingStandards: _castList(json['weldingStandards']),
        weldingParameters: _castList(json['weldingParameters']),
        downloadedAt: json['downloadedAt'] as String,
      );

  static List<Map<String, dynamic>> _castList(dynamic raw) =>
      (raw as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .toList();
}
