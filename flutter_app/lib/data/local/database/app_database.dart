import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../tables/projects_table.dart';
import '../tables/machines_table.dart';
import '../tables/welds_table.dart';
import '../tables/weld_steps_table.dart';
import '../tables/sensor_logs_table.dart';
import '../tables/sensor_calibrations_table.dart';
import '../dao/projects_dao.dart';
import '../dao/machines_dao.dart';
import '../dao/welds_dao.dart';
import '../dao/sensor_logs_dao.dart';

part 'app_database.g.dart';

/// Drift offline-first SQLite database.
///
/// Code generation:
///   flutter pub run build_runner build --delete-conflicting-outputs
@DriftDatabase(
  tables: [
    ProjectsTable,
    MachinesTable,
    WeldsTable,
    WeldStepsTable,
    SensorLogsTable,
    SensorCalibrationsTable,
  ],
  daos: [
    ProjectsDao,
    MachinesDao,
    WeldsDao,
    SensorLogsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Future schema migrations go here
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'weldtrace');
  }
}
