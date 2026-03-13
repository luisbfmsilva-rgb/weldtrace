import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../data/local/tables/welding_parameters_table.dart';
import '../welding/pipe_geometry.dart';
import '../welding/welding_phases.dart';

/// Fallback welding parameter generator for **ASTM F2620** (HDPE butt-fusion).
///
/// ASTM F2620 governs heat-fusion joining of polyethylene piping.
/// The standard specifies:
///
///   Base interfacial fusion pressure:  0.20 bar
///   Heating time:                      dynamic — max(60, OD × 1.5) s
///   Changeover time max:               dynamic — min(15, e × 2) s
///   Cooling time:                      dynamic — max(300, e × 90) s
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
///   changeover [s] = min(15, e × 2)
///
/// ── Machine gauge pressure conversion ────────────────────────────────────────
///
///   F [N]          = P_interfacial [bar] × 100 000 × A_pipe [mm²] / 1e6
///   P_gauge [bar]  = P_interfacial × A_pipe / A_cyl + P_drag
class AstmF2620 {
  AstmF2620._();

  // ── ASTM F2620 base interfacial pressures ────────────────────────────────

  /// Phase 1 — Bead build-up: full joining pressure.
  static const double _heatingUpInterfacialBar = 0.20;

  /// Phase 2 — Heat soak: near-zero load.
  static const double _heatSoakInterfacialBar = 0.02;

  /// Base fusion interfacial pressure before material correction  [bar].
  ///
  /// ASTM F2620 prescribes a slightly higher interfacial pressure than
  /// DVS 2207 (0.20 vs 0.15 bar) reflecting differences in pipe-end
  /// preparation and machine compliance requirements in the US market.
  static const double _baseFusionBar = 0.20;

  /// ±10 % tolerance band around the nominal fusion pressure.
  static const double _toleranceFraction = 0.10;

  // ── Fixed phase times ─────────────────────────────────────────────────────

  static const int _heatingUpTimeS = 40;  // bead build-up
  static const int _buildupTimeS    = 20; // pressure ramp (ASTM allows longer ramp)
  static const int _fusionTimeS     = 45; // joining hold

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generates a [WeldingParametersTableCompanion] using ASTM F2620 defaults.
  ///
  /// The companion stores **interfacial** pressures.  Pass it to
  /// [WeldingTableGenerator.generate()] with a [MachineSpec] to convert
  /// to machine gauge pressures.
  ///
  /// [pipeDiameterMm]           — OD [mm]
  /// [sdrRating]                — SDR string (e.g. '11', 'SDR17')
  /// [pipeMaterial]             — 'PE80' | 'PE100' | 'HDPE' | 'PE' | 'PP'
  /// [hydraulicCylinderAreaMm2] — used only to populate [WeldPhaseTable]
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
    //   e [mm]      = OD / SDR                 (wall thickness)
    //   A_ann [mm²] = π × (OD − e) × e        (annular end-face area)
    //
    final sdr   = PipeGeometry.parseSdr(sdrRating);
    final e     = PipeGeometry.wallThickness(pipeDiameterMm, sdr);
    final aPipe = PipeGeometry.pipeAnnulusArea(pipeDiameterMm, e);

    // ── 2. Bead geometry ──────────────────────────────────────────────────────

    // approximate DVS bead height rule
    final beadHeightMm = _beadHeight(e);

    // bead width proportional to wall thickness
    final beadWidthMm = e * 0.9;

    // ── 3. Dynamic time parameters ────────────────────────────────────────────

    // approximate DVS heating rule
    final heatSoakTimeS = _heatSoakTime(pipeDiameterMm);

    // cooling proportional to wall thickness
    final coolingTimeS = _coolingTime(e);

    final changeoverMaxS = _changeoverMax(e);

    // ── 4. Fusion pressure with material correction ───────────────────────────
    //
    //   Material factor compensates for different melt rheology:
    //     PE80 / HDPE → 1.00 (reference)
    //     PE100       → 1.05 (higher-density polyethylene)
    //     PP          → 0.90 (polypropylene — lower fusion pressure)
    //
    //   Result clamped to safe operating window [0.12 … 0.30] bar.
    //
    final factor       = _materialFactor(pipeMaterial);
    final fusionBar    = (_baseFusionBar * factor).clamp(0.12, 0.30);
    final fusionMinBar = (fusionBar * (1 - _toleranceFraction)).clamp(0.12, 0.30);
    final fusionMaxBar = (fusionBar * (1 + _toleranceFraction)).clamp(0.12, 0.30);

    // ── 5. Machine gauge pressure (for WeldPhaseTable inspection only) ────────
    //
    //   F [N]          = P_interfacial [bar] × 100 000 × A_pipe [mm²] / 1e6
    //   P_gauge [bar]  = P_interfacial × A_pipe / A_cyl + P_drag
    //
    final double fusionGaugeBar;
    if (hydraulicCylinderAreaMm2 != null && hydraulicCylinderAreaMm2 > 0) {
      final forceN             = fusionBar * 100000 * aPipe / 1e6;
      final machinePressureBar = forceN / (hydraulicCylinderAreaMm2 / 1e6) / 100000;
      fusionGaugeBar           = machinePressureBar + dragPressureBar;
    } else {
      fusionGaugeBar = fusionBar;
    }

    _buildPhaseTable(
      fusionGaugeBar: fusionGaugeBar,
      heatSoakTimeS:  heatSoakTimeS,
      coolingTimeS:   coolingTimeS,
      changeoverMaxS: changeoverMaxS,
    );

    // ── 6. Return companion ───────────────────────────────────────────────────

    return WeldingParametersTableCompanion(
      pipeMaterial:   Value(pipeMaterial),
      pipeDiameterMm: Value(pipeDiameterMm),
      sdrRating:      Value(sdrRating),
      wallThicknessMm: Value(e),

      // Phase 1 — Bead build-up (ASTM uses slightly longer build-up time)
      heatingUpTimeS:       const Value(_heatingUpTimeS),
      heatingUpPressureBar: const Value(_heatingUpInterfacialBar),

      // Phase 2 — Heat soak: time scales with pipe diameter
      // approximate DVS heating rule
      heatingTimeS:    Value(heatSoakTimeS),
      heatingPressureBar: const Value(_heatSoakInterfacialBar),

      // Phase 3 — Changeover
      changeoverTimeMaxS: Value(changeoverMaxS),

      // Phase 4 — Pressure build-up (longer ramp per ASTM practice)
      buildupTimeS: const Value(_buildupTimeS),

      // Phase 5 — Fusion: corrected + clamped interfacial pressure
      fusionTimeS:         const Value(_fusionTimeS),
      fusionPressureBar:    Value(fusionBar),
      fusionPressureMinBar: Value(fusionMinBar),
      fusionPressureMaxBar: Value(fusionMaxBar),

      // Phase 6 — Cooling: proportional to wall thickness
      // cooling proportional to wall thickness
      coolingTimeS:    Value(coolingTimeS),
      coolingPressureBar: Value(fusionBar),

      notes: Value(
        'ASTM F2620 fallback — '
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

  // approximate DVS bead height rule
  static double _beadHeight(double e) {
    if (e <  8)  return 2.0;
    if (e < 15)  return 3.0;
    if (e < 25)  return 4.0;
    return 5.0;
  }

  // approximate DVS heating rule
  static int _heatSoakTime(double diameterMm) =>
      math.max(60, diameterMm * 1.5).round();

  // cooling proportional to wall thickness
  static int _coolingTime(double e) =>
      math.max(300, e * 90).round();

  static int _changeoverMax(double e) =>
      math.min(15, e * 2).round();

  /// Material correction factor for fusion pressure.
  ///
  /// PE80 / HDPE → 1.00  (reference)
  /// PE100       → 1.05  (higher-density PE)
  /// PP          → 0.90  (polypropylene)
  static double _materialFactor(String material) {
    final m = material.toUpperCase();
    if (m.contains('PE100')) return 1.05;
    if (m.contains('PP'))    return 0.90;
    return 1.00; // PE80 / HDPE / PE (generic)
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
          name:        'Bead Build-up',
          pressureBar: _heatingUpInterfacialBar,
          timeSeconds: _heatingUpTimeS,
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
