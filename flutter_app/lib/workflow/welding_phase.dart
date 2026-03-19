/// Defines the phases of a butt-fusion or electrofusion weld cycle
/// as specified in DVS 2207, ISO 21307, and ASTM F2620.

enum WeldingPhase {
  // ── Butt-fusion phases ──────────────────────────────────────────────────
  heatingUp(order: 1, displayName: 'Formação do Cordão', unit: 's'),
  heating(order: 2, displayName: 'Aquecimento', unit: 's'),
  changeover(order: 3, displayName: 'Troca de Ferramenta', unit: 's'),
  buildup(order: 4, displayName: 'Pressurização', unit: 's'),
  fusion(order: 5, displayName: 'Fusão', unit: 's'),
  cooling(order: 6, displayName: 'Resfriamento', unit: 's'),

  // ── Electrofusion phases ────────────────────────────────────────────────
  efClamping(order: 1, displayName: 'Fixação', unit: 's'),
  efWelding(order: 2, displayName: 'Soldagem', unit: 's'),
  efCooling(order: 3, displayName: 'Resfriamento', unit: 's');

  const WeldingPhase({
    required this.order,
    required this.displayName,
    required this.unit,
  });

  final int order;
  final String displayName;
  final String unit;

  String toJson() => name;

  static WeldingPhase fromJson(String s) =>
      WeldingPhase.values.firstWhere((e) => e.name == s);
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
    this.isManualCompletion = false,
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

  /// When true, the phase only ends on explicit operator confirmation,
  /// not automatically based on elapsed time (e.g. heatingUp / bead formation).
  final bool isManualCompletion;

  bool isPressureInRange(double bar) =>
      (minPressureBar == null || bar >= minPressureBar!) &&
      (maxPressureBar == null || bar <= maxPressureBar!);

  bool isTemperatureInRange(double celsius) =>
      (minTemperatureCelsius == null || celsius >= minTemperatureCelsius!) &&
      (maxTemperatureCelsius == null || celsius <= maxTemperatureCelsius!);

  Map<String, dynamic> toJson() => {
        'phase': phase.toJson(),
        'nominalDuration': nominalDuration,
        'minDuration': minDuration,
        'maxDuration': maxDuration,
        if (nominalPressureBar != null) 'nominalPressureBar': nominalPressureBar,
        if (minPressureBar != null) 'minPressureBar': minPressureBar,
        if (maxPressureBar != null) 'maxPressureBar': maxPressureBar,
        if (nominalTemperatureCelsius != null)
          'nominalTemperatureCelsius': nominalTemperatureCelsius,
        if (minTemperatureCelsius != null)
          'minTemperatureCelsius': minTemperatureCelsius,
        if (maxTemperatureCelsius != null)
          'maxTemperatureCelsius': maxTemperatureCelsius,
        'isManualCompletion': isManualCompletion,
      };

  factory PhaseParameters.fromJson(Map<String, dynamic> j) => PhaseParameters(
        phase: WeldingPhase.fromJson(j['phase'] as String),
        nominalDuration: (j['nominalDuration'] as num).toDouble(),
        minDuration: (j['minDuration'] as num).toDouble(),
        maxDuration: (j['maxDuration'] as num).toDouble(),
        nominalPressureBar: (j['nominalPressureBar'] as num?)?.toDouble(),
        minPressureBar: (j['minPressureBar'] as num?)?.toDouble(),
        maxPressureBar: (j['maxPressureBar'] as num?)?.toDouble(),
        nominalTemperatureCelsius:
            (j['nominalTemperatureCelsius'] as num?)?.toDouble(),
        minTemperatureCelsius:
            (j['minTemperatureCelsius'] as num?)?.toDouble(),
        maxTemperatureCelsius:
            (j['maxTemperatureCelsius'] as num?)?.toDouble(),
        isManualCompletion: j['isManualCompletion'] as bool? ?? false,
      );
}
