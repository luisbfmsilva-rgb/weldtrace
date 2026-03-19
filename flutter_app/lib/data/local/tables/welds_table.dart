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
  /// WeldTracePoint objects.  Kept for backward compatibility with schema v4/v5.
  /// New records should prefer [traceCurveCompressed].
  TextColumn get traceCurveJson => text().nullable()();

  /// PDF welding report as raw bytes.  Null until the weld is completed.
  BlobColumn get tracePdf => blob().nullable()();

  // ── Weld traceability — added in schema v5 ────────────────────────────────

  /// Indicates the quality of the recorded trace data.
  ///
  /// 'OK'               — curve has ≥ 2 samples, considered valid
  /// 'LOW_SAMPLE_COUNT' — curve has < 2 samples; signature still generated
  ///                      but chart will show "No data recorded"
  ///
  /// Null for welds completed before schema v5 or before the traceability
  /// feature was enabled.
  TextColumn get traceQuality => text().nullable()();

  // ── Weld traceability — added in schema v6 ────────────────────────────────

  /// Gzip-compressed pressure × time curve (replaces [traceCurveJson] for new
  /// records).  Stored as raw bytes via a BLOB column.  Typical compression
  /// ratio is 10 : 1 for large curves (5 000 samples ≈ 400 kB → ~40 kB).
  BlobColumn get traceCurveCompressed => blob().nullable()();

  // ── Weld certification — added in schema v7 ───────────────────────────────

  /// Globally-unique joint identifier generated with UUID v7 at weld
  /// completion.  Included in the QR verification payload and the local
  /// certification ledger.  Null for welds completed before schema v7.
  TextColumn get jointId => text().nullable()();

  // ── Resume support — added in schema v9 ──────────────────────────────────

  /// JSON-encoded List<PhaseParameters> that allows resuming an in-progress
  /// weld session without re-running setup.  Serialised using
  /// PhaseParameters.toJson() at session start.
  TextColumn get phasesJson => text().nullable()();

  /// JSON-encoded WeldSessionArgs metadata (machine name, area, operator, etc.)
  /// so the session can be fully reconstructed when the user resumes.
  TextColumn get sessionMetaJson => text().nullable()();

  // ── Completion flags — added in schema v9 ────────────────────────────────

  /// True when the operator ended cooling before the nominal time elapsed.
  BoolColumn get coolingIncomplete =>
      boolean().nullable().withDefault(const Constant(false))();

  /// Elapsed seconds of the bead-formation (heatingUp) phase.
  IntColumn get beadFormationSeconds => integer().nullable()();

  /// Actual bead height measured by the operator [mm].  Optional.
  RealColumn get beadHeightMeasuredMm => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
