import '../../services/welding/pipe_spec.dart';
import '../../workflow/welding_phase.dart';

/// A single row of calculated butt-fusion welding parameters for a specific
/// pipe × machine combination.
///
/// Pressures are expressed as **machine hydraulic gauge pressure** [bar] when
/// [isMachinePressure] is true, or as **interfacial pressure** [bar] when the
/// machine's hydraulic cylinder area is unknown.
class WeldingTableRow {
  const WeldingTableRow({
    // ── Geometry ──────────────────────────────────────────────────────────────
    required this.wallThicknessMm,
    required this.pipeAnnulusAreaMm2,
    required this.minBeadHeightMm,

    // ── Machine gauge pressures or interfacial fallback ───────────────────────
    this.heatingUpPressureBar,
    this.heatingPressureBar,
    this.fusionPressureBar,
    this.fusionPressureMinBar,
    this.fusionPressureMaxBar,
    this.coolingPressureBar,

    // ── Times (unchanged — determined by standard, not machine) ───────────────
    required this.heatingUpTimeS,
    required this.heatingTimeS,
    required this.changeoverTimeMaxS,
    required this.buildupTimeS,
    required this.fusionTimeS,
    required this.coolingTimeS,

    // ── Metadata ──────────────────────────────────────────────────────────────
    required this.isMachinePressure,
    this.hydraulicCylinderAreaMm2,
    required this.dragPressureBar,
  });

  // ── Geometry ────────────────────────────────────────────────────────────────

  /// Wall thickness  e = OD / SDR  [mm]
  final double wallThicknessMm;

  /// Pipe annulus area  A = π × (OD − e) × e  [mm²]
  final double pipeAnnulusAreaMm2;

  /// Minimum bead height per ISO 21307 Table 4  [mm]
  final double minBeadHeightMm;

  // ── Machine gauge pressures ─────────────────────────────────────────────────

  final double? heatingUpPressureBar;
  final double? heatingPressureBar;
  final double? fusionPressureBar;
  final double? fusionPressureMinBar;
  final double? fusionPressureMaxBar;
  final double? coolingPressureBar;

  // ── Phase durations ─────────────────────────────────────────────────────────

  final int heatingUpTimeS;
  final int heatingTimeS;
  final int changeoverTimeMaxS;
  final int buildupTimeS;
  final int fusionTimeS;
  final int coolingTimeS;

  // ── Metadata ────────────────────────────────────────────────────────────────

  /// True when pressures above are machine hydraulic gauge pressures.
  /// False when the machine cylinder area is unknown and pressures are
  /// the raw interfacial values from the welding standard.
  final bool isMachinePressure;

  /// Machine hydraulic cylinder area used in the calculation  [mm²].
  /// Null when [isMachinePressure] is false.
  final double? hydraulicCylinderAreaMm2;

  /// Drag pressure that was added to every machine gauge target  [bar].
  final double dragPressureBar;

  String get pressureLabel => isMachinePressure ? 'gauge' : 'interfacial';
}

/// Complete welding table for one pipe specification + machine combination.
///
/// [row] contains every calculated parameter.
/// [phases] is the ordered list of [PhaseParameters] ready for the
/// [WeldWorkflowEngine] — pressures in [phases] match those in [row].
class WeldingTable {
  const WeldingTable({
    required this.pipeSpec,
    required this.machineSpec,
    required this.row,
    required this.phases,
  });

  final PipeSpec pipeSpec;
  final MachineSpec machineSpec;
  final WeldingTableRow row;

  /// Ordered [PhaseParameters] with machine (or interfacial) pressures.
  /// Pass directly to [WeldWorkflowEngine].
  final List<PhaseParameters> phases;
}
