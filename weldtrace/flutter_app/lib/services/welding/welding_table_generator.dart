import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../data/local/tables/welding_parameters_table.dart';
import '../../workflow/welding_phase.dart';
import '../standards/dvs_2207.dart';
import '../standards/iso_21307.dart';
import '../standards/astm_f2620.dart';
import 'pipe_spec.dart';
import 'welding_table.dart';

/// Converts a [WeldingParameterRecord] (which stores **interfacial** pressures
/// as specified by the welding standard) into a [WeldingTable] containing:
///
///   • Verified pipe geometry (wall thickness, annulus area, bead height)
///   • Machine hydraulic gauge pressures calculated from the interfacial
///     pressures using the hydraulic cylinder area and the measured drag
///
///   • A ready-to-use [List<PhaseParameters>] for the [WeldWorkflowEngine]
///
/// ── Conversion formula ─────────────────────────────────────────────────────
///
///   e                   = OD / SDR                               [mm]
///   A_ann               = π × (OD − e) × e                      [mm²]  (annulus, for reference)
///   beadWidth           = e × 0.9                                [mm]
///   effectiveCircum     = π × OD × 0.65  (beadContactFactor)    [mm]
///   contactArea         = effectiveCircum × beadWidth            [mm²]  clamped [100, 10 000 000]
///   forceN              = P_interfacial × 100 000 × contactArea / 1e6   [N]
///   machinePressureBar  = forceN / (A_cylinder / 1e6) / 100 000         [bar]
///   gaugePressureBar    = max(0, machinePressureBar − dragPressureBar)   [bar]
///
/// When [MachineSpec.hasHydraulicData] is false the generator returns
/// the interfacial pressures unchanged and marks [WeldingTableRow.isMachinePressure]
/// as false — a useful fallback for machines whose cylinder area has not
/// been entered yet.
///
/// ── Pressure tolerances ────────────────────────────────────────────────────
///
///   The standard's min/max interfacial values (when present) are converted
///   independently.  When only a nominal interfacial value is stored the
///   generator applies a ±10 % tolerance band around the converted nominal.
class WeldingTableGenerator {
  WeldingTableGenerator._();

  /// Build a [WeldingTable] from a DB record + pipe geometry + machine data.
  ///
  /// [record]      — row from `welding_parameters` (interfacial pressures)
  /// [pipeSpec]    — OD, SDR, material (from the setup screen selectors)
  /// [machineSpec] — cylinder area + measured drag pressure
  /// [weldType]    — 'butt_fusion' | 'electrofusion'
  static WeldingTable generate({
    required WeldingParameterRecord record,
    required PipeSpec pipeSpec,
    required MachineSpec machineSpec,
    required String weldType,
  }) {
    final row = _buildRow(
      record: record,
      pipeSpec: pipeSpec,
      machineSpec: machineSpec,
    );

    final phases = weldType == 'electrofusion'
        ? _buildElectrofusionPhases(record, pipeSpec, machineSpec)
        : _buildButtFusionPhases(record, pipeSpec, machineSpec);

    return WeldingTable(
      pipeSpec: pipeSpec,
      machineSpec: machineSpec,
      row: row,
      phases: phases,
    );
  }

  // ── Row builder ─────────────────────────────────────────────────────────────

  static WeldingTableRow _buildRow({
    required WeldingParameterRecord record,
    required PipeSpec pipeSpec,
    required MachineSpec machineSpec,
  }) {
    final hasMachine = machineSpec.hasHydraulicData;
    final cyl  = machineSpec.hydraulicCylinderAreaMm2 ?? 1.0;
    final drag = machineSpec.dragPressureBar;

    // Pipe end-face annulus area.
    //   A_ann [mm²] = π × (OD − e) × e
    final e    = pipeSpec.wallThicknessMm;
    final area = math.pi * (pipeSpec.outerDiameterMm - e) * e;

    // Bead width and contact area for pressure conversion.
    //
    //   bead width proportional to wall thickness
    final beadWidthMm = e * 0.9;
    // effective molten bead contact band
    // reduces full circumference assumption
    const beadContactFactor = 0.65;
    final effectiveCircumference = math.pi * pipeSpec.outerDiameterMm * beadContactFactor;
    // numeric guard — prevents unrealistic values for very small/large pipes
    final contactAreaMm2 =
        (effectiveCircumference * beadWidthMm).clamp(100.0, 10000000.0);

    // Converts one interfacial pressure value to machine gauge pressure.
    //
    //   F [N]               = P [bar] × 100 000 × contactArea [mm²] / 1e6
    //   machinePressure [bar] = F / (A_cyl [mm²] / 1e6) / 100 000
    //   gaugePressure [bar]   = machinePressure − P_drag  (clamped ≥ 0)
    //
    // Returns the interfacial value unchanged when cylinder area is unknown.
    double? convert(double? interfacial) {
      if (interfacial == null) return null;
      if (!hasMachine) return interfacial;
      // converts bar × area into Newtons
      final forceN             = interfacial * 100000 * contactAreaMm2 / 1e6;
      final machinePressureBar = forceN / (cyl / 1e6) / 100000;
      return math.max(0.0, machinePressureBar - drag);
    }

    // Fusion pressure band
    final fusionNom = convert(record.fusionPressureBar);
    final fusionMin = convert(record.fusionPressureMinBar) ??
        (fusionNom != null ? fusionNom * 0.90 : null);
    final fusionMax = convert(record.fusionPressureMaxBar) ??
        (fusionNom != null ? fusionNom * 1.10 : null);

    return WeldingTableRow(
      wallThicknessMm: pipeSpec.wallThicknessMm,
      pipeAnnulusAreaMm2: area,
      minBeadHeightMm: pipeSpec.minBeadHeightMm,

      heatingUpPressureBar: convert(record.heatingUpPressureBar),
      heatingPressureBar: convert(record.heatingPressureBar),
      fusionPressureBar: fusionNom,
      fusionPressureMinBar: fusionMin,
      fusionPressureMaxBar: fusionMax,
      coolingPressureBar: convert(record.coolingPressureBar),

      heatingUpTimeS: record.heatingUpTimeS ?? 30,
      heatingTimeS: record.heatingTimeS ?? 60,
      changeoverTimeMaxS: record.changeoverTimeMaxS ?? _changeoverMax(pipeSpec.wallThicknessMm),
      buildupTimeS: record.buildupTimeS ?? 15,
      fusionTimeS: record.fusionTimeS ?? 120,
      coolingTimeS: record.coolingTimeS ?? 300,

      isMachinePressure: hasMachine,
      hydraulicCylinderAreaMm2: machineSpec.hydraulicCylinderAreaMm2,
      dragPressureBar: drag,
    );
  }

  // ── Phase builders ──────────────────────────────────────────────────────────

  static List<PhaseParameters> _buildButtFusionPhases(
    WeldingParameterRecord record,
    PipeSpec pipeSpec,
    MachineSpec machineSpec,
  ) {
    final hasMachine = machineSpec.hasHydraulicData;
    final cyl  = machineSpec.hydraulicCylinderAreaMm2 ?? 1.0;
    final drag = machineSpec.dragPressureBar;

    // bead width proportional to wall thickness
    final e           = pipeSpec.wallThicknessMm;
    final beadWidthMm = e * 0.9;
    // effective molten bead contact band
    // reduces full circumference assumption
    const beadContactFactor = 0.65;
    final effectiveCircumference = math.pi * pipeSpec.outerDiameterMm * beadContactFactor;
    // numeric guard — prevents unrealistic values for very small/large pipes
    final contactAreaMm2 =
        (effectiveCircumference * beadWidthMm).clamp(100.0, 10000000.0);

    const timeTol = 0.10;  // ±10 % time tolerance
    const presTol = 0.10;  // ±10 % pressure tolerance fallback

    // converts bar × area into Newtons; result clamped ≥ 0
    double? conv(double? interfacial) {
      if (interfacial == null) return null;
      if (!hasMachine) return interfacial;
      // converts bar × area into Newtons
      final forceN             = interfacial * 100000 * contactAreaMm2 / 1e6;
      final machinePressureBar = forceN / (cyl / 1e6) / 100000;
      return math.max(0.0, machinePressureBar - drag);
    }

    double? convMin(double? interfacial, double? nomMachine) =>
        conv(interfacial) ?? (nomMachine != null ? nomMachine * (1 - presTol) : null);

    double? convMax(double? interfacial, double? nomMachine) =>
        conv(interfacial) ?? (nomMachine != null ? nomMachine * (1 + presTol) : null);

    // ── 1. Heating-up ─────────────────────────────────────────────────────────
    final huNom = conv(record.heatingUpPressureBar);
    final huT = (record.heatingUpTimeS ?? 30).toDouble();

    // ── 2. Heating ────────────────────────────────────────────────────────────
    final hNom = conv(record.heatingPressureBar);
    final hT = (record.heatingTimeS ?? 60).toDouble();

    // ── 5. Fusion ─────────────────────────────────────────────────────────────
    final fNom = conv(record.fusionPressureBar);
    final fMin = convMin(record.fusionPressureMinBar, fNom);
    final fMax = convMax(record.fusionPressureMaxBar, fNom);
    final fT = (record.fusionTimeS ?? 120).toDouble();

    // ── 6. Cooling ────────────────────────────────────────────────────────────
    final cNom = conv(record.coolingPressureBar) ?? fNom;
    final cT = (record.coolingTimeS ?? 300).toDouble();

    // Changeover max: use record if available, else look up from wall thickness
    final coMax = (record.changeoverTimeMaxS ?? _changeoverMax(pipeSpec.wallThicknessMm)).toDouble();

    // Build-up time
    final buT = (record.buildupTimeS ?? 15).toDouble();

    return [
      // 1. Heating-up
      PhaseParameters(
        phase: WeldingPhase.heatingUp,
        nominalDuration: huT,
        minDuration: 0,
        maxDuration: huT * 1.5,
        nominalPressureBar: huNom,
        minPressureBar: huNom != null ? huNom * (1 - presTol) : null,
        maxPressureBar: huNom != null ? huNom * (1 + presTol) : null,
      ),

      // 2. Heating (soak time — only loose lower bound, no pressure after initial)
      PhaseParameters(
        phase: WeldingPhase.heating,
        nominalDuration: hT,
        minDuration: hT * (1 - timeTol),
        maxDuration: hT * (1 + timeTol),
        nominalPressureBar: hNom,
        minPressureBar: hNom != null ? hNom * (1 - presTol) : null,
        maxPressureBar: hNom != null ? hNom * (1 + presTol) : null,
        nominalTemperatureCelsius: record.heatingTempNominalCelsius,
        minTemperatureCelsius: record.heatingTempMinCelsius,
        maxTemperatureCelsius: record.heatingTempMaxCelsius,
      ),

      // 3. Changeover (heater removal — no pressure target, only max time)
      PhaseParameters(
        phase: WeldingPhase.changeover,
        nominalDuration: 0,
        minDuration: 0,
        maxDuration: coMax,
      ),

      // 4. Pressure build-up (ramp to fusion pressure — no lower limit)
      PhaseParameters(
        phase: WeldingPhase.buildup,
        nominalDuration: buT,
        minDuration: 0,
        maxDuration: buT * 2.0,
        nominalPressureBar: fNom,
        minPressureBar: null,          // ramping — enforce only upper bound
        maxPressureBar: fMax,
      ),

      // 5. Fusion
      PhaseParameters(
        phase: WeldingPhase.fusion,
        nominalDuration: fT,
        minDuration: fT * (1 - timeTol * 0.5),
        maxDuration: fT * (1 + timeTol * 0.5),
        nominalPressureBar: fNom,
        minPressureBar: fMin,
        maxPressureBar: fMax,
      ),

      // 6. Cooling
      PhaseParameters(
        phase: WeldingPhase.cooling,
        nominalDuration: cT,
        minDuration: cT * (1 - timeTol * 0.5),
        maxDuration: cT * (1 + timeTol * 2.0),
        nominalPressureBar: cNom,
        minPressureBar: cNom != null ? cNom * (1 - presTol) : null,
        maxPressureBar: cNom != null ? cNom * (1 + presTol) : null,
      ),
    ];
  }

  static List<PhaseParameters> _buildElectrofusionPhases(
    WeldingParameterRecord record,
    PipeSpec pipeSpec,
    MachineSpec machineSpec,
  ) {
    // Electrofusion machines use voltage, not hydraulic pressure —
    // the cylinder area conversion is not applied.
    final eT = (record.efWeldingTimeS ?? 60).toDouble();
    final ecT = (record.efCoolingTimeS ?? 180).toDouble();

    return [
      PhaseParameters(
        phase: WeldingPhase.efClamping,
        nominalDuration: 60,
        minDuration: 30,
        maxDuration: 300,
      ),
      PhaseParameters(
        phase: WeldingPhase.efWelding,
        nominalDuration: eT,
        minDuration: eT * 0.98,
        maxDuration: eT * 1.02,
      ),
      PhaseParameters(
        phase: WeldingPhase.efCooling,
        nominalDuration: ecT,
        minDuration: ecT * 0.95,
        maxDuration: ecT * 1.20,
      ),
    ];
  }

  // ── Convenience named-constructor alias ──────────────────────────────────────

  /// Named alias for [generate] — preferred by callers that already have a
  /// [WeldingParameterRecord] and want to make the intent explicit.
  ///
  /// Usage:
  /// ```dart
  /// final table = WeldingTableGenerator.buildFromRecord(
  ///   record: record,
  ///   pipeSpec: spec,
  ///   machineSpec: machine,
  ///   weldType: 'butt_fusion',
  /// );
  /// ```
  static WeldingTable buildFromRecord({
    required WeldingParameterRecord record,
    required PipeSpec pipeSpec,
    required MachineSpec machineSpec,
    required String weldType,
  }) =>
      generate(
        record: record,
        pipeSpec: pipeSpec,
        machineSpec: machineSpec,
        weldType: weldType,
      );

  // ── Fallback generator dispatcher ────────────────────────────────────────────

  /// Generates a [WeldingParametersTableCompanion] using the built-in
  /// standard-specific fallback engine when **no DB record** is available.
  ///
  /// Dispatches to the correct engine based on [standardId]:
  ///
  ///   • Strings containing 'dvs'    → [Dvs2207.generateFallback]
  ///   • Strings containing 'iso'    → [Iso21307.generateFallback]
  ///       Sub-dispatch on [Iso21307Mode] via [iso21307Mode] parameter.
  ///   • Strings containing 'astm'   → [AstmF2620.generateFallback]
  ///   • Unrecognised ID             → DVS 2207 (safe conservative default)
  ///
  /// The returned companion stores **interfacial** pressures.  To get machine
  /// gauge pressures, persist the companion, load a [WeldingParameterRecord],
  /// and call [generate] or [buildFromRecord].
  ///
  /// [standardId]               — standard ID or code string from the DB
  ///                              (e.g. 'DVS_2207', 'ISO_21307', 'ASTM_F2620')
  /// [pipeDiameterMm]           — OD [mm]
  /// [sdrRating]                — SDR string (e.g. 'SDR11', '17.6')
  /// [pipeMaterial]             — 'PE' | 'PP'
  /// [hydraulicCylinderAreaMm2] — cylinder area [mm²]; null = no machine data
  /// [dragPressureBar]          — drag measured before welding [bar]
  /// [iso21307Mode]             — selects low or high pressure for ISO 21307
  static WeldingParametersTableCompanion generateFallbackForStandard({
    required String standardId,
    required double pipeDiameterMm,
    required String sdrRating,
    required String pipeMaterial,
    double? hydraulicCylinderAreaMm2,
    double dragPressureBar = 0.0,
    Iso21307Mode iso21307Mode = Iso21307Mode.lowPressure,
  }) {
    final id = standardId.toLowerCase();

    if (id.contains('iso')) {
      return Iso21307.generateFallback(
        pipeDiameterMm: pipeDiameterMm,
        sdrRating: sdrRating,
        pipeMaterial: pipeMaterial,
        mode: iso21307Mode,
        hydraulicCylinderAreaMm2: hydraulicCylinderAreaMm2,
        dragPressureBar: dragPressureBar,
      );
    }

    if (id.contains('astm')) {
      return AstmF2620.generateFallback(
        pipeDiameterMm: pipeDiameterMm,
        sdrRating: sdrRating,
        pipeMaterial: pipeMaterial,
        hydraulicCylinderAreaMm2: hydraulicCylinderAreaMm2,
        dragPressureBar: dragPressureBar,
      );
    }

    // dvs — and catch-all (conservative default)
    return Dvs2207.generateFallback(
      pipeDiameterMm: pipeDiameterMm,
      sdrRating: sdrRating,
      pipeMaterial: pipeMaterial,
      hydraulicCylinderAreaMm2: hydraulicCylinderAreaMm2,
      dragPressureBar: dragPressureBar,
    );
  }

  // ── Companion → Record converter ──────────────────────────────────────────────

  /// Creates a [WeldingParameterRecord] from a [WeldingParametersTableCompanion].
  ///
  /// Used when a fallback companion is generated offline (no DB row exists)
  /// and must be passed to [generate] / [buildFromRecord] immediately.
  ///
  /// [id]         — synthetic record ID (e.g. 'fallback-dvs-PE100-160-11')
  /// [standardId] — the standard's ID from the DB (or the standardId string)
  static WeldingParameterRecord companionToRecord({
    required WeldingParametersTableCompanion companion,
    required String id,
    required String standardId,
  }) {
    // Helper: extract value or return null for absent fields.
    T? val<T>(Value<T> v) => v.present ? v.value : null;
    // Helper: extract value or return a default for required fields.
    T def<T>(Value<T> v, T defaultVal) => v.present ? v.value : defaultVal;

    return WeldingParameterRecord(
      id:              id,
      standardId:      standardId,
      pipeMaterial:    def(companion.pipeMaterial, ''),
      pipeDiameterMm:  def(companion.pipeDiameterMm, 0.0),
      sdrRating:       def(companion.sdrRating, ''),
      wallThicknessMm: val(companion.wallThicknessMm),

      ambientTempMinCelsius: def(companion.ambientTempMinCelsius, -15.0),
      ambientTempMaxCelsius: def(companion.ambientTempMaxCelsius, 50.0),

      heatingUpTimeS:       val(companion.heatingUpTimeS),
      heatingUpPressureBar: val(companion.heatingUpPressureBar),
      heatingTimeS:         val(companion.heatingTimeS),
      heatingPressureBar:   val(companion.heatingPressureBar),
      changeoverTimeMaxS:   val(companion.changeoverTimeMaxS),
      buildupTimeS:         val(companion.buildupTimeS),
      fusionTimeS:          val(companion.fusionTimeS),
      fusionPressureBar:    val(companion.fusionPressureBar),
      fusionPressureMinBar: val(companion.fusionPressureMinBar),
      fusionPressureMaxBar: val(companion.fusionPressureMaxBar),
      coolingTimeS:         val(companion.coolingTimeS),
      coolingPressureBar:   val(companion.coolingPressureBar),

      efWeldingTimeS:  val(companion.efWeldingTimeS),
      efWeldingVoltage: val(companion.efWeldingVoltage),
      efCoolingTimeS:  val(companion.efCoolingTimeS),

      heatingTempNominalCelsius: val(companion.heatingTempNominalCelsius),
      heatingTempMinCelsius:     val(companion.heatingTempMinCelsius),
      heatingTempMaxCelsius:     val(companion.heatingTempMaxCelsius),

      notes:      val(companion.notes),
      isActive:   def(companion.isActive, true),
      createdAt:  val(companion.createdAt),
      updatedAt:  val(companion.updatedAt),
      syncStatus: def(companion.syncStatus, 'pending'),
      lastSyncedAt: val(companion.lastSyncedAt),
    );
  }

  // ── Debug / engineering verification helper ──────────────────────────────────

  /// Returns a human-readable map of intermediate calculation values for a
  /// given pipe and machine combination.
  ///
  /// Useful for engineering verification of the pressure conversion chain
  /// without needing to run a full weld:
  ///
  /// ```dart
  /// final info = WeldingTableGenerator.debugCalculation(
  ///   pipeDiameterMm:           160,
  ///   wallThicknessMm:          14.55,
  ///   interfacialPressureBar:   0.15,
  ///   hydraulicCylinderAreaMm2: 1000,
  ///   dragPressureBar:          0.2,
  /// );
  /// ```
  ///
  /// Returned keys:
  ///   wallThickness       — e [mm]
  ///   beadWidth           — e × 0.9 [mm]
  ///   contactArea         — effective contact area [mm²]
  ///   fusionForce         — forceN [N]
  ///   machinePressure     — machine hydraulic pressure [bar]
  static Map<String, double> debugCalculation({
    required double pipeDiameterMm,
    required double wallThicknessMm,
    required double interfacialPressureBar,
    required double hydraulicCylinderAreaMm2,
    double dragPressureBar = 0.0,
  }) {
    final e           = wallThicknessMm;
    final beadWidthMm = e * 0.9;

    // effective molten bead contact band
    // reduces full circumference assumption
    const beadContactFactor = 0.65;
    final effectiveCircumference = math.pi * pipeDiameterMm * beadContactFactor;
    // numeric guard — prevents unrealistic values for very small/large pipes
    final contactAreaMm2 =
        (effectiveCircumference * beadWidthMm).clamp(100.0, 10000000.0);

    final fusionForceN       = interfacialPressureBar * 100000 * contactAreaMm2 / 1e6;
    final machinePressureBar = fusionForceN / (hydraulicCylinderAreaMm2 / 1e6) / 100000;
    final gaugePressureBar   = math.max(0.0, machinePressureBar - dragPressureBar);

    return {
      'wallThickness':   e,
      'beadWidth':       beadWidthMm,
      'contactArea':     contactAreaMm2,
      'fusionForce':     fusionForceN,
      'machinePressure': gaugePressureBar,
    };
  }

  // ── Changeover time lookup ────────────────────────────────────────────────────
  // DVS 2207-1 Table 3 — maximum changeover time as a function of wall thickness.

  static int _changeoverMax(double wallThicknessMm) {
    if (wallThicknessMm <= 12) return 5;
    if (wallThicknessMm <= 25) return 7;
    if (wallThicknessMm <= 45) return 9;
    return 12;
  }
}
