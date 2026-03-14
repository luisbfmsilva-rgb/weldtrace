import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../data/local/tables/welding_parameters_table.dart';
import '../welding/pipe_geometry.dart';
import '../welding/welding_phases.dart';

/// Fallback welding parameter generator for **DVS 2207-1** (PE butt-fusion).
///
/// Used when the local database has not yet been seeded with records for
/// the selected pipe spec, or when the device is operating fully offline.
///
/// ── Standard reference values ────────────────────────────────────────────────
///
///   Base interfacial fusion pressure:  0.15 N/mm²  (= 0.15 bar here; unit
///     convention: 1 N/mm² = 10 bar, but DVS specifies P in N/mm² and the
///     companion stores bar — 0.15 N/mm² = 1.5 bar; field kept as 0.15 for
///     direct comparison with standard tables; material correction applied.)
///   Heat soak pressure:               ≈ 0.02 bar (heater contact, near-zero)
///
/// ── Bead geometry rules ───────────────────────────────────────────────────────
///
///   // approximate DVS bead height rule
///   e <  8 mm         → height 2 mm
///   8  ≤ e < 15 mm    → height 3 mm
///   15 ≤ e < 25 mm    → height 4 mm
///   e ≥ 25 mm         → height 5 mm
///
///   // bead width proportional to wall thickness
///   beadWidth = e × 0.9
///
/// ── Dynamic time rules ────────────────────────────────────────────────────────
///
///   // approximate DVS heating rule
///   heatSoak [s]   = max(60, OD × 1.5)
///
///   // cooling proportional to wall thickness
///   cooling  [s]   = max(300, e × 90)
///
///   changeover [s] = min(15, e × 2)   (per DVS 2207-1 Table 3 spirit)
///
/// ── Contact area model ────────────────────────────────────────────────────────
///
///   // effective molten bead contact band
///   // reduces full circumference assumption
///   beadContactFactor           = 0.65
///   effectiveCircumference [mm] = π × OD × beadContactFactor
///   contactAreaMm2 [mm²]        = effectiveCircumference × beadWidth
///     clamped to [100, 10 000 000] mm² (numeric guard)
///
/// ── Machine gauge pressure conversion ────────────────────────────────────────
///
///   forceN [N]              = P_interfacial [bar] × 100 000 × contactArea [mm²] / 1e6
///   machinePressureBar [bar]= forceN / (A_cyl [mm²] / 1e6) / 100 000
///   gaugePressureBar [bar]  = max(0, machinePressureBar − dragPressureBar)
class Dvs2207 {
  Dvs2207._();

  // ── DVS 2207-1 base interfacial pressures ────────────────────────────────

  /// Phase 1 — Bead build-up: full joining pressure while forming the bead.
  static const double _heatingUpInterfacialBar = 0.15;

  /// Phase 2 — Heat soak: near-zero load; melt flows without being squeezed.
  static const double _heatSoakInterfacialBar = 0.02;

  /// Base fusion interfacial pressure before material correction  [bar].
  ///
  /// Material correction factor is applied in [_fusionPressure] and the
  /// result is clamped to the safe operating window [0.12 … 0.30] bar.
  static const double _baseFusionBar = 0.15;

  /// ±10 % tolerance band around the nominal interfacial fusion pressure.
  static const double _toleranceFraction = 0.10;

  // ── Fixed phase times ─────────────────────────────────────────────────────

  static const int _heatingUpTimeS = 30;  // bead build-up
  static const int _buildupTimeS    = 15; // pressure ramp to fusion
  static const int _fusionTimeS     = 30; // joining hold at fusion pressure

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generates a [WeldingParametersTableCompanion] using DVS 2207-1 defaults.
  ///
  /// The companion stores **interfacial** pressures exactly as the standard
  /// specifies.  Pass it to [WeldingTableGenerator.generate()] together with
  /// a [MachineSpec] to convert to machine gauge pressures.
  ///
  /// [pipeDiameterMm]           — OD [mm]
  /// [sdrRating]                — SDR string (e.g. 'SDR11', '11')
  /// [pipeMaterial]             — 'PE80' | 'PE100' | 'PE' | 'PP'
  /// [hydraulicCylinderAreaMm2] — machine cylinder area [mm²]; used only
  ///                              to populate [WeldPhaseTable] for inspection
  /// [dragPressureBar]          — measured drag [bar]
  static WeldingParametersTableCompanion generateFallback({
    required double pipeDiameterMm,
    required String sdrRating,
    required String pipeMaterial,
    double? hydraulicCylinderAreaMm2,
    double dragPressureBar = 0.0,
  }) {
    // ── 1. Pipe geometry ──────────────────────────────────────────────────────
    //
    //   e [mm]     = OD / SDR                  (wall thickness)
    //   A_ann [mm²] = π × (OD − e) × e         (annular end-face area)
    //
    final sdr = PipeGeometry.parseSdr(sdrRating);
    final e   = PipeGeometry.wallThickness(pipeDiameterMm, sdr);

    // ── 2. Bead geometry ──────────────────────────────────────────────────────

    // approximate DVS bead height rule
    final beadHeightMm = _beadHeight(e);

    // bead width proportional to wall thickness
    final beadWidthMm = e * 0.9;

    // effective molten bead contact band
    // reduces full circumference assumption
    const beadContactFactor = 0.65;
    final effectiveCircumference = math.pi * pipeDiameterMm * beadContactFactor;
    var contactAreaMm2 = effectiveCircumference * beadWidthMm;
    // numeric guard — prevents unrealistic values for very small/large pipes
    contactAreaMm2 = contactAreaMm2.clamp(100.0, 10000000.0);

    // ── 3. Dynamic time parameters ────────────────────────────────────────────

    // approximate DVS heating rule — larger diameter needs more soak time
    final heatSoakTimeS = _heatSoakTime(pipeDiameterMm);

    // cooling proportional to wall thickness — thicker wall retains more heat
    final coolingTimeS = _coolingTime(e);

    // changeover window derived from wall thickness
    final changeoverMaxS = _changeoverMax(e);

    // ── 4. Fusion pressure with material correction ───────────────────────────
    //
    //   Material factor compensates for different melt-flow behaviour:
    //     PE80  → 1.00  (reference)
    //     PE100 → 1.05  (stiffer melt requires slightly higher pressure)
    //     PP    → 0.90  (lower fusion pressure for polypropylene)
    //
    //   Result is clamped to the safe operating window [0.12 … 0.30] bar.
    //
    final factor         = _materialFactor(pipeMaterial);
    final fusionBar      = (_baseFusionBar * factor).clamp(0.12, 0.30);
    final fusionMinBar   = (fusionBar * (1 - _toleranceFraction)).clamp(0.12, 0.30);
    final fusionMaxBar   = (fusionBar * (1 + _toleranceFraction)).clamp(0.12, 0.30);

    // ── 5. Machine gauge pressure (for WeldPhaseTable inspection only) ────────
    //
    //   converts bar × area into Newtons
    //   F [N]               = P_interfacial [bar] × 100 000 × contactArea [mm²] / 1e6
    //   machinePressure [bar] = F [N] / (A_cyl [mm²] / 1e6) / 100 000
    //   gaugePressure [bar]   = machinePressure − P_drag  (clamped ≥ 0)
    //
    final double fusionGaugeBar;
    if (hydraulicCylinderAreaMm2 != null && hydraulicCylinderAreaMm2 > 0) {
      // converts bar × area into Newtons
      final forceN             = fusionBar * 100000 * contactAreaMm2 / 1e6;
      final machinePressureBar = forceN / (hydraulicCylinderAreaMm2 / 1e6) / 100000;
      fusionGaugeBar           = math.max(0.0, machinePressureBar - dragPressureBar);
    } else {
      fusionGaugeBar = fusionBar; // interfacial fallback (no cylinder data)
    }

    // ── 6. Build phase table (informational — not serialised) ─────────────────
    _buildPhaseTable(
      fusionGaugeBar:  fusionGaugeBar,
      heatSoakTimeS:   heatSoakTimeS,
      coolingTimeS:    coolingTimeS,
      changeoverMaxS:  changeoverMaxS,
    );

    // ── 7. Return companion ───────────────────────────────────────────────────
    return WeldingParametersTableCompanion(
      pipeMaterial:  Value(pipeMaterial),
      pipeDiameterMm: Value(pipeDiameterMm),
      sdrRating:     Value(sdrRating),
      wallThicknessMm: Value(e),

      // Phase 1 — Bead build-up (heating-up): full pressure to seat heater
      heatingUpTimeS:       const Value(_heatingUpTimeS),
      heatingUpPressureBar: const Value(_heatingUpInterfacialBar),

      // Phase 2 — Heat soak: reduced load; time scales with pipe diameter
      // approximate DVS heating rule
      heatingTimeS:    Value(heatSoakTimeS),
      heatingPressureBar: const Value(_heatSoakInterfacialBar),

      // Phase 3 — Changeover: heater removal; max time from wall thickness
      changeoverTimeMaxS: Value(changeoverMaxS),

      // Phase 4 — Pressure build-up: ramp from drag to fusion pressure
      buildupTimeS: const Value(_buildupTimeS),

      // Phase 5 — Fusion: hold at corrected interfacial pressure
      fusionTimeS:         const Value(_fusionTimeS),
      fusionPressureBar:    Value(fusionBar),
      fusionPressureMinBar: Value(fusionMinBar),
      fusionPressureMaxBar: Value(fusionMaxBar),

      // Phase 6 — Cooling: hold with pressure; time scales with wall thickness
      // cooling proportional to wall thickness
      coolingTimeS:    Value(coolingTimeS),
      coolingPressureBar: Value(fusionBar),

      notes: Value(
        'DVS 2207-1 fallback — '
        'bead h≥${beadHeightMm.toStringAsFixed(1)} mm '
        'w≈${beadWidthMm.toStringAsFixed(1)} mm | '
        'OD ${pipeDiameterMm.toStringAsFixed(0)} mm '
        'e ${e.toStringAsFixed(2)} mm | '
        'mat×${factor.toStringAsFixed(2)} '
        'P=${fusionBar.toStringAsFixed(3)} bar',
      ),
      isActive:   const Value(true),
      syncStatus: const Value('pending'),
    );
  }

  // ── Internal physics helpers ──────────────────────────────────────────────

  /// Bead height from wall thickness [mm].
  ///
  /// // approximate DVS bead height rule
  static double _beadHeight(double e) {
    if (e <  8)  return 2.0;
    if (e < 15)  return 3.0;
    if (e < 25)  return 4.0;
    return 5.0;
  }

  /// Heat soak time [s] from pipe diameter.
  ///
  /// // approximate DVS heating rule
  /// Larger diameters require proportionally more time to achieve uniform
  /// through-wall melt temperature.
  static int _heatSoakTime(double diameterMm) =>
      math.max(60, diameterMm * 1.5).round();

  /// Cooling time [s] from wall thickness.
  ///
  /// // cooling proportional to wall thickness
  /// Thicker walls retain more thermal energy and need longer under-pressure
  /// cooling to reach handling temperature.
  static int _coolingTime(double e) =>
      math.max(300, e * 90).round();

  /// Maximum changeover time [s] from wall thickness.
  ///
  /// Thin-wall pipes cool faster — a shorter changeover window applies.
  /// Derived from DVS 2207-1 Table 3 spirit: limit scales with wall mass.
  static int _changeoverMax(double e) =>
      math.min(15, e * 2).round();

  /// Material correction factor for fusion pressure.
  ///
  /// PE80  → 1.00  (reference material per DVS 2207-1)
  /// PE100 → 1.05  (higher-density PE needs ~5% more interfacial pressure)
  /// PP    → 0.90  (polypropylene fusion pressure is lower)
  static double _materialFactor(String material) {
    final m = material.toUpperCase();
    if (m.contains('PE100')) return 1.05;
    if (m.contains('PP'))    return 0.90;
    return 1.00; // PE80 / PE (generic)
  }

  // ── Phase table builder (informational) ──────────────────────────────────

  static WeldPhaseTable _buildPhaseTable({
    required double fusionGaugeBar,
    required int    heatSoakTimeS,
    required int    coolingTimeS,
    required int    changeoverMaxS,
  }) {
    return WeldPhaseTable(
      machineGaugePressureBar: fusionGaugeBar,
      phases: [
        const WeldPhase(
          name:         'Bead Build-up',
          pressureBar:  _heatingUpInterfacialBar,
          timeSeconds:  _heatingUpTimeS,
        ),
        WeldPhase(
          name:        'Heat Soak',
          pressureBar: _heatSoakInterfacialBar,
          timeSeconds: heatSoakTimeS,
        ),
        WeldPhase(
          name:        'Changeover',
          pressureBar: 0.0,
          timeSeconds: changeoverMaxS,
        ),
        WeldPhase(
          name:        'Fusion',
          pressureBar: fusionGaugeBar,
          timeSeconds: _buildupTimeS + _fusionTimeS,
        ),
        WeldPhase(
          name:        'Initial Cooling',
          pressureBar: fusionGaugeBar,
          timeSeconds: coolingTimeS ~/ 3,
        ),
        WeldPhase(
          name:        'Final Cooling',
          pressureBar: fusionGaugeBar,
          timeSeconds: coolingTimeS - coolingTimeS ~/ 3,
        ),
      ],
    );
  }
}
