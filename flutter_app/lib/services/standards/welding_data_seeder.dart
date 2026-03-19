import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database/app_database.dart';

/// Seeds the local SQLite database with factory welding standards and
/// pre-computed parameter rows derived from DVS 2207-1, ISO 21307, and
/// ASTM F2620.
///
/// The seeder runs once on app startup and only inserts rows if the
/// welding_standards table is empty (i.e., no cloud sync has been
/// performed yet and no prior seed exists).
///
/// Parameters follow the interfacial pressure convention used by
/// [WeldingTableGenerator]: all pressure values are stored in **bar**
/// as interfacial (pipe-side) pressures.  The generator converts them
/// to machine gauge pressures using the hydraulic cylinder area.
class WeldingDataSeeder {
  WeldingDataSeeder._();

  static const _uuid = Uuid();

  // ── Standard IDs (stable so re-seeding is idempotent) ─────────────────────
  static const _dvs2207Id  = 'std-dvs-2207-butt';
  static const _iso21307Id = 'std-iso-21307-butt';
  static const _astmF2620Id = 'std-astm-f2620-butt';

  // ── DVS 2207 interfacial pressures [bar] ─────────────────────────────────
  // See Dvs2207 class for reference values.
  static const _heatingUpBar   = 0.15;  // Phase 1 — bead build-up
  static const _heatSoakBar    = 0.02;  // Phase 2 — heat soak
  static const _toleranceFrac  = 0.10;  // ±10 % tolerance band

  /// Returns true when seeding was performed (DB was empty).
  static Future<bool> seedIfNeeded(AppDatabase db) async {
    final existing = await db.weldingParametersDao.getAllStandards();
    if (existing.isNotEmpty) return false;

    await _seedStandards(db);
    await _seedParameters(db);
    return true;
  }

  // ── Standards ─────────────────────────────────────────────────────────────

  static Future<void> _seedStandards(AppDatabase db) async {
    final now = DateTime.now();
    await db.weldingParametersDao.upsertAllStandards([
      WeldingStandardsTableCompanion.insert(
        id:          _dvs2207Id,
        name:        'DVS 2207-1',
        code:        'DVS_2207',
        weldType:    'butt_fusion',
        description: const Value('German standard for PE/PP butt-fusion welding (Heizelementstumpfschweißen)'),
        version:     const Value('2015'),
        isActive:    const Value(true),
        createdAt:   Value(now),
        updatedAt:   Value(now),
      ),
      WeldingStandardsTableCompanion.insert(
        id:          _iso21307Id,
        name:        'ISO 21307',
        code:        'ISO_21307',
        weldType:    'butt_fusion',
        description: const Value('International standard for PE butt-fusion welding'),
        version:     const Value('2017'),
        isActive:    const Value(true),
        createdAt:   Value(now),
        updatedAt:   Value(now),
      ),
      WeldingStandardsTableCompanion.insert(
        id:          _astmF2620Id,
        name:        'ASTM F2620',
        code:        'ASTM_F2620',
        weldType:    'butt_fusion',
        description: const Value('Standard practice for heat fusion of PE pipe (North America)'),
        version:     const Value('2013'),
        isActive:    const Value(true),
        createdAt:   Value(now),
        updatedAt:   Value(now),
      ),
    ]);
  }

  // ── Parameters ────────────────────────────────────────────────────────────

  static Future<void> _seedParameters(AppDatabase db) async {
    final rows = <WeldingParametersTableCompanion>[];

    // Pipe diameters [mm] and their common SDR ratings
    const specs = <(double, String)>[
      (32,   '11'), (32,   '17'),
      (40,   '11'), (40,   '17'),
      (50,   '11'), (50,   '17'),
      (63,   '11'), (63,   '17'),
      (75,   '11'), (75,   '17'),
      (90,   '11'), (90,   '17'),
      (110,  '11'), (110,  '17'),
      (125,  '11'), (125,  '17'),
      (160,  '11'), (160,  '17'),
      (200,  '11'), (200,  '17'),
      (250,  '11'), (250,  '17'),
      (315,  '11'), (315,  '17'),
      (400,  '11'), (400,  '17'),
      (500,  '11'), (500,  '17'),
    ];

    const materials = ['PE80', 'PE100', 'PP'];
    const standardIds = [_dvs2207Id, _iso21307Id, _astmF2620Id];

    for (final stdId in standardIds) {
      for (final material in materials) {
        for (final (od, sdr) in specs) {
          rows.add(_buildRow(
            standardId: stdId,
            pipeMaterial: material,
            pipeDiameterMm: od,
            sdrRating: sdr,
          ));
        }
      }
    }

    await db.weldingParametersDao.upsertAllParameters(rows);
  }

  // ── Row builder ────────────────────────────────────────────────────────────

  static WeldingParametersTableCompanion _buildRow({
    required String standardId,
    required String pipeMaterial,
    required double pipeDiameterMm,
    required String sdrRating,
  }) {
    final sdr    = double.tryParse(sdrRating) ?? 11.0;
    final e      = pipeDiameterMm / sdr;         // wall thickness [mm]
    final now    = DateTime.now();

    // ── Phase times (DVS 2207 formulas) ──────────────────────────────────
    // Heating-up: fixed 30 s bead build-up
    const heatingUpTimeS    = 30;
    // Heat soak: max(60, OD × 1.5) — per DVS 2207-1 Table 3
    final heatingTimeS      = math.max(60, (pipeDiameterMm * 1.5).round());
    // Changeover: min(15, e × 2) — table 3 spirit
    final changeoverTimeMaxS = math.min(15, (e * 2).ceil());
    // Build-up: 15 s default
    const buildupTimeS      = 15;
    // Fusion hold: min(60, max(30, e × 10)) — approximately equal to heat soak
    final fusionTimeS       = math.max(30, (e * 10).round());
    // Cooling: max(300, e × 90) — per DVS comment
    final coolingTimeS      = math.max(300, (e * 90).round());

    // ── Material correction on fusion pressure ────────────────────────────
    // PE80: 0.13 bar, PE100: 0.15 bar, PP: 0.12 bar (all interfacial)
    final fusionP = switch (pipeMaterial) {
      'PE80' => 0.13,
      'PE100' => 0.15,
      'PP'   => 0.12,
      _      => 0.15,
    };
    final fusionPMin  = fusionP * (1 - _toleranceFrac);
    final fusionPMax  = fusionP * (1 + _toleranceFrac);

    // Heating temp per material
    final (tempMin, tempNom, tempMax) = switch (pipeMaterial) {
      'PP'   => (200.0, 210.0, 220.0),
      _      => (200.0, 210.0, 225.0), // PE80 / PE100
    };

    return WeldingParametersTableCompanion.insert(
      id:             _uuid.v4(),
      standardId:     standardId,
      pipeMaterial:   pipeMaterial,
      pipeDiameterMm: pipeDiameterMm,
      sdrRating:      sdrRating,
      wallThicknessMm: Value(double.parse(e.toStringAsFixed(2))),

      // ── Times ──────────────────────────────────────────────────────────
      heatingUpTimeS:     Value(heatingUpTimeS),
      heatingTimeS:       Value(heatingTimeS),
      changeoverTimeMaxS: Value(changeoverTimeMaxS),
      buildupTimeS:       Value(buildupTimeS),
      fusionTimeS:        Value(fusionTimeS),
      coolingTimeS:       Value(coolingTimeS),

      // ── Interfacial pressures [bar] ────────────────────────────────────
      heatingUpPressureBar: Value(_heatingUpBar),
      heatingPressureBar:   Value(_heatSoakBar),
      fusionPressureBar:    Value(fusionP),
      fusionPressureMinBar: Value(fusionPMin),
      fusionPressureMaxBar: Value(fusionPMax),
      coolingPressureBar:   Value(fusionP), // hold at fusion pressure during cooling

      // ── Heating temperature ────────────────────────────────────────────
      heatingTempMinCelsius:     Value(tempMin),
      heatingTempNominalCelsius: Value(tempNom),
      heatingTempMaxCelsius:     Value(tempMax),

      isActive:   const Value(true),
      createdAt:  Value(now),
      updatedAt:  Value(now),
      syncStatus: const Value('local_seed'),
    );
  }
}
