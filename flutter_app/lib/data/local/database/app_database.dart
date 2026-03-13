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
import '../dao/projects_dao.dart';
import '../dao/machines_dao.dart';
import '../dao/welds_dao.dart';
import '../dao/sensor_logs_dao.dart';
import '../dao/welding_parameters_dao.dart';

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
  ],
  daos: [
    ProjectsDao,
    MachinesDao,
    WeldsDao,
    SensorLogsDao,
    WeldingParametersDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 5;

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
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'weldtrace');
  }
}
