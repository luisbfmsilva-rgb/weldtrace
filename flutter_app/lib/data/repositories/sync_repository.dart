import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/result.dart';
import '../local/database/app_database.dart';
import '../local/dao/welds_dao.dart';
import '../local/dao/projects_dao.dart';
import '../local/dao/machines_dao.dart';
import '../local/dao/sensor_logs_dao.dart';
import '../local/tables/projects_table.dart';
import '../local/tables/machines_table.dart';
import '../local/tables/welding_standards_table.dart';
import '../local/tables/welding_parameters_table.dart';
import '../models/sync_models.dart';
import '../remote/sync_remote_data_source.dart';

/// Coordinates offline data upload and cloud-to-local update download.
class SyncRepository {
  const SyncRepository({
    required this.remoteDataSource,
    required this.db,
  });

  final SyncRemoteDataSource remoteDataSource;
  final AppDatabase db;

  // ── Upload (local → cloud) ────────────────────────────────────────────────

  /// Uploads all pending local records to the cloud.
  /// Returns the upload result or a [SyncException].
  Future<Result<SyncUploadResult>> syncUpload() async {
    try {
      // 1. Gather pending records from each DAO
      final pendingWelds = await db.weldsDao.getPendingSync();
      final pendingSteps = await db.weldsDao.getPendingSteps();

      // 2. Build sensor log batches (max 200 records per weld per batch)
      final sensorBatches = <SensorLogBatchPayload>[];
      for (final weld in pendingWelds) {
        final logs = await db.sensorLogsDao.getPendingBatch(weld.id);
        if (logs.isNotEmpty) {
          sensorBatches.add(SensorLogBatchPayload(
            weldId: weld.id,
            records: logs.map((l) => SensorLogPayload(
                  recordedAt: l.recordedAt.toUtc().toIso8601String(),
                  pressureBar: l.pressureBar,
                  temperatureCelsius: l.temperatureCelsius,
                  phaseName: l.phaseName,
                  weldStepId: l.weldStepId,
                )).toList(),
          ));
        }
      }

      // 3. Build weld payloads
      final weldPayloads = pendingWelds.map((w) => {
            'id': w.id,
            'projectId': w.projectId,
            'machineId': w.machineId,
            'weldType': w.weldType,
            'status': w.status,
            'pipeMaterial': w.pipeMaterial,
            'pipeDiameter': w.pipeDiameter,
            if (w.pipeSdr != null) 'pipeSdr': w.pipeSdr,
            if (w.pipeWallThickness != null) 'pipeWallThickness': w.pipeWallThickness,
            if (w.ambientTemperature != null) 'ambientTemperature': w.ambientTemperature,
            if (w.gpsLat != null) 'gpsLat': w.gpsLat,
            if (w.gpsLng != null) 'gpsLng': w.gpsLng,
            if (w.standardUsed != null) 'standardUsed': w.standardUsed,
            if (w.standardId != null) 'standardId': w.standardId,
            'isCancelled': w.isCancelled,
            if (w.cancelReason != null) 'cancelReason': w.cancelReason,
            if (w.cancelTimestamp != null)
              'cancelTimestamp': w.cancelTimestamp!.toUtc().toIso8601String(),
            if (w.notes != null) 'notes': w.notes,
            'startedAt': w.startedAt.toUtc().toIso8601String(),
            if (w.completedAt != null)
              'completedAt': w.completedAt!.toUtc().toIso8601String(),
          }).toList();

      // 4. Build weld step payloads
      final stepPayloads = pendingSteps.map((s) => {
            'id': s.id,
            'weldId': s.weldId,
            'phaseName': s.phaseName,
            'phaseOrder': s.phaseOrder,
            if (s.startedAt != null) 'startedAt': s.startedAt!.toUtc().toIso8601String(),
            if (s.completedAt != null)
              'completedAt': s.completedAt!.toUtc().toIso8601String(),
            if (s.nominalValue != null) 'nominalValue': s.nominalValue,
            if (s.actualValue != null) 'actualValue': s.actualValue,
            if (s.unit != null) 'unit': s.unit,
            if (s.validationPassed != null) 'validationPassed': s.validationPassed,
            if (s.notes != null) 'notes': s.notes,
          }).toList();

      if (weldPayloads.isEmpty && stepPayloads.isEmpty && sensorBatches.isEmpty) {
        return Success(SyncUploadResult(
          welds: const EntitySyncResult(inserted: 0, errors: []),
          weldSteps: const EntitySyncResult(inserted: 0, errors: []),
          weldErrors: const EntitySyncResult(inserted: 0, errors: []),
          weldPhotos: const EntitySyncResult(inserted: 0, errors: []),
          sensorLogs: const EntitySyncResult(inserted: 0, errors: []),
          syncedAt: DateTime.now().toUtc().toIso8601String(),
        ));
      }

      // 5. Upload
      final payload = SyncUploadPayload(
        welds: weldPayloads,
        weldSteps: stepPayloads,
        sensorLogBatches: sensorBatches,
      );

      final result = await remoteDataSource.upload(payload);

      return result.when(
        success: (uploadResult) async {
          // 6. Mark as synced only if upload succeeded
          if (!uploadResult.welds.hasErrors) {
            for (final w in pendingWelds) {
              await db.weldsDao.markSynced(w.id);
            }
          }
          if (!uploadResult.weldSteps.hasErrors) {
            for (final s in pendingSteps) {
              await db.weldsDao.markStepSynced(s.id);
            }
          }
          if (!uploadResult.sensorLogs.hasErrors) {
            for (final batch in sensorBatches) {
              final logs = await db.sensorLogsDao.getPendingBatch(batch.weldId);
              await db.sensorLogsDao.markSynced(logs.map((l) => l.id).toList());
            }
          }
          return Success(uploadResult);
        },
        failure: (e) => Failure(SyncException('Upload failed: ${e.message}', e)),
      );
    } catch (e) {
      return Failure(SyncException('Unexpected sync error', e));
    }
  }

  // ── Download (cloud → local) ──────────────────────────────────────────────

  /// Downloads changes from the cloud since [since] and writes them to local DB.
  Future<Result<SyncUpdatesResponse>> syncDownload({
    required DateTime since,
    String? projectId,
  }) async {
    try {
      final result = await remoteDataSource.getUpdates(
        since: since,
        projectId: projectId,
      );

      return result.when(
        success: (updates) async {
          // Write projects
          final projectRows = updates.projects.map((p) => ProjectsTableCompanion(
                id: Value(p['id'] as String),
                companyId: Value(p['company_id'] as String? ?? ''),
                name: Value(p['name'] as String),
                description: Value(p['description'] as String?),
                location: Value(p['location'] as String?),
                status: Value(p['status'] as String? ?? 'active'),
                syncStatus: const Value('synced'),
                lastSyncedAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.tryParse(p['updated_at'] as String? ?? '')),
              )).toList();
          await db.projectsDao.upsertAll(projectRows);

          // Write machines
          final machineRows = updates.machines.map((m) => MachinesTableCompanion(
                id: Value(m['id'] as String),
                companyId: Value(m['company_id'] as String? ?? ''),
                serialNumber: Value(m['serial_number'] as String),
                model: Value(m['model'] as String),
                manufacturer: Value(m['manufacturer'] as String),
                type: Value(m['type'] as String),
                isApproved: Value(m['is_approved'] as bool? ?? false),
                isActive: Value(m['is_active'] as bool? ?? true),
                lastCalibrationDate: Value(m['last_calibration_date'] as String?),
                nextCalibrationDate: Value(m['next_calibration_date'] as String?),
                syncStatus: const Value('synced'),
                lastSyncedAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.tryParse(m['updated_at'] as String? ?? '')),
              )).toList();
          await db.machinesDao.upsertAll(machineRows);

          // Write welding standards
          final standardRows = updates.weldingStandards.map((s) =>
              WeldingStandardsTableCompanion(
                id: Value(s['id'] as String),
                name: Value(s['name'] as String),
                code: Value(s['code'] as String),
                weldType: Value(s['weld_type'] as String? ?? 'butt_fusion'),
                description: Value(s['description'] as String?),
                version: Value(s['version'] as String?),
                isActive: Value(s['is_active'] as bool? ?? true),
                syncStatus: const Value('synced'),
                lastSyncedAt: Value(DateTime.now()),
                updatedAt: Value(
                    DateTime.tryParse(s['updated_at'] as String? ?? '')),
              )).toList();
          await db.weldingParametersDao.upsertAllStandards(standardRows);

          // Write welding parameters
          final paramRows = updates.weldingParameters.map((p) =>
              WeldingParametersTableCompanion(
                id: Value(p['id'] as String),
                standardId: Value(p['standard_id'] as String),
                pipeMaterial: Value(p['pipe_material'] as String),
                pipeDiameterMm: Value((p['pipe_diameter_mm'] as num).toDouble()),
                sdrRating: Value(p['sdr_rating'] as String),
                wallThicknessMm: Value(
                    (p['wall_thickness_mm'] as num?)?.toDouble()),
                ambientTempMinCelsius: Value(
                    (p['ambient_temp_min_celsius'] as num?)?.toDouble() ??
                        -15.0),
                ambientTempMaxCelsius: Value(
                    (p['ambient_temp_max_celsius'] as num?)?.toDouble() ??
                        50.0),
                heatingUpTimeS: Value(p['heating_up_time_s'] as int?),
                heatingUpPressureBar: Value(
                    (p['heating_up_pressure_bar'] as num?)?.toDouble()),
                heatingTimeS: Value(p['heating_time_s'] as int?),
                heatingPressureBar: Value(
                    (p['heating_pressure_bar'] as num?)?.toDouble()),
                changeoverTimeMaxS:
                    Value(p['changeover_time_max_s'] as int?),
                buildupTimeS: Value(p['buildup_time_s'] as int?),
                fusionTimeS: Value(p['fusion_time_s'] as int?),
                fusionPressureBar: Value(
                    (p['fusion_pressure_bar'] as num?)?.toDouble()),
                fusionPressureMinBar: Value(
                    (p['fusion_pressure_min_bar'] as num?)?.toDouble()),
                fusionPressureMaxBar: Value(
                    (p['fusion_pressure_max_bar'] as num?)?.toDouble()),
                coolingTimeS: Value(p['cooling_time_s'] as int?),
                coolingPressureBar: Value(
                    (p['cooling_pressure_bar'] as num?)?.toDouble()),
                efWeldingTimeS: Value(p['ef_welding_time_s'] as int?),
                efWeldingVoltage: Value(
                    (p['ef_welding_voltage'] as num?)?.toDouble()),
                efCoolingTimeS: Value(p['ef_cooling_time_s'] as int?),
                heatingTempNominalCelsius: Value(
                    (p['heating_temp_nominal_celsius'] as num?)?.toDouble()),
                heatingTempMinCelsius: Value(
                    (p['heating_temp_min_celsius'] as num?)?.toDouble()),
                heatingTempMaxCelsius: Value(
                    (p['heating_temp_max_celsius'] as num?)?.toDouble()),
                notes: Value(p['notes'] as String?),
                isActive: Value(p['is_active'] as bool? ?? true),
                syncStatus: const Value('synced'),
                lastSyncedAt: Value(DateTime.now()),
                updatedAt: Value(
                    DateTime.tryParse(p['updated_at'] as String? ?? '')),
              )).toList();
          await db.weldingParametersDao.upsertAllParameters(paramRows);

          return Success(updates);
        },
        failure: (e) => Failure(SyncException('Download failed: ${e.message}', e)),
      );
    } catch (e) {
      return Failure(SyncException('Unexpected download error', e));
    }
  }
}
