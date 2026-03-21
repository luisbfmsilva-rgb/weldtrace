import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/result.dart';
import '../local/database/app_database.dart';
import '../models/sync_models.dart';
import '../remote/supabase_sync_data_source.dart';

/// Coordinates offline data upload and cloud-to-local update download
/// using direct Supabase client calls (no intermediate Express API).
class SyncRepository {
  const SyncRepository({
    required this.remoteDataSource,
    required this.db,
  });

  final SupabaseSyncDataSource remoteDataSource;
  final AppDatabase db;

  // ── Upload (local → cloud) ────────────────────────────────────────────────

  /// Uploads all pending local records to Supabase via direct upsert.
  Future<Result<SyncUploadResult>> syncUpload() async {
    try {
      // 1. Gather pending records from every DAO in parallel
      final results = await Future.wait([
        db.machinesDao.getPendingSync(),
        db.projectsDao.getPendingSync(),
        db.weldsDao.getPendingSync(),
        db.weldsDao.getPendingSteps(),
      ]);
      final pendingMachines = results[0] as List;
      final pendingProjects = results[1] as List;
      final pendingWelds    = results[2] as List;
      final pendingSteps    = results[3] as List;

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

      // 3a. Build machine payloads (camelCase — converted to snake_case in data source)
      final machinePayloads = pendingMachines.map((m) => {
            'id':                    m.id,
            'serialNumber':          m.serialNumber,
            'model':                 m.model,
            'manufacturer':          m.manufacturer,
            'type':                  m.type,
            if (m.manufactureYear != null) 'manufactureYear': m.manufactureYear,
            if (m.hydraulicCylinderAreaMm2 != null)
              'hydraulicCylinderAreaMm2': m.hydraulicCylinderAreaMm2,
            'isApproved':            m.isApproved,
            'isActive':              m.isActive,
            if (m.lastCalibrationDate != null)
              'lastCalibrationDate': m.lastCalibrationDate,
            if (m.nextCalibrationDate != null)
              'nextCalibrationDate': m.nextCalibrationDate,
            if (m.notes != null) 'notes': m.notes,
            if (m.updatedAt != null)
              'updatedAt': m.updatedAt!.toUtc().toIso8601String(),
          }).toList();

      // 3b. Build project payloads
      final projectPayloads = pendingProjects.map((p) => {
            'id':          p.id,
            'name':        p.name,
            'status':      p.status,
            if (p.description != null) 'description': p.description,
            if (p.location != null)    'location':    p.location,
            if (p.gpsLat != null)      'gpsLat':      p.gpsLat,
            if (p.gpsLng != null)      'gpsLng':      p.gpsLng,
            if (p.startDate != null)   'startDate':   p.startDate,
            if (p.endDate != null)     'endDate':     p.endDate,
            if (p.clientName != null)  'clientName':  p.clientName,
            if (p.contractNumber != null) 'contractNumber': p.contractNumber,
            if (p.updatedAt != null)
              'updatedAt': p.updatedAt!.toUtc().toIso8601String(),
          }).toList();

      // 3c. Build weld payloads
      final weldPayloads = pendingWelds.map((w) => {
            'id':        w.id,
            'projectId': w.projectId,
            'machineId': w.machineId,
            'weldType':  w.weldType,
            'status':    w.status,
            'pipeMaterial': w.pipeMaterial,
            'pipeDiameter': w.pipeDiameter,
            if (w.pipeSdr != null)            'pipeSdr':            w.pipeSdr,
            if (w.pipeWallThickness != null)  'pipeWallThickness':  w.pipeWallThickness,
            if (w.ambientTemperature != null) 'ambientTemperature': w.ambientTemperature,
            if (w.gpsLat != null)             'gpsLat':             w.gpsLat,
            if (w.gpsLng != null)             'gpsLng':             w.gpsLng,
            if (w.standardUsed != null)       'standardUsed':       w.standardUsed,
            if (w.standardId != null)         'standardId':         w.standardId,
            'isCancelled': w.isCancelled,
            if (w.cancelReason != null) 'cancelReason': w.cancelReason,
            if (w.cancelTimestamp != null)
              'cancelTimestamp': w.cancelTimestamp!.toUtc().toIso8601String(),
            if (w.notes != null) 'notes': w.notes,
            'startedAt': w.startedAt.toUtc().toIso8601String(),
            if (w.completedAt != null)
              'completedAt': w.completedAt!.toUtc().toIso8601String(),
          }).toList();

      // 3d. Build weld step payloads
      final stepPayloads = pendingSteps.map((s) => {
            'id':        s.id,
            'weldId':    s.weldId,
            'phaseName': s.phaseName,
            'phaseOrder': s.phaseOrder,
            if (s.startedAt != null)
              'startedAt': s.startedAt!.toUtc().toIso8601String(),
            if (s.completedAt != null)
              'completedAt': s.completedAt!.toUtc().toIso8601String(),
            if (s.nominalValue != null)      'nominalValue':      s.nominalValue,
            if (s.actualValue != null)       'actualValue':       s.actualValue,
            if (s.unit != null)              'unit':              s.unit,
            if (s.validationPassed != null)  'validationPassed':  s.validationPassed,
            if (s.notes != null)             'notes':             s.notes,
          }).toList();

      final nothingToUpload = machinePayloads.isEmpty &&
          projectPayloads.isEmpty &&
          weldPayloads.isEmpty &&
          stepPayloads.isEmpty &&
          sensorBatches.isEmpty;

      if (nothingToUpload) {
        return Success(SyncUploadResult(
          machines:   const EntitySyncResult(inserted: 0, errors: []),
          projects:   const EntitySyncResult(inserted: 0, errors: []),
          welds:      const EntitySyncResult(inserted: 0, errors: []),
          weldSteps:  const EntitySyncResult(inserted: 0, errors: []),
          weldErrors: const EntitySyncResult(inserted: 0, errors: []),
          weldPhotos: const EntitySyncResult(inserted: 0, errors: []),
          sensorLogs: const EntitySyncResult(inserted: 0, errors: []),
          syncedAt:   DateTime.now().toUtc().toIso8601String(),
        ));
      }

      // 4. Upload everything
      final payload = SyncUploadPayload(
        machines:         machinePayloads,
        projects:         projectPayloads,
        welds:            weldPayloads,
        weldSteps:        stepPayloads,
        sensorLogBatches: sensorBatches,
      );

      final result = await remoteDataSource.upload(payload);

      return result.when(
        success: (uploadResult) async {
          // 5. Mark as synced only if upload succeeded per entity
          if (!uploadResult.machines.hasErrors) {
            for (final m in pendingMachines) {
              await db.machinesDao.markSynced(m.id);
            }
          }
          if (!uploadResult.projects.hasErrors) {
            for (final p in pendingProjects) {
              await db.projectsDao.markSynced(p.id);
            }
          }
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

  // ── Force full re-upload ──────────────────────────────────────────────────

  /// Marks ALL local machines and projects as 'pending' for forced re-upload.
  Future<void> markAllLocalAsPending() async {
    await db.transaction(() async {
      final machines = await db.machinesDao.getAll();
      for (final m in machines) {
        await db.machinesDao.upsert(MachinesTableCompanion(
          id: Value(m.id),
          syncStatus: const Value('pending'),
        ));
      }
      final projects = await db.projectsDao.getAll();
      for (final p in projects) {
        await db.projectsDao.upsert(ProjectsTableCompanion(
          id: Value(p.id),
          syncStatus: const Value('pending'),
        ));
      }
    });
  }

  // ── Download (cloud → local) ──────────────────────────────────────────────

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
                clientName: Value(p['client_name'] as String?),
                contractNumber: Value(p['contract_number'] as String?),
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
                hydraulicCylinderAreaMm2: Value(
                    (m['hydraulic_cylinder_area_mm2'] as num?)?.toDouble()),
                lastCalibrationDate: Value(m['last_calibration_date'] as String?),
                nextCalibrationDate: Value(m['next_calibration_date'] as String?),
                notes: Value(m['notes'] as String?),
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
                updatedAt: Value(DateTime.tryParse(s['updated_at'] as String? ?? '')),
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
                wallThicknessMm: Value((p['wall_thickness_mm'] as num?)?.toDouble()),
                ambientTempMinCelsius: Value(
                    (p['ambient_temp_min_celsius'] as num?)?.toDouble() ?? -15.0),
                ambientTempMaxCelsius: Value(
                    (p['ambient_temp_max_celsius'] as num?)?.toDouble() ?? 50.0),
                heatingUpTimeS: Value(p['heating_up_time_s'] as int?),
                heatingUpPressureBar: Value(
                    (p['heating_up_pressure_bar'] as num?)?.toDouble()),
                heatingTimeS: Value(p['heating_time_s'] as int?),
                heatingPressureBar: Value(
                    (p['heating_pressure_bar'] as num?)?.toDouble()),
                changeoverTimeMaxS: Value(p['changeover_time_max_s'] as int?),
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
                updatedAt: Value(DateTime.tryParse(p['updated_at'] as String? ?? '')),
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
