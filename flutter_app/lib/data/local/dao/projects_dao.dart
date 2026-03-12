import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../tables/projects_table.dart';

part 'projects_dao.g.dart';

@DriftAccessor(tables: [ProjectsTable])
class ProjectsDao extends DatabaseAccessor<AppDatabase> with _$ProjectsDaoMixin {
  ProjectsDao(super.db);

  /// All projects for the current user's company, ordered by name.
  Stream<List<ProjectRecord>> watchAll() =>
      (select(projectsTable)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<List<ProjectRecord>> getAll() =>
      (select(projectsTable)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<ProjectRecord?> getById(String id) =>
      (select(projectsTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Projects that need to be uploaded to the cloud.
  Future<List<ProjectRecord>> getPendingSync() =>
      (select(projectsTable)..where((t) => t.syncStatus.equals('pending'))).get();

  Future<void> upsert(ProjectsTableCompanion row) =>
      into(projectsTable).insertOnConflictUpdate(row);

  Future<void> upsertAll(List<ProjectsTableCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(projectsTable, rows));

  Future<void> markSynced(String id) =>
      (update(projectsTable)..where((t) => t.id.equals(id))).write(
        ProjectsTableCompanion(
          syncStatus: const Value('synced'),
          lastSyncedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteById(String id) =>
      (delete(projectsTable)..where((t) => t.id.equals(id))).go();
}
