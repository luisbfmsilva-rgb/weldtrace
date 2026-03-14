import 'package:drift/drift.dart';

@DataClassName('MachineRecord')
class MachinesTable extends Table {
  @override
  String get tableName => 'machines';

  TextColumn get id => text()();
  TextColumn get companyId => text()();
  TextColumn get serialNumber => text()();
  TextColumn get model => text()();
  TextColumn get manufacturer => text()();

  // 'electrofusion' | 'butt_fusion' | 'universal'
  TextColumn get type => text()();

  IntColumn get manufactureYear => integer().nullable()();
  BoolColumn get isApproved => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get approvedBy => text().nullable()();
  DateTimeColumn get approvedAt => dateTime().nullable()();

  /// Hydraulic cylinder piston area [mm²].
  ///
  /// Stamped on the machine data plate or from the calibration certificate.
  /// Used to convert standard interfacial pressures to machine gauge pressures.
  /// Null means the value has not been entered for this machine.
  RealColumn get hydraulicCylinderAreaMm2 => real().nullable()();

  TextColumn get lastCalibrationDate => text().nullable()();
  TextColumn get nextCalibrationDate => text().nullable()();
  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
