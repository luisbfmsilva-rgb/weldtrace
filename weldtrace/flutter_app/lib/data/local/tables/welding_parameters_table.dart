import 'package:drift/drift.dart';

/// Mirrors the cloud `welding_parameters` table.
/// Each row defines all phase durations and pressures for a specific
/// standard × pipe_material × pipe_diameter × SDR combination.
@DataClassName('WeldingParameterRecord')
class WeldingParametersTable extends Table {
  @override
  String get tableName => 'welding_parameters';

  TextColumn get id => text()();
  TextColumn get standardId => text()();     // FK → welding_standards.id

  /// 'PE' | 'PP'
  TextColumn get pipeMaterial => text()();

  /// Nominal outer diameter in mm (e.g. 63, 90, 110, 160, 200, 250, 315, 400)
  RealColumn get pipeDiameterMm => real()();

  /// SDR ratio as text (e.g. '11', '17', '17.6', '26')
  TextColumn get sdrRating => text()();

  /// Corresponding wall thickness in mm (informational)
  RealColumn get wallThicknessMm => real().nullable()();

  // ── Ambient temperature operating window ──────────────────────────────────
  RealColumn get ambientTempMinCelsius => real().withDefault(const Constant(-15.0))();
  RealColumn get ambientTempMaxCelsius => real().withDefault(const Constant(50.0))();

  // ── Butt-fusion phase parameters ──────────────────────────────────────────

  // 1. Heating-up (drag pressure applied, heater contact)
  IntColumn get heatingUpTimeS => integer().nullable()();
  RealColumn get heatingUpPressureBar => real().nullable()();

  // 2. Heating (bead formation time at reduced / no axial force)
  IntColumn get heatingTimeS => integer().nullable()();
  RealColumn get heatingPressureBar => real().nullable()();

  // 3. Changeover (heater removal; max time allowed)
  IntColumn get changeoverTimeMaxS => integer().nullable()();

  // 4. Pressure build-up (ramp to fusion pressure)
  IntColumn get buildupTimeS => integer().nullable()();

  // 5. Fusion / joining (hold at full fusion pressure)
  IntColumn get fusionTimeS => integer().nullable()();
  RealColumn get fusionPressureBar => real().nullable()();
  RealColumn get fusionPressureMinBar => real().nullable()();
  RealColumn get fusionPressureMaxBar => real().nullable()();

  // 6. Cooling (hold with fusion pressure, no movement)
  IntColumn get coolingTimeS => integer().nullable()();
  RealColumn get coolingPressureBar => real().nullable()();

  // ── Electrofusion parameters ───────────────────────────────────────────────
  IntColumn get efWeldingTimeS => integer().nullable()();
  RealColumn get efWeldingVoltage => real().nullable()();
  IntColumn get efCoolingTimeS => integer().nullable()();

  // ── Tolerance fields ──────────────────────────────────────────────────────
  RealColumn get heatingTempNominalCelsius => real().nullable()();
  RealColumn get heatingTempMinCelsius => real().nullable()();
  RealColumn get heatingTempMaxCelsius => real().nullable()();

  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
