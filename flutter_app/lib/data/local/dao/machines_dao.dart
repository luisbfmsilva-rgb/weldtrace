import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../tables/machines_table.dart';

part 'machines_dao.g.dart';

@DriftAccessor(tables: [MachinesTable])
class MachinesDao extends DatabaseAccessor<AppDatabase> with _$MachinesDaoMixin {
  MachinesDao(super.db);

  Stream<List<MachineRecord>> watchAll() =>
      (select(machinesTable)..orderBy([(t) => OrderingTerm.asc(t.model)])).watch();

  Future<List<MachineRecord>> getAll() =>
      (select(machinesTable)..orderBy([(t) => OrderingTerm.asc(t.model)])).get();

  Future<List<MachineRecord>> getApproved() =>
      (select(machinesTable)
            ..where((t) => t.isApproved.equals(true) & t.isActive.equals(true)))
          .get();

  Future<MachineRecord?> getById(String id) =>
      (select(machinesTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(MachinesTableCompanion row) =>
      into(machinesTable).insertOnConflictUpdate(row);

  Future<void> upsertAll(List<MachinesTableCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(machinesTable, rows));

  Future<void> markSynced(String id) =>
      (update(machinesTable)..where((t) => t.id.equals(id))).write(
        MachinesTableCompanion(
          syncStatus: const Value('synced'),
          lastSyncedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteById(String id) =>
      (delete(machinesTable)..where((t) => t.id.equals(id))).go();

  Future<void> updateMachine(MachinesTableCompanion row) =>
      (update(machinesTable)..where((t) => t.id.equals(row.id.value))).write(row);
}
