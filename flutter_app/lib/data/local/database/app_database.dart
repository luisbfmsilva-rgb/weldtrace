import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../tables/projects_table.dart';
import '../tables/machines_table.dart';
import '../tables/welds_table.dart';
import '../tables/weld_steps_table.dart';
import '../tables/sensor_logs_table.dart';
import '../tables/sensor_calibrations_table.dart';
import '../tables/welding_standards_table.dart';
import '../tables/welding_parameters_table.dart';
import '../tables/pipes_catalog_table.dart';
import '../dao/projects_dao.dart';
import '../dao/machines_dao.dart';
import '../dao/welds_dao.dart';
import '../dao/sensor_logs_dao.dart';
import '../dao/welding_parameters_dao.dart';
import '../dao/pipes_catalog_dao.dart';

part 'app_database.g.dart';

/// Drift offline-first SQLite database.
///
/// Code generation (run once after any table/DAO change):
///   flutter pub run build_runner build --delete-conflicting-outputs
@DriftDatabase(
  tables: [
    ProjectsTable,
    MachinesTable,
    WeldsTable,
    WeldStepsTable,
    SensorLogsTable,
    SensorCalibrationsTable,
    WeldingStandardsTable,
    WeldingParametersTable,
    PipesCatalogTable,
  ],
  daos: [
    ProjectsDao,
    MachinesDao,
    WeldsDao,
    SensorLogsDao,
    WeldingParametersDao,
    PipesCatalogDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 → v2: welding_standards and welding_parameters tables added
            await m.createTable(weldingStandardsTable);
            await m.createTable(weldingParametersTable);
          }
          if (from < 3) {
            // v2 → v3: hydraulicCylinderAreaMm2 column added to machines
            await m.addColumn(
                machinesTable, machinesTable.hydraulicCylinderAreaMm2);
          }
          if (from < 4) {
            // v3 → v4: weld traceability columns (signature, curve JSON, PDF)
            await m.addColumn(weldsTable, weldsTable.traceSignature);
            await m.addColumn(weldsTable, weldsTable.traceCurveJson);
            await m.addColumn(weldsTable, weldsTable.tracePdf);
          }
          if (from < 5) {
            // v4 → v5: trace quality indicator
            await m.addColumn(weldsTable, weldsTable.traceQuality);
          }
          if (from < 6) {
            // v5 → v6: gzip-compressed curve BLOB column
            await m.addColumn(weldsTable, weldsTable.traceCurveCompressed);
          }
          if (from < 7) {
            // v6 → v7: globally-unique joint ID for certification ledger
            await m.addColumn(weldsTable, weldsTable.jointId);
          }
          if (from < 8) {
            // v7 → v8: pipe dimensional catalog
            await m.createTable(pipesCatalogTable);
          }
          if (from < 9) {
            // v8 → v9: resume support + completion flags
            await m.addColumn(weldsTable, weldsTable.phasesJson);
            await m.addColumn(weldsTable, weldsTable.sessionMetaJson);
            await m.addColumn(weldsTable, weldsTable.coolingIncomplete);
            await m.addColumn(weldsTable, weldsTable.beadFormationSeconds);
            await m.addColumn(weldsTable, weldsTable.beadHeightMeasuredMm);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'weldtrace');
  }
}
