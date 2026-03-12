import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../tables/welding_standards_table.dart';
import '../tables/welding_parameters_table.dart';

part 'welding_parameters_dao.g.dart';

@DriftAccessor(tables: [WeldingStandardsTable, WeldingParametersTable])
class WeldingParametersDao extends DatabaseAccessor<AppDatabase>
    with _$WeldingParametersDaoMixin {
  WeldingParametersDao(super.db);

  // ── Standards ─────────────────────────────────────────────────────────────

  Future<List<WeldingStandardRecord>> getAllStandards() =>
      (select(weldingStandardsTable)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<WeldingStandardRecord?> getStandardById(String id) =>
      (select(weldingStandardsTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> upsertStandard(WeldingStandardsTableCompanion row) =>
      into(weldingStandardsTable).insertOnConflictUpdate(row);

  Future<void> upsertAllStandards(List<WeldingStandardsTableCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(weldingStandardsTable, rows));

  // ── Parameters ────────────────────────────────────────────────────────────

  /// All distinct pipe diameters available for a given standard and material.
  /// Returns sorted ascending for display in a dropdown.
  Future<List<double>> getAvailableDiameters({
    required String standardId,
    required String pipeMaterial,
  }) async {
    final rows = await (select(weldingParametersTable)
          ..where((t) =>
              t.standardId.equals(standardId) &
              t.pipeMaterial.equals(pipeMaterial) &
              t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.pipeDiameterMm)]))
        .get();

    final seen = <double>{};
    return rows
        .map((r) => r.pipeDiameterMm)
        .where(seen.add)
        .toList();
  }

  /// All distinct SDR ratings available for a given standard, material, and diameter.
  Future<List<String>> getAvailableSdrRatings({
    required String standardId,
    required String pipeMaterial,
    required double pipeDiameterMm,
  }) async {
    final rows = await (select(weldingParametersTable)
          ..where((t) =>
              t.standardId.equals(standardId) &
              t.pipeMaterial.equals(pipeMaterial) &
              t.pipeDiameterMm.isBetweenValues(
                  pipeDiameterMm - 0.01, pipeDiameterMm + 0.01) &
              t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.sdrRating)]))
        .get();

    final seen = <String>{};
    return rows.map((r) => r.sdrRating).where(seen.add).toList();
  }

  /// Look up the single matching parameter record for a complete weld spec.
  /// Returns null if no match — the UI should show an error in that case.
  Future<WeldingParameterRecord?> lookupParameters({
    required String standardId,
    required String pipeMaterial,
    required double pipeDiameterMm,
    required String sdrRating,
  }) =>
      (select(weldingParametersTable)
            ..where((t) =>
                t.standardId.equals(standardId) &
                t.pipeMaterial.equals(pipeMaterial) &
                t.pipeDiameterMm.isBetweenValues(
                    pipeDiameterMm - 0.01, pipeDiameterMm + 0.01) &
                t.sdrRating.equals(sdrRating) &
                t.isActive.equals(true))
            ..limit(1))
          .getSingleOrNull();

  Future<void> upsertParameter(WeldingParametersTableCompanion row) =>
      into(weldingParametersTable).insertOnConflictUpdate(row);

  Future<void> upsertAllParameters(
          List<WeldingParametersTableCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(weldingParametersTable, rows));
}
