import 'dart:math' as math;

/// A single sample recorded during a live weld session.
///
/// [timeSeconds] is measured from [WeldTraceRecorder.start] with millisecond
/// precision.  [pressureBar] is clamped to ≥ 0 before storage.
class WeldTracePoint {
  const WeldTracePoint({
    required this.timeSeconds,
    required this.pressureBar,
    required this.phase,
  });

  final double timeSeconds;

  /// Hydraulic gauge pressure [bar], always ≥ 0.
  final double pressureBar;

  /// Display name of the welding phase at the moment this sample was captured
  /// (e.g. 'Fusion Pressure', 'Cooling').
  final String phase;

  Map<String, dynamic> toJson() => {
        'timeSeconds':  timeSeconds,
        'pressureBar':  pressureBar,
        'phase':        phase,
      };

  factory WeldTracePoint.fromJson(Map<String, dynamic> json) => WeldTracePoint(
        timeSeconds: (json['timeSeconds'] as num).toDouble(),
        pressureBar: (json['pressureBar'] as num).toDouble(),
        phase:       json['phase'] as String,
      );
}

/// Records the real-time pressure × time curve during a live weld session.
///
/// Usage:
/// ```dart
/// final recorder = WeldTraceRecorder();
/// recorder.start();
///
/// // called once per second from sensor subscription
/// recorder.record(pressureBar: reading.pressureBar, phase: 'Fusion Pressure');
///
/// final curve = recorder.export();
/// ```
///
/// ── Guards ───────────────────────────────────────────────────────────────────
///
/// • [record] is a no-op if [start] has not been called yet.
/// • Negative pressures are clamped to 0 before storage.
/// • [export] returns an unmodifiable copy — the internal list is not cleared
///   so the recorder can be inspected after the weld completes.
class WeldTraceRecorder {
  WeldTraceRecorder();

  final List<WeldTracePoint> _points = [];
  DateTime? _startTime;

  /// All recorded samples in chronological order (read-only).
  List<WeldTracePoint> get points => List.unmodifiable(_points);

  /// Returns true once [start] has been called.
  bool get isStarted => _startTime != null;

  /// Total recording duration in seconds.  Returns 0 if not started.
  double get durationSeconds {
    if (_startTime == null) return 0;
    return DateTime.now().difference(_startTime!).inMilliseconds / 1000.0;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Initialises the recording clock.  Must be called before [record].
  ///
  /// Calling [start] a second time resets the recorder (points are cleared
  /// and the clock restarts from zero).
  void start() {
    _startTime = DateTime.now();
    _points.clear();
  }

  /// Records a single pressure sample at the current wall-clock offset.
  ///
  /// Sampling frequency guidance: call once per second from the sensor loop
  /// to match the ≈ 1 Hz resolution expected by [WeldReportGenerator].
  ///
  /// [pressureBar] is clamped to ≥ 0.
  /// If [start] has not been called this call is silently ignored.
  void record({
    required double pressureBar,
    required String phase,
  }) {
    if (_startTime == null) return; // guard: must call start() first

    final timeSeconds =
        DateTime.now().difference(_startTime!).inMilliseconds / 1000.0;

    // Clamp pressure to ≥ 0 — negative gauge readings are unphysical.
    final clampedPressure = math.max(0.0, pressureBar);

    _points.add(WeldTracePoint(
      timeSeconds:  timeSeconds,
      pressureBar:  clampedPressure,
      phase:        phase,
    ));
  }

  /// Returns an immutable snapshot of the recorded curve.
  ///
  /// Safe to call even if the recorder has not been started (returns empty
  /// list) or has fewer than 10 samples (no minimum is enforced).
  List<WeldTracePoint> export() => List.unmodifiable(_points);

  // ── Derived statistics ──────────────────────────────────────────────────────

  /// Maximum pressure recorded across all samples.  Returns 0 on empty curve.
  double get maxPressureBar {
    if (_points.isEmpty) return 0;
    return _points.map((p) => p.pressureBar).reduce(math.max);
  }

  /// Mean pressure across all samples.  Returns 0 on empty curve.
  double get averagePressureBar {
    if (_points.isEmpty) return 0;
    return _points.map((p) => p.pressureBar).reduce((a, b) => a + b) /
        _points.length;
  }

  /// Elapsed recording time from the first to the last sample [s].
  /// Returns 0 if fewer than 2 samples.
  double get recordedDurationSeconds {
    if (_points.length < 2) return 0;
    return _points.last.timeSeconds - _points.first.timeSeconds;
  }
}
