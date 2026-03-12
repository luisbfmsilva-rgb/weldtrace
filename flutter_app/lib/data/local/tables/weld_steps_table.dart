import 'package:drift/drift.dart';

/// A single phase step within a weld session (heating, pressurisation, cooling, etc.).
@DataClassName('WeldStepRecord')
class WeldStepsTable extends Table {
  @override
  String get tableName => 'weld_steps';

  TextColumn get id => text()();
  TextColumn get weldId => text()();       // FK → welds.id

  TextColumn get phaseName => text()();    // 'heating' | 'pressurisation' | 'cooling' | ...
  IntColumn get phaseOrder => integer()();

  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  RealColumn get nominalValue => real().nullable()();
  RealColumn get actualValue => real().nullable()();
  TextColumn get unit => text().nullable()();
  BoolColumn get validationPassed => boolean().nullable()();
  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
