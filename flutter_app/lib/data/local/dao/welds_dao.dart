import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../tables/welds_table.dart';
import '../tables/weld_steps_table.dart';

part 'welds_dao.g.dart';

@DriftAccessor(tables: [WeldsTable, WeldStepsTable])
class WeldsDao extends DatabaseAccessor<AppDatabase> with _$WeldsDaoMixin {
  WeldsDao(super.db);

  // ── Welds ─────────────────────────────────────────────────────────────────

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

  Future<WeldRecord?> getById(String id) =>
      (select(weldsTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<WeldRecord?> getActiveWeld() =>
      (select(weldsTable)..where((t) => t.status.equals('in_progress'))).getSingleOrNull();

  Future<List<WeldRecord>> getPendingSync() =>
      (select(weldsTable)..where((t) => t.syncStatus.equals('pending'))).get();

  Future<String> insertWeld(WeldsTableCompanion row) =>
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
  /// [id]            — weld UUID
  /// [signature]     — 64-char SHA-256 hex digest
  /// [curveJson]     — JSON-encoded pressure × time curve
  /// [pdfBytes]      — rendered PDF report as raw bytes (nullable — stored
  ///                   only when PDF generation succeeded)
  Future<void> saveTraceData({
    required String id,
    required String signature,
    required String curveJson,
    Uint8List? pdfBytes,
  }) =>
      (update(weldsTable)..where((t) => t.id.equals(id))).write(
        WeldsTableCompanion(
          traceSignature: Value(signature),
          traceCurveJson: Value(curveJson),
          tracePdf:       Value(pdfBytes),
          updatedAt:      Value(DateTime.now()),
        ),
      );

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
