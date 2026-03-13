import 'package:drift/drift.dart';

import '../../data/local/tables/welding_parameters_table.dart';
import '../welding/pipe_geometry.dart';
import '../welding/welding_phases.dart';

/// Fallback welding parameter generator for **ASTM F2620** (HDPE butt-fusion).
///
/// ASTM F2620 governs heat-fusion joining of polyethylene piping.
/// The standard specifies:
///
///   Interfacial fusion pressure:  ~0.20 N/mm²  (2.0 bar; varies with SDR)
///   Heating time:                 ~150 s conservative fallback
///   Changeover time max:          10 s
///   Cooling time:                 ~900 s (varies with wall thickness)
///
/// ── Bead height rule (simplified) ────────────────────────────────────────────
///
///   e < 10 mm   → min bead 2 mm
///   e 10–20 mm  → min bead 3 mm
///   e > 20 mm   → min bead 4 mm
///
///   TODO: confirm bead rule with ASTM F2620 Table X1.
///
/// ── Machine gauge pressure conversion ────────────────────────────────────────
///
///   F [N]          = P_interfacial [bar] × 100 000 × A_pipe [mm²] / 1e6
///   P_gauge [bar]  = P_interfacial × A_pipe / A_cyl + P_drag
class AstmF2620 {
  AstmF2620._();

  // ── ASTM F2620 interfacial pressures ─────────────────────────────────────

  /// Bead build-up phase (heating-up) interfacial pressure [bar].
  static const double _heatingUpInterfacialBar = 0.20;

  /// Heat soak phase: near-zero so melt flows freely.
  static const double _heatSoakInterfacialBar = 0.02;

  /// Fusion / joining hold interfacial pressure [bar].
  static const double _fusionInterfacialBar = 0.20;

  static const double _toleranceFraction = 0.10;

  // ── Time parameters ───────────────────────────────────────────────────────

  static const int _heatingUpTimeS = 40;        // bead build-up
  static const int _heatingTimeS = 150;          // heat soak (ASTM F2620 longer soak)
  static const int _changeoverMaxS = 10;
  static const int _buildupTimeS = 20;           // pressure ramp
  static const int _fusionTimeS = 45;            // joining hold
  static const int _coolingTimeS = 900;          // conservative cooling hold

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generates a [WeldingParametersTableCompanion] using ASTM F2620 defaults.
  ///
  /// The companion stores **interfacial** pressures.  Pass it to
  /// [WeldingTableGenerator.generate()] with a [MachineSpec] to convert
  /// to machine gauge pressures.
  ///
  /// [pipeDiameterMm]           — OD [mm]
  /// [sdrRating]                — SDR string (e.g. '11', 'SDR17')
  /// [pipeMaterial]             — 'PE' | 'HDPE' | 'PP'
  /// [hydraulicCylinderAreaMm2] — used only to populate [WeldPhaseTable]
  /// [dragPressureBar]          — measured drag [bar]
  static WeldingParametersTableCompanion generateFallback({
    required double pipeDiameterMm,
    required String sdrRating,
    required String pipeMaterial,
    double? hydraulicCylinderAreaMm2,
    double dragPressureBar = 0.0,
  }) {
    // ── 1. Geometry ───────────────────────────────────────────────────────────

    final sdr = PipeGeometry.parseSdr(sdrRating);
    final e = PipeGeometry.wallThickness(pipeDiameterMm, sdr);
    final aPipe = PipeGeometry.pipeAnnulusArea(pipeDiameterMm, e);

    // ── 2. Bead size estimate ─────────────────────────────────────────────────
    // TODO: confirm bead rule with ASTM F2620 Table X1.
    final beadHeightMm = _beadHeight(e);

    // ── 3. Machine gauge conversion (for WeldPhaseTable inspection only) ─────
    //
    //   F [N]          = P_interfacial [bar] × 100 000 × A_pipe [mm²] / 1e6
    //   P_gauge [bar]  = P_interfacial × A_pipe / A_cyl + P_drag
    //
    final double fusionGaugeBar;
    if (hydraulicCylinderAreaMm2 != null && hydraulicCylinderAreaMm2 > 0) {
      final forceN = _fusionInterfacialBar * 100000 * aPipe / 1e6;
      final machinePressureBar =
          forceN / (hydraulicCylinderAreaMm2 / 1e6) / 100000;
      fusionGaugeBar = machinePressureBar + dragPressureBar;
    } else {
      fusionGaugeBar = _fusionInterfacialBar;
    }

    _buildPhaseTable(fusionGaugeBar);

    // ── 4. Return companion ───────────────────────────────────────────────────

    return WeldingParametersTableCompanion(
      pipeMaterial: Value(pipeMaterial),
      pipeDiameterMm: Value(pipeDiameterMm),
      sdrRating: Value(sdrRating),
      wallThicknessMm: Value(e),

      // Phase 1: Bead build-up
      heatingUpTimeS: const Value(_heatingUpTimeS),
      heatingUpPressureBar: const Value(_heatingUpInterfacialBar),

      // Phase 2: Heat soak
      heatingTimeS: const Value(_heatingTimeS),
      heatingPressureBar: const Value(_heatSoakInterfacialBar),

      // Phase 3: Changeover
      changeoverTimeMaxS: const Value(_changeoverMaxS),

      // Phase 4: Pressure build-up
      buildupTimeS: const Value(_buildupTimeS),

      // Phase 5: Fusion
      fusionTimeS: const Value(_fusionTimeS),
      fusionPressureBar: const Value(_fusionInterfacialBar),
      fusionPressureMinBar:
          const Value(_fusionInterfacialBar * (1 - _toleranceFraction)),
      fusionPressureMaxBar:
          const Value(_fusionInterfacialBar * (1 + _toleranceFraction)),

      // Phase 6: Cooling
      coolingTimeS: const Value(_coolingTimeS),
      coolingPressureBar: const Value(_fusionInterfacialBar),

      notes: Value(
        'ASTM F2620 fallback — bead ≥ ${beadHeightMm.toStringAsFixed(1)} mm, '
        'OD ${pipeDiameterMm.toStringAsFixed(0)} mm / e '
        '${e.toStringAsFixed(2)} mm',
      ),
      isActive: const Value(true),
      syncStatus: const Value('pending'),
    );
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static double _beadHeight(double e) {
    if (e < 10) return 2.0;
    if (e <= 20) return 3.0;
    return 4.0;
  }

  static WeldPhaseTable _buildPhaseTable(double fusionGaugeBar) {
    return WeldPhaseTable(
      machineGaugePressureBar: fusionGaugeBar,
      phases: [
        const WeldPhase(
            name: 'Bead Build-up',
            pressureBar: _heatingUpInterfacialBar,
            timeSeconds: _heatingUpTimeS),
        const WeldPhase(
            name: 'Heat Soak',
            pressureBar: _heatSoakInterfacialBar,
            timeSeconds: _heatingTimeS),
        const WeldPhase(
            name: 'Changeover', pressureBar: 0.0, timeSeconds: _changeoverMaxS),
        WeldPhase(
            name: 'Fusion',
            pressureBar: fusionGaugeBar,
            timeSeconds: _buildupTimeS + _fusionTimeS),
        WeldPhase(
            name: 'Initial Cooling',
            pressureBar: fusionGaugeBar,
            timeSeconds: _coolingTimeS ~/ 3),
        WeldPhase(
            name: 'Final Cooling',
            pressureBar: fusionGaugeBar,
            timeSeconds: _coolingTimeS - _coolingTimeS ~/ 3),
      ],
    );
  }
}
