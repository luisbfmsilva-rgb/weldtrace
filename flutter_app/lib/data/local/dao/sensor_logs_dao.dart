import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../tables/sensor_logs_table.dart';

part 'sensor_logs_dao.g.dart';

@DriftAccessor(tables: [SensorLogsTable])
class SensorLogsDao extends DatabaseAccessor<AppDatabase> with _$SensorLogsDaoMixin {
  SensorLogsDao(super.db);

  /// Returns up to [limit] sensor log records for graphing, ordered by time.
  Future<List<SensorLogRecord>> getForWeld(String weldId, {int limit = 3600}) =>
      (select(sensorLogsTable)
            ..where((t) => t.weldId.equals(weldId))
            ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)])
            ..limit(limit))
          .get();

  Stream<List<SensorLogRecord>> watchForWeld(String weldId) =>
      (select(sensorLogsTable)
            ..where((t) => t.weldId.equals(weldId))
            ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
          .watch();

  /// Returns pending records for a specific weld, chunked to [batchSize].
  Future<List<SensorLogRecord>> getPendingBatch(String weldId,
      {int batchSize = 200}) =>
      (select(sensorLogsTable)
            ..where((t) => t.weldId.equals(weldId) & t.syncStatus.equals('pending'))
            ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)])
            ..limit(batchSize))
          .get();

  Future<void> insert(SensorLogsTableCompanion row) =>
      into(sensorLogsTable).insert(row);

  Future<void> insertAll(List<SensorLogsTableCompanion> rows) =>
      batch((b) => b.insertAll(sensorLogsTable, rows));

  Future<void> markSynced(List<String> ids) async {
    await batch((b) {
      for (final id in ids) {
        b.update(
          sensorLogsTable,
          SensorLogsTableCompanion(
            syncStatus: const Value('synced'),
            lastSyncedAt: Value(DateTime.now()),
          ),
          where: (t) => t.id.equals(id),
        );
      }
    });
  }
}
