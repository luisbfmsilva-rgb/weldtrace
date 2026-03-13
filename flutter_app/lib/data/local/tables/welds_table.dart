import 'package:drift/drift.dart';

/// Stores individual weld sessions.
/// New welds are created locally with sync_status = 'pending'
/// and uploaded to the cloud on next sync.
/// Completed welds are IMMUTABLE — no UPDATE is permitted after status = 'completed'.
@DataClassName('WeldRecord')
class WeldsTable extends Table {
  @override
  String get tableName => 'welds';

  TextColumn get id => text()();            // UUID, generated locally
  TextColumn get projectId => text()();
  TextColumn get machineId => text()();
  TextColumn get operatorId => text()();

  // 'electrofusion' | 'butt_fusion'
  TextColumn get weldType => text()();

  // 'in_progress' | 'completed' | 'cancelled' | 'failed'
  TextColumn get status => text().withDefault(const Constant('in_progress'))();

  TextColumn get pipeMaterial => text()();
  RealColumn get pipeDiameter => real()();
  TextColumn get pipeSdr => text().nullable()();
  RealColumn get pipeWallThickness => real().nullable()();
  RealColumn get ambientTemperature => real().nullable()();
  RealColumn get gpsLat => real().nullable()();
  RealColumn get gpsLng => real().nullable()();

  // 'DVS_2207' | 'ISO_21307' | 'ASTM_F2620'
  TextColumn get standardUsed => text().nullable()();
  TextColumn get standardId => text().nullable()();

  BoolColumn get isCancelled => boolean().withDefault(const Constant(false))();
  TextColumn get cancelReason => text().nullable()();
  DateTimeColumn get cancelTimestamp => dateTime().nullable()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))(); // pending | synced | conflict
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  // ── Weld traceability — added in schema v4 ────────────────────────────────

  /// SHA-256 hex digest computed from the pressure × time curve + weld
  /// metadata.  Null until the weld is completed.
  TextColumn get traceSignature => text().nullable()();

  /// Full pressure × time curve serialised as a JSON array of
  /// WeldTracePoint objects.  Null until the weld is completed.
  TextColumn get traceCurveJson => text().nullable()();

  /// PDF welding report as raw bytes.  Null until the weld is completed.
  BlobColumn get tracePdf => blob().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
