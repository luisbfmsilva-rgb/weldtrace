import 'package:drift/drift.dart';

/// Mirrors the cloud `welding_standards` table.
/// Seeded from the sync download endpoint.
@DataClassName('WeldingStandardRecord')
class WeldingStandardsTable extends Table {
  @override
  String get tableName => 'welding_standards';

  TextColumn get id => text()();

  /// e.g. 'DVS 2207', 'ISO 21307', 'ASTM F2620'
  TextColumn get name => text()();

  /// e.g. 'DVS_2207', 'ISO_21307', 'ASTM_F2620'
  TextColumn get code => text()();

  /// 'butt_fusion' | 'electrofusion'
  TextColumn get weldType => text()();

  TextColumn get description => text().nullable()();
  TextColumn get version => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
