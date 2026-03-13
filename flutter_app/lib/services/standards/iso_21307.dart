import 'package:drift/drift.dart';

import '../../data/local/tables/welding_parameters_table.dart';
import '../welding/pipe_geometry.dart';
import '../welding/welding_phases.dart';

/// ISO 21307 welding mode selector.
///
/// ISO 21307 specifies two pressure regimes:
///   [lowPressure]  — single / dual-pressure: fusion step at 0.15 N/mm²
///   [highPressure] — high-pressure:           fusion step at 0.25 N/mm²
enum Iso21307Mode {
  lowPressure,
  highPressure,
}

/// Fallback welding parameter generator for **ISO 21307** (PE butt-fusion).
///
/// ISO 21307 defines two pressure procedures:
///
///   Low-pressure (single or dual):  P_fusion = 0.15 N/mm²  (1.5 bar)
///   High-pressure:                  P_fusion = 0.25 N/mm²  (2.5 bar)
///
/// All other timing and geometry rules mirror the DVS 2207 implementation
/// (same calculation engine, different interfacial pressure constants).
///
/// ── Bead height rule (simplified) ────────────────────────────────────────────
///
///   e < 10 mm   → min bead 2 mm
///   e 10–20 mm  → min bead 3 mm
///   e > 20 mm   → min bead 4 mm
///
///   TODO: confirm bead rule with ISO 21307 Table 4 values.
///
/// ── Machine gauge pressure conversion ────────────────────────────────────────
///
///   F [N]          = P_interfacial [bar] × 100 000 × A_pipe [mm²] / 1e6
///   P_gauge [bar]  = P_interfacial × A_pipe / A_cyl + P_drag
class Iso21307 {
  Iso21307._();

  // ── ISO 21307 interfacial pressure constants ─────────────────────────────

  static const double _heatingUpInterfacialBar = 0.15;
  static const double _heatSoakInterfacialBar = 0.02;

  /// Low-pressure procedure fusion interfacial pressure [bar].
  static const double _fusionLowBar = 0.15;

  /// High-pressure procedure fusion interfacial pressure [bar].
  static const double _fusionHighBar = 0.25;

  static const double _toleranceFraction = 0.10;

  // ── Time fallbacks ────────────────────────────────────────────────────────

  static const int _heatingUpTimeS = 30;
  static const int _heatSoakTimeS = 120;
  static const int _changeoverMaxS = 10;
  static const int _buildupTimeS = 15;
  static const int _fusionTimeS = 30;
  static const int _coolingTimeS = 720;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generates a [WeldingParametersTableCompanion] using ISO 21307 defaults.
  ///
  /// [mode] selects the pressure procedure ([Iso21307Mode.lowPressure] or
  /// [Iso21307Mode.highPressure]).  All other parameters are shared.
  ///
  /// The companion stores **interfacial** pressures.  Pass it to
  /// [WeldingTableGenerator.generate()] with a [MachineSpec] for gauge
  /// pressure conversion.
  ///
  /// [pipeDiameterMm]           — OD [mm]
  /// [sdrRating]                — SDR string (e.g. '11', 'SDR17.6')
  /// [pipeMaterial]             — 'PE' | 'PP'
  /// [mode]                     — pressure procedure; defaults to low-pressure
  /// [hydraulicCylinderAreaMm2] — used only to populate [WeldPhaseTable]
  /// [dragPressureBar]          — measured drag [bar]
  static WeldingParametersTableCompanion generateFallback({
    required double pipeDiameterMm,
    required String sdrRating,
    required String pipeMaterial,
    Iso21307Mode mode = Iso21307Mode.lowPressure,
    double? hydraulicCylinderAreaMm2,
    double dragPressureBar = 0.0,
  }) {
    // ── 1. Geometry ───────────────────────────────────────────────────────────

    final sdr = PipeGeometry.parseSdr(sdrRating);
    final e = PipeGeometry.wallThickness(pipeDiameterMm, sdr);
    final aPipe = PipeGeometry.pipeAnnulusArea(pipeDiameterMm, e);

    // ── 2. Fusion interfacial pressure based on mode ──────────────────────────

    final fusionInterfacialBar =
        mode == Iso21307Mode.highPressure ? _fusionHighBar : _fusionLowBar;

    // ── 3. Bead size estimate ─────────────────────────────────────────────────
    // TODO: confirm bead rule with ISO 21307 Table 4 values.
    final beadHeightMm = _beadHeight(e);

    // ── 4. Machine gauge conversion (for WeldPhaseTable inspection only) ─────
    //
    //   F [N]          = P_interfacial [bar] × 100 000 × A_pipe [mm²] / 1e6
    //   P_gauge [bar]  = P_interfacial × A_pipe / A_cyl + P_drag
    //
    final double fusionGaugeBar;
    if (hydraulicCylinderAreaMm2 != null && hydraulicCylinderAreaMm2 > 0) {
      final forceN = fusionInterfacialBar * 100000 * aPipe / 1e6;
      final machinePressureBar =
          forceN / (hydraulicCylinderAreaMm2 / 1e6) / 100000;
      fusionGaugeBar = machinePressureBar + dragPressureBar;
    } else {
      fusionGaugeBar = fusionInterfacialBar;
    }

    _buildPhaseTable(fusionGaugeBar);

    // ── 5. Return companion ───────────────────────────────────────────────────

    final modeLabel =
        mode == Iso21307Mode.highPressure ? 'High-Pressure' : 'Low-Pressure';

    return WeldingParametersTableCompanion(
      pipeMaterial: Value(pipeMaterial),
      pipeDiameterMm: Value(pipeDiameterMm),
      sdrRating: Value(sdrRating),
      wallThicknessMm: Value(e),

      // Phase 1: Bead build-up
      heatingUpTimeS: const Value(_heatingUpTimeS),
      heatingUpPressureBar: const Value(_heatingUpInterfacialBar),

      // Phase 2: Heat soak
      heatingTimeS: const Value(_heatSoakTimeS),
      heatingPressureBar: const Value(_heatSoakInterfacialBar),

      // Phase 3: Changeover
      changeoverTimeMaxS: const Value(_changeoverMaxS),

      // Phase 4: Pressure build-up
      buildupTimeS: const Value(_buildupTimeS),

      // Phase 5: Fusion
      fusionTimeS: const Value(_fusionTimeS),
      fusionPressureBar: Value(fusionInterfacialBar),
      fusionPressureMinBar: Value(fusionInterfacialBar * (1 - _toleranceFraction)),
      fusionPressureMaxBar: Value(fusionInterfacialBar * (1 + _toleranceFraction)),

      // Phase 6: Cooling
      coolingTimeS: const Value(_coolingTimeS),
      coolingPressureBar: Value(fusionInterfacialBar),

      notes: Value(
        'ISO 21307 $modeLabel fallback — bead ≥ '
        '${beadHeightMm.toStringAsFixed(1)} mm, '
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
            timeSeconds: _heatSoakTimeS),
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
