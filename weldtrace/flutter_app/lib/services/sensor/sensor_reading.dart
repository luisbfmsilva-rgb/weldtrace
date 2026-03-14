/// A single timestamped sensor reading captured from the BLE sensor kit.
class SensorReading {
  const SensorReading({
    required this.recordedAt,
    required this.phaseName,
    this.pressureBar,
    this.temperatureCelsius,
    this.weldStepId,
  });

  final DateTime recordedAt;
  final String phaseName;
  final double? pressureBar;
  final double? temperatureCelsius;
  final String? weldStepId;

  /// Apply linear calibration correction: corrected = raw * slope + offset
  SensorReading calibrated({
    double pressureOffset = 0.0,
    double pressureSlope = 1.0,
    double temperatureOffset = 0.0,
    double temperatureSlope = 1.0,
  }) =>
      SensorReading(
        recordedAt: recordedAt,
        phaseName: phaseName,
        pressureBar: pressureBar != null
            ? pressureBar! * pressureSlope + pressureOffset
            : null,
        temperatureCelsius: temperatureCelsius != null
            ? temperatureCelsius! * temperatureSlope + temperatureOffset
            : null,
        weldStepId: weldStepId,
      );

  @override
  String toString() =>
      'SensorReading(t=${recordedAt.toIso8601String()}, '
      'p=${pressureBar?.toStringAsFixed(2)}bar, '
      'T=${temperatureCelsius?.toStringAsFixed(1)}°C)';
}
