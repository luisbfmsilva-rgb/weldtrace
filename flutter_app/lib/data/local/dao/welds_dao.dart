import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../tables/welds_table.dart';
import '../tables/weld_steps_table.dart';
import '../../../services/welding_trace/curve_compression.dart';
import '../../../services/welding_trace/weld_trace_recorder.dart';

part 'welds_dao.g.dart';

@DriftAccessor(tables: [WeldsTable, WeldStepsTable])
class WeldsDao extends DatabaseAccessor<AppDatabase> with _$WeldsDaoMixin {
  WeldsDao(super.db);

  // ── Welds ─────────────────────────────────────────────────────────────────

  Stream<List<WeldRecord>> watchAll() =>
      (select(weldsTable)..orderBy([(t) => OrderingTerm.desc(t.startedAt)])).watch();

  Future<List<WeldRecord>> getAll() =>
      (select(weldsTable)..orderBy([(t) => OrderingTerm.desc(t.startedAt)])).get();

  Stream<List<WeldRecord>> watchByProject(String projectId) =>
      (select(weldsTable)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
          .watch();

  Future<List<WeldRecord>> getByProject(String projectId) =>
      (select(weldsTable)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
          .get();

  Stream<List<WeldRecord>> watchCompleted() =>
      (select(weldsTable)
            ..where((t) => t.status.equals('completed'))
            ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]))
          .watch();

  Future<void> deleteById(String id) =>
      (delete(weldsTable)..where((t) => t.id.equals(id))).go();

  Future<WeldRecord?> getById(String id) =>
      (select(weldsTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<WeldRecord?> getActiveWeld() =>
      (select(weldsTable)..where((t) => t.status.equals('in_progress'))).getSingleOrNull();

  Future<List<WeldRecord>> getPendingSync() =>
      (select(weldsTable)..where((t) => t.syncStatus.equals('pending'))).get();

  Future<int> insertWeld(WeldsTableCompanion row) =>
      into(weldsTable).insert(row);

  Future<void> upsert(WeldsTableCompanion row) =>
      into(weldsTable).insertOnConflictUpdate(row);

  /// Completes a weld — IMMUTABLE after this point, matching cloud RLS policy.
  Future<void> completeWeld(String id, DateTime completedAt) =>
      (update(weldsTable)..where((t) => t.id.equals(id) & t.status.equals('in_progress')))
          .write(WeldsTableCompanion(
        status: const Value('completed'),
        completedAt: Value(completedAt),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ));

  Future<void> cancelWeld(String id, String reason) =>
      (update(weldsTable)..where((t) => t.id.equals(id) & t.status.equals('in_progress')))
          .write(WeldsTableCompanion(
        status: const Value('cancelled'),
        isCancelled: const Value(true),
        cancelReason: Value(reason),
        cancelTimestamp: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ));

  Future<void> markSynced(String id) =>
      (update(weldsTable)..where((t) => t.id.equals(id))).write(
        WeldsTableCompanion(
          syncStatus: const Value('synced'),
          lastSyncedAt: Value(DateTime.now()),
        ),
      );

  /// Persists the traceability payload for a completed weld.
  ///
  /// Must be called before [completeWeld] marks the row immutable.
  ///
  /// [id]                   — weld UUID
  /// [signature]            — 64-char SHA-256 hex digest
  /// [curveJson]            — JSON-encoded pressure × time curve (kept for
  ///                          backward compatibility; stored in TEXT column)
  /// [traceCurveCompressed] — gzip-compressed curve bytes (preferred; stored
  ///                          in BLOB column).  When provided, the DB stores
  ///                          both representations; consumers prefer the
  ///                          compressed form via [loadTraceCurve].
  /// [pdfBytes]             — rendered PDF report as raw bytes (nullable)
  /// [traceQuality]         — 'OK' when ≥ 2 samples, 'LOW_SAMPLE_COUNT' otherwise
  /// [jointId]              — globally-unique joint ID (UUID v7)
  Future<void> saveTraceData({
    required String id,
    required String signature,
    required String curveJson,
    Uint8List? traceCurveCompressed,
    Uint8List? pdfBytes,
    String? traceQuality,
    String? jointId,
  }) =>
      (update(weldsTable)..where((t) => t.id.equals(id))).write(
        WeldsTableCompanion(
          traceSignature:       Value(signature),
          traceCurveJson:       Value(curveJson),
          traceCurveCompressed: Value(traceCurveCompressed),
          tracePdf:             Value(pdfBytes),
          traceQuality:         Value(traceQuality),
          jointId:              Value(jointId),
          updatedAt:            Value(DateTime.now().toUtc()),
        ),
      );

  /// Loads and deserialises the pressure × time curve for a weld.
  ///
  /// Prefers the compressed BLOB column ([WeldsTable.traceCurveCompressed])
  /// when available.  Falls back to the plain JSON TEXT column
  /// ([WeldsTable.traceCurveJson]) for records from schema v4/v5.
  ///
  /// Returns `null` when the weld is not found or has no curve data.
  Future<List<WeldTracePoint>?> loadTraceCurve(String id) async {
    final weld = await getById(id);
    if (weld == null) return null;

    String? json;

    if (weld.traceCurveCompressed != null) {
      json = CurveCompression.decompressCurve(weld.traceCurveCompressed!);
    } else if (weld.traceCurveJson != null) {
      json = weld.traceCurveJson;
    }

    if (json == null) return null;

    final decoded = jsonDecode(json);
    if (decoded is! List) return null;
    return decoded
        .map((e) => WeldTracePoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ── Weld steps ────────────────────────────────────────────────────────────

  Future<List<WeldStepRecord>> getStepsForWeld(String weldId) =>
      (select(weldStepsTable)
            ..where((t) => t.weldId.equals(weldId))
            ..orderBy([(t) => OrderingTerm.asc(t.phaseOrder)]))
          .get();

  Stream<List<WeldStepRecord>> watchStepsForWeld(String weldId) =>
      (select(weldStepsTable)
            ..where((t) => t.weldId.equals(weldId))
            ..orderBy([(t) => OrderingTerm.asc(t.phaseOrder)]))
          .watch();

  Future<List<WeldStepRecord>> getPendingSteps() =>
      (select(weldStepsTable)..where((t) => t.syncStatus.equals('pending'))).get();

  Future<void> insertStep(WeldStepsTableCompanion row) =>
      into(weldStepsTable).insert(row);

  Future<void> markStepSynced(String id) =>
      (update(weldStepsTable)..where((t) => t.id.equals(id))).write(
        WeldStepsTableCompanion(
          syncStatus: const Value('synced'),
          lastSyncedAt: Value(DateTime.now()),
        ),
      );
}
