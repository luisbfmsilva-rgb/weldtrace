/// A single timestamped sensor reading captured from the BLE sensor kit.
///
/// Both raw (pre-calibration) and calibrated values are carried so that the
/// calibration screen can display the actual sensor output alongside the
/// corrected value in real time.
class SensorReading {
  const SensorReading({
    required this.recordedAt,
    required this.phaseName,
    this.pressureBar,
    this.temperatureCelsius,
    this.weldStepId,
    this.rawPressureBar,
    this.rawTemperatureCelsius,
  });

  final DateTime recordedAt;
  final String phaseName;

  /// Calibrated pressure in bar (raw × slope + offset).
  final double? pressureBar;

  /// Calibrated temperature in °C (raw × slope + offset).
  final double? temperatureCelsius;

  final String? weldStepId;

  /// Raw (uncalibrated) pressure directly from the BLE characteristic.
  /// Null when the sensor service is applying calibration on the same object
  /// (i.e., the [pressureBar] field already IS the calibrated value).
  final double? rawPressureBar;

  /// Raw (uncalibrated) temperature directly from the BLE characteristic.
  final double? rawTemperatureCelsius;

  /// Apply linear calibration: corrected = raw × slope + offset.
  ///
  /// Used to re-compute calibrated values from stored raw readings.
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
        rawPressureBar: pressureBar,
        rawTemperatureCelsius: temperatureCelsius,
      );

  @override
  String toString() =>
      'SensorReading(t=${recordedAt.toIso8601String()}, '
      'p=${pressureBar?.toStringAsFixed(2)}bar, '
      'T=${temperatureCelsius?.toStringAsFixed(1)}°C)';
}
