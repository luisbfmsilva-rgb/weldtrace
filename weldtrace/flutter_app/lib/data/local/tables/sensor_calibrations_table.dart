import 'package:drift/drift.dart';

/// Calibration records for pressure and temperature sensors.
/// offset and slope apply linear correction: corrected = raw * slope + offset
@DataClassName('SensorCalibrationRecord')
class SensorCalibrationsTable extends Table {
  @override
  String get tableName => 'sensor_calibrations';

  TextColumn get id => text()();
  TextColumn get machineId => text()();    // FK → machines.id
  TextColumn get sensorSerial => text()();
  TextColumn get calibrationDate => text()();   // YYYY-MM-DD
  TextColumn get referenceDevice => text()();
  TextColumn get referenceCertificate => text()();

  RealColumn get offsetValue => real().withDefault(const Constant(0.0))();
  RealColumn get slopeValue => real().withDefault(const Constant(1.0))();

  TextColumn get notes => text().nullable()();
  TextColumn get calibratedBy => text().nullable()();

  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
