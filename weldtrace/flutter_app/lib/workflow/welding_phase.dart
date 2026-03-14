/// Defines the phases of a butt-fusion or electrofusion weld cycle
/// as specified in DVS 2207, ISO 21307, and ASTM F2620.

enum WeldingPhase {
  // ── Butt-fusion phases ──────────────────────────────────────────────────
  heatingUp(order: 1, displayName: 'Heating-up', unit: 's'),
  heating(order: 2, displayName: 'Heating', unit: 's'),
  changeover(order: 3, displayName: 'Changeover', unit: 's'),
  buildup(order: 4, displayName: 'Pressure Build-up', unit: 's'),
  fusion(order: 5, displayName: 'Fusion Pressure', unit: 's'),
  cooling(order: 6, displayName: 'Cooling', unit: 's'),

  // ── Electrofusion phases ────────────────────────────────────────────────
  efClamping(order: 1, displayName: 'Clamping', unit: 's'),
  efWelding(order: 2, displayName: 'Welding', unit: 's'),
  efCooling(order: 3, displayName: 'Cooling', unit: 's');

  const WeldingPhase({
    required this.order,
    required this.displayName,
    required this.unit,
  });

  final int order;
  final String displayName;
  final String unit;
}

/// Describes the parametric requirements for a single welding phase
/// as derived from the selected standard + pipe specification.
class PhaseParameters {
  const PhaseParameters({
    required this.phase,
    required this.nominalDuration,
    required this.minDuration,
    required this.maxDuration,
    this.nominalPressureBar,
    this.minPressureBar,
    this.maxPressureBar,
    this.nominalTemperatureCelsius,
    this.minTemperatureCelsius,
    this.maxTemperatureCelsius,
  });

  final WeldingPhase phase;

  // Time limits (seconds)
  final double nominalDuration;
  final double minDuration;
  final double maxDuration;

  // Pressure limits (bar) — null means not monitored for this phase
  final double? nominalPressureBar;
  final double? minPressureBar;
  final double? maxPressureBar;

  // Temperature limits (°C) — null means not monitored for this phase
  final double? nominalTemperatureCelsius;
  final double? minTemperatureCelsius;
  final double? maxTemperatureCelsius;

  bool isPressureInRange(double bar) =>
      (minPressureBar == null || bar >= minPressureBar!) &&
      (maxPressureBar == null || bar <= maxPressureBar!);

  bool isTemperatureInRange(double celsius) =>
      (minTemperatureCelsius == null || celsius >= minTemperatureCelsius!) &&
      (maxTemperatureCelsius == null || celsius <= maxTemperatureCelsius!);
}
