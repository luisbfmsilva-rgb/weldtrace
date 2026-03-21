import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/result.dart';
import '../models/sync_models.dart';

/// Direct Supabase client data source for offline→cloud sync.
///
/// Replaces the Express `/sync/upload` and `/sync/updates` API routes with
/// direct `supabase_flutter` upserts and selects.
///
/// Upload order: machines → projects → welds → weld_steps → sensor_logs
/// (parent entities first to satisfy FK constraints).
class SupabaseSyncDataSource {
  const SupabaseSyncDataSource();

  SupabaseClient get _client => Supabase.instance.client;

  // ── Upload ────────────────────────────────────────────────────────────────

  Future<Result<SyncUploadResult>> upload(SyncUploadPayload payload) async {
    try {
      var machines   = const EntitySyncResult(inserted: 0, errors: []);
      var projects   = const EntitySyncResult(inserted: 0, errors: []);
      var welds      = const EntitySyncResult(inserted: 0, errors: []);
      var steps      = const EntitySyncResult(inserted: 0, errors: []);
      var sensorLogs = const EntitySyncResult(inserted: 0, errors: []);

      if (payload.machines.isNotEmpty) {
        final rows = _toSnake(payload.machines);
        await _client.from('machines').upsert(rows, onConflict: 'id');
        machines = EntitySyncResult(inserted: rows.length, errors: []);
      }

      if (payload.projects.isNotEmpty) {
        final rows = _toSnake(payload.projects);
        await _client.from('projects').upsert(rows, onConflict: 'id');
        projects = EntitySyncResult(inserted: rows.length, errors: []);
      }

      if (payload.welds.isNotEmpty) {
        final rows = _toSnake(payload.welds);
        await _client.from('welds').upsert(rows, onConflict: 'id');
        welds = EntitySyncResult(inserted: rows.length, errors: []);
      }

      if (payload.weldSteps.isNotEmpty) {
        final rows = _toSnake(payload.weldSteps);
        await _client.from('weld_steps').upsert(rows, onConflict: 'id');
        steps = EntitySyncResult(inserted: rows.length, errors: []);
      }

      for (final batch in payload.sensorLogBatches) {
        final rows = batch.records.map((r) => {
          'weld_id':              batch.weldId,
          'recorded_at':          r.recordedAt,
          if (r.pressureBar != null)       'pressure_bar':        r.pressureBar,
          if (r.temperatureCelsius != null) 'temperature_celsius': r.temperatureCelsius,
          if (r.phaseName != null)         'phase_name':          r.phaseName,
          if (r.weldStepId != null)        'weld_step_id':        r.weldStepId,
        }).toList();
        await _client
            .from('sensor_logs')
            .upsert(rows, onConflict: 'weld_id,recorded_at');
        sensorLogs = EntitySyncResult(
          inserted: sensorLogs.inserted + rows.length,
          errors: [],
        );
      }

      return Success(SyncUploadResult(
        machines:   machines,
        projects:   projects,
        welds:      welds,
        weldSteps:  steps,
        weldErrors: const EntitySyncResult(inserted: 0, errors: []),
        weldPhotos: const EntitySyncResult(inserted: 0, errors: []),
        sensorLogs: sensorLogs,
        syncedAt:   DateTime.now().toUtc().toIso8601String(),
      ));
    } catch (e) {
      return Failure(SyncException('Supabase upload failed', e));
    }
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<Result<SyncUpdatesResponse>> getUpdates({
    required DateTime since,
    String? projectId,
  }) async {
    try {
      final sinceStr = since.toUtc().toIso8601String();

      final projectsQuery = _client
          .from('projects')
          .select()
          .gte('updated_at', sinceStr);
      final machinesQuery = _client
          .from('machines')
          .select()
          .gte('updated_at', sinceStr);
      final standardsQuery = _client
          .from('welding_standards')
          .select()
          .gte('updated_at', sinceStr);
      final paramsQuery = _client
          .from('welding_parameters')
          .select()
          .gte('updated_at', sinceStr);

      final results = await Future.wait([
        projectsQuery,
        machinesQuery,
        standardsQuery,
        paramsQuery,
      ]);

      final projectRows  = _castRows(results[0]);
      final machineRows  = _castRows(results[1]);
      final standardRows = _castRows(results[2]);
      final paramRows    = _castRows(results[3]);

      return Success(SyncUpdatesResponse(
        projects:           projectRows,
        projectUsers:       [],
        machines:           machineRows,
        sensorCalibrations: [],
        weldingStandards:   standardRows,
        weldingParameters:  paramRows,
        downloadedAt:       DateTime.now().toUtc().toIso8601String(),
      ));
    } catch (e) {
      return Failure(SyncException('Supabase download failed', e));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Converts a list of camelCase key maps to snake_case for Supabase columns.
  List<Map<String, dynamic>> _toSnake(List<Map<String, dynamic>> rows) =>
      rows.map((r) => r.map((k, v) => MapEntry(_camelToSnake(k), v))).toList();

  /// 'projectId' → 'project_id', 'isCancelled' → 'is_cancelled', etc.
  String _camelToSnake(String key) => key.replaceAllMapped(
      RegExp(r'([A-Z])'), (m) => '_${m.group(0)!.toLowerCase()}');

  List<Map<String, dynamic>> _castRows(dynamic raw) =>
      (raw as List<dynamic>).cast<Map<String, dynamic>>();
}
