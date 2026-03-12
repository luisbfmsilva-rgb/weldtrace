import 'package:drift/drift.dart';

/// Time-series pressure and temperature readings at 1 Hz.
/// Logs are write-once — no UPDATE policy exists in the cloud schema either.
@DataClassName('SensorLogRecord')
class SensorLogsTable extends Table {
  @override
  String get tableName => 'sensor_logs';

  TextColumn get id => text()();
  TextColumn get weldId => text()();       // FK → welds.id
  TextColumn get weldStepId => text().nullable()();

  DateTimeColumn get recordedAt => dateTime()();
  RealColumn get pressureBar => real().nullable()();
  RealColumn get temperatureCelsius => real().nullable()();
  TextColumn get phaseName => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  // Sensor logs are never updated after insert.
  // 'pending' → uploaded to cloud, kept locally for graphing.
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
