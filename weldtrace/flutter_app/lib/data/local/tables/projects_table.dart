import 'package:drift/drift.dart';

/// Local SQLite table that mirrors the Supabase `projects` table.
/// `sync_status` tracks whether the record is pending upload, synced,
/// or in conflict with the server version.
@DataClassName('ProjectRecord')
class ProjectsTable extends Table {
  @override
  String get tableName => 'projects';

  // Primary key — UUID string from the server
  TextColumn get id => text()();
  TextColumn get companyId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();

  RealColumn get gpsLat => real().nullable()();
  RealColumn get gpsLng => real().nullable()();

  TextColumn get startDate => text().nullable()();
  TextColumn get endDate => text().nullable()();
  TextColumn get clientName => text().nullable()();
  TextColumn get contractNumber => text().nullable()();
  TextColumn get createdBy => text().nullable()();

  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  // Offline sync metadata
  TextColumn get syncStatus =>
      text().withDefault(const Constant('synced'))(); // pending | synced | conflict
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
