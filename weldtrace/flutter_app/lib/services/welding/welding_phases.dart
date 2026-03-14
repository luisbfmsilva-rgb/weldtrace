/// Lightweight models used by the standard-specific fallback generators.
///
/// These types represent a single weld cycle phase (name, pressure, time)
/// and a computed phase table with the overall machine gauge pressure.
///
/// They are distinct from the workflow-level [PhaseParameters] / [WeldingPhase]
/// types used by [WeldWorkflowEngine] — those carry tolerance bands and are
/// tightly coupled to the engine state machine.  These simpler types are used
/// only to assemble and inspect the output of the fallback generators before
/// the data is persisted as [WeldingParametersTableCompanion].

/// A single named phase in a butt-fusion weld cycle.
class WeldPhase {
  const WeldPhase({
    required this.name,
    required this.pressureBar,
    required this.timeSeconds,
  });

  /// Human-readable phase name, e.g. 'Bead Build-up', 'Heat Soak'.
  final String name;

  /// Target pressure for this phase [bar].
  ///
  /// For interfacial-pressure phases this is the face pressure.
  /// For machine-gauge phases (after conversion) this is the hydraulic
  /// gauge pressure the operator reads on the machine panel.
  final double pressureBar;

  /// Nominal phase duration [s].
  final int timeSeconds;

  @override
  String toString() =>
      'WeldPhase($name: ${pressureBar.toStringAsFixed(3)} bar, ${timeSeconds}s)';
}

/// Output of a standard-specific fallback generator.
///
/// [phases] — ordered list of phases for the weld cycle.
/// [machineGaugePressureBar] — the computed hydraulic gauge target for the
///   fusion and cooling phases; equals the interfacial fusion pressure when
///   no machine cylinder data is available.
class WeldPhaseTable {
  const WeldPhaseTable({
    required this.phases,
    required this.machineGaugePressureBar,
  });

  final List<WeldPhase> phases;

  /// Machine hydraulic gauge pressure at fusion  [bar].
  ///
  /// Derived from:
  ///   F [N]        = P_interfacial [bar] × 100 000 [Pa/bar] × A_pipe [mm²] / 1e6
  ///   P_gauge [bar] = F [N] / (A_cyl [mm²] / 1e6) / 100 000 + P_drag
  ///                 = P_interfacial × A_pipe / A_cyl + P_drag
  final double machineGaugePressureBar;
}
