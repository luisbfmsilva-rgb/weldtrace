import 'package:drift/drift.dart';

import '../database/app_database.dart';

part 'pipes_catalog_dao.g.dart';

@DriftAccessor(tables: [PipesCatalogTable])
class PipesCatalogDao extends DatabaseAccessor<AppDatabase>
    with _$PipesCatalogDaoMixin {
  PipesCatalogDao(super.db);

  /// Returns all unique outer diameters in ascending order.
  Future<List<double>> getDistinctDiameters() async {
    final query = selectOnly(pipesCatalogTable, distinct: true)
      ..addColumns([pipesCatalogTable.de])
      ..orderBy([OrderingTerm.asc(pipesCatalogTable.de)]);
    return (await query.get())
        .map((row) => row.read(pipesCatalogTable.de)!)
        .toList();
  }

  /// Returns all SDR values available for a given outer diameter.
  Future<List<double>> getSdrsForDiameter(double de) async {
    final query = selectOnly(pipesCatalogTable, distinct: true)
      ..addColumns([pipesCatalogTable.sdr])
      ..where(pipesCatalogTable.de.equalsExp(Variable.withReal(de)))
      ..orderBy([OrderingTerm.asc(pipesCatalogTable.sdr)]);
    return (await query.get())
        .map((row) => row.read(pipesCatalogTable.sdr)!)
        .toList();
  }

  /// Returns the catalog record for a specific (de, sdr) pair, or null.
  Future<PipeCatalogRecord?> getByDiameterAndSdr(double de, double sdr) async {
    return (select(pipesCatalogTable)
          ..where((t) =>
              t.de.equalsExp(Variable.withReal(de)) &
              t.sdr.equalsExp(Variable.withReal(sdr))))
        .getSingleOrNull();
  }

  /// True when the catalog table has at least one row.
  Future<bool> hasData() async {
    final count = countAll();
    final query = selectOnly(pipesCatalogTable)..addColumns([count]);
    final row = await query.getSingle();
    return (row.read(count) ?? 0) > 0;
  }

  /// Inserts all rows in a batch (used by the seeder).
  Future<void> insertAll(List<PipesCatalogTableCompanion> rows) =>
      batch((b) => b.insertAll(pipesCatalogTable, rows,
          mode: InsertMode.insertOrIgnore));
}
