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
///   Interfacial fusion pressure:  0.15 N/mm²  (= 1.5 bar)
///   Heat soak pressure:           ≈ 0.02 N/mm² (heater contact, near-zero)
///   Heating time:                 ~ 10 s per mm of wall thickness (fallback 120 s)
///   Changeover time max:          per DVS 2207-1 Table 3 (see WeldingTableGenerator)
///   Cooling time:                 ~ 720 s conservative fallback
///
/// ── Bead height rule (simplified) ────────────────────────────────────────────
///
///   e < 10 mm   → min bead 2 mm
///   e 10–20 mm  → min bead 3 mm
///   e > 20 mm   → min bead 4 mm
///
///   TODO: confirm bead rule with DVS 2207 Table 4 values for each diameter.
///
/// ── Machine gauge pressure conversion ────────────────────────────────────────
///
///   F [N]          = P_interfacial [bar] × 100 000 [Pa/bar] × A_pipe [mm²] / 1e6
///   P_gauge [bar]  = F [N] / (A_cyl [mm²] / 1e6) / 100 000 + P_drag [bar]
///                  = P_interfacial × A_pipe / A_cyl + P_drag
class Dvs2207 {
  Dvs2207._();

  // ── DVS 2207-1 standard interfacial pressures ─────────────────────────────

  /// Phase 1 — Bead build-up: full joining pressure applied while pushing
  /// pipe against heater to form the initial bead.
  static const double _heatingUpInterfacialBar = 0.15;

  /// Phase 2 — Heat soak: pressure reduced to near-zero so the melt can
  /// flow freely without being squeezed away.
  static const double _heatSoakInterfacialBar = 0.02;

  /// Phase 4–5 — Fusion / joining hold: standard joining pressure.
  static const double _fusionInterfacialBar = 0.15;

  /// Tolerance band: ±10 % around the nominal interfacial pressure.
  static const double _toleranceFraction = 0.10;

  // ── Time parameters (safe fallbacks) ─────────────────────────────────────

  static const int _heatingUpTimeS = 30;       // bead build-up
  static const int _heatSoakTimeS = 120;        // heat soak (heating_time_s column)
  static const int _changeoverMaxS = 10;        // heater removal
  static const int _buildupTimeS = 15;          // pressure ramp
  static const int _fusionTimeS = 30;           // joining hold
  static const int _coolingTimeS = 720;         // conservative cooling hold

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generates a [WeldingParametersTableCompanion] using DVS 2207-1 defaults.
  ///
  /// The companion stores **interfacial** pressures exactly as the standard
  /// specifies.  Pass it to [WeldingTableGenerator.generate()] together with
  /// a [MachineSpec] to convert to machine gauge pressures.
  ///
  /// [pipeDiameterMm]           — OD [mm]
  /// [sdrRating]                — SDR string (e.g. 'SDR11', '11')
  /// [pipeMaterial]             — 'PE' | 'PP'
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
    // ── 1. Geometry ───────────────────────────────────────────────────────────

    final sdr = PipeGeometry.parseSdr(sdrRating);
    final e = PipeGeometry.wallThickness(pipeDiameterMm, sdr);
    final aPipe = PipeGeometry.pipeAnnulusArea(pipeDiameterMm, e);

    // ── 2. Bead size estimate (simplified DVS rule) ───────────────────────────
    // TODO: confirm bead rule with DVS 2207 Table 4 values for each diameter.
    final beadHeightMm = _beadHeight(e);

    // ── 3. Machine gauge conversion (for WeldPhaseTable inspection only) ─────
    //
    //   F [N] = P_interfacial [bar] × 100 000 × A_pipe [mm²] / 1e6
    //   P_gauge [bar] = P_interfacial × A_pipe / A_cyl + P_drag
    //
    final double fusionGaugeBar;
    if (hydraulicCylinderAreaMm2 != null && hydraulicCylinderAreaMm2 > 0) {
      final forceN = _fusionInterfacialBar * 100000 * aPipe / 1e6;
      final machinePressureBar =
          forceN / (hydraulicCylinderAreaMm2 / 1e6) / 100000;
      fusionGaugeBar = machinePressureBar + dragPressureBar;
    } else {
      fusionGaugeBar = _fusionInterfacialBar; // interfacial fallback
    }

    // ── 4. Build phase table (informational) ─────────────────────────────────
    // Stored in-memory for callers that need to inspect the phase sequence.
    // Not serialised into the companion — use WeldingTableGenerator for that.
    _buildPhaseTable(aPipe, fusionGaugeBar);

    // ── 5. Return companion (interfacial pressures) ───────────────────────────
    return WeldingParametersTableCompanion(
      // Identity — caller must supply a real UUID; AbsentValue here means the
      // field will be absent (not inserted) unless the caller overrides it.
      // Callers that persist this companion must set id + standardId first.

      pipeMaterial: Value(pipeMaterial),
      pipeDiameterMm: Value(pipeDiameterMm),
      sdrRating: Value(sdrRating),
      wallThicknessMm: Value(e),

      // ── Phase 1: Bead build-up (heating-up) ──────────────────────────────
      heatingUpTimeS: const Value(_heatingUpTimeS),
      heatingUpPressureBar: const Value(_heatingUpInterfacialBar),

      // ── Phase 2: Heat soak ────────────────────────────────────────────────
      heatingTimeS: const Value(_heatSoakTimeS),
      heatingPressureBar: const Value(_heatSoakInterfacialBar),

      // ── Phase 3: Changeover (heater removal) ──────────────────────────────
      changeoverTimeMaxS: const Value(_changeoverMaxS),

      // ── Phase 4: Pressure build-up ────────────────────────────────────────
      buildupTimeS: const Value(_buildupTimeS),

      // ── Phase 5: Fusion ───────────────────────────────────────────────────
      fusionTimeS: const Value(_fusionTimeS),
      fusionPressureBar: const Value(_fusionInterfacialBar),
      fusionPressureMinBar:
          Value(_fusionInterfacialBar * (1 - _toleranceFraction)),
      fusionPressureMaxBar:
          Value(_fusionInterfacialBar * (1 + _toleranceFraction)),

      // ── Phase 6: Cooling ──────────────────────────────────────────────────
      coolingTimeS: const Value(_coolingTimeS),
      coolingPressureBar: const Value(_fusionInterfacialBar),

      // ── Misc ──────────────────────────────────────────────────────────────
      notes: Value(
        'DVS 2207-1 fallback — bead ≥ ${beadHeightMm.toStringAsFixed(1)} mm, '
        'OD ${pipeDiameterMm.toStringAsFixed(0)} mm / e '
        '${e.toStringAsFixed(2)} mm',
      ),
      isActive: const Value(true),
      syncStatus: const Value('pending'),
    );
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  /// Simplified bead height estimate from wall thickness.
  ///
  /// Based on DVS 2207-1 recommendations for initial bead formation.
  /// TODO: confirm bead rule with DVS 2207 Table 4 values for each diameter.
  static double _beadHeight(double wallThicknessMm) {
    if (wallThicknessMm < 10) return 2.0;
    if (wallThicknessMm <= 20) return 3.0;
    return 4.0;
  }

  /// Assembles the six DVS 2207 phases for informational / inspection use.
  static WeldPhaseTable _buildPhaseTable(
      double pipeAnnulusAreaMm2, double fusionGaugeBar) {
    return WeldPhaseTable(
      machineGaugePressureBar: fusionGaugeBar,
      phases: [
        const WeldPhase(
          name: 'Bead Build-up',
          pressureBar: _heatingUpInterfacialBar,
          timeSeconds: _heatingUpTimeS,
        ),
        const WeldPhase(
          name: 'Heat Soak',
          pressureBar: _heatSoakInterfacialBar,
          timeSeconds: _heatSoakTimeS,
        ),
        const WeldPhase(
          name: 'Changeover',
          pressureBar: 0.0,
          timeSeconds: _changeoverMaxS,
        ),
        WeldPhase(
          name: 'Fusion',
          pressureBar: fusionGaugeBar,
          timeSeconds: _buildupTimeS + _fusionTimeS,
        ),
        WeldPhase(
          name: 'Initial Cooling',
          pressureBar: fusionGaugeBar,
          timeSeconds: _coolingTimeS ~/ 3,
        ),
        WeldPhase(
          name: 'Final Cooling',
          pressureBar: fusionGaugeBar,
          timeSeconds: _coolingTimeS - _coolingTimeS ~/ 3,
        ),
      ],
    );
  }
}
