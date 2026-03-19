import 'package:fl_chart/fl_chart.dart';

import '../../workflow/welding_phase.dart';

/// Pre-computed chart data derived purely from [PhaseParameters].
/// Created once per weld session and passed to [PressureTimeGraph].
class NominalCurveData {
  const NominalCurveData({
    required this.nominalSpots,
    required this.minBandSpots,
    required this.maxBandSpots,
    required this.phaseMarkers,
    required this.totalDuration,
    required this.maxPressure,
  });

  /// Step-function spots for the nominal pressure line.
  final List<FlSpot> nominalSpots;

  /// Step-function spots for the lower tolerance boundary (shaded band).
  final List<FlSpot> minBandSpots;

  /// Step-function spots for the upper tolerance boundary (shaded band).
  final List<FlSpot> maxBandSpots;

  /// Phase boundary information used to draw vertical marker lines.
  final List<PhaseMarker> phaseMarkers;

  /// Sum of all nominal phase durations (seconds). Used for x-axis range.
  final double totalDuration;

  /// Largest pressure value across nominal + bands. Used for y-axis ceiling.
  final double maxPressure;
}

/// Describes a vertical phase-boundary marker line on the chart.
class PhaseMarker {
  const PhaseMarker({
    required this.timeSeconds,
    required this.label,
    required this.isActive,
  });

  /// X position (seconds from weld start).
  final double timeSeconds;

  /// Phase display name shown on the chart.
  final String label;

  /// Whether this is the currently active phase (rendered differently).
  final bool isActive;
}

/// Builds all fl_chart data needed by [PressureTimeGraph] from a list
/// of [PhaseParameters].  The algorithm is a pure function — no side effects.
///
/// Nominal pressure curve:
///   Each phase contributes a horizontal step at [nominalPressureBar].
///   Phases with no pressure monitoring (nominalPressureBar == null)
///   are rendered at 0 bar (e.g. changeover / clamping).
///
/// Tolerance band:
///   Upper and lower spots mirror the nominal step shape but use
///   [minPressureBar] / [maxPressureBar] respectively.
///   Phases with no limits use the nominal value (zero-width band).
class NominalCurveBuilder {
  NominalCurveBuilder._();

  /// Build [NominalCurveData] from a list of phases.
  ///
  /// [currentPhaseIndex] is used to mark the active phase on each marker.
  static NominalCurveData build(
    List<PhaseParameters> phases, {
    int currentPhaseIndex = 0,
  }) {
    if (phases.isEmpty) {
      return const NominalCurveData(
        nominalSpots: [],
        minBandSpots: [],
        maxBandSpots: [],
        phaseMarkers: [],
        totalDuration: 1,
        maxPressure: 1,
      );
    }

    final nominalSpots = <FlSpot>[];
    final minSpots = <FlSpot>[];
    final maxSpots = <FlSpot>[];
    final markers = <PhaseMarker>[];

    double cursor = 0; // seconds from weld start
    double globalMax = 0.5; // ensure y-axis never collapses to zero

    for (int i = 0; i < phases.length; i++) {
      final p = phases[i];
      final nominal = p.nominalPressureBar ?? 0.0;
      final min = p.minPressureBar ?? nominal;
      final max = p.maxPressureBar ?? nominal;
      final end = cursor + p.nominalDuration;

      // Phase-start boundary marker (skip first — it's t=0)
      if (cursor > 0) {
        markers.add(PhaseMarker(
          timeSeconds: cursor,
          label: p.phase.displayName,
          isActive: i == currentPhaseIndex,
        ));
      } else {
        // Add t=0 marker for the first phase label
        markers.add(PhaseMarker(
          timeSeconds: 0,
          label: p.phase.displayName,
          isActive: i == currentPhaseIndex,
        ));
      }

      // Step: at phase start and phase end, hold the same value
      // Adding two spots at slightly different x positions creates a
      // perfectly vertical step transition.
      if (nominalSpots.isNotEmpty) {
        // Vertical drop/rise: one spot at the phase boundary with old value,
        // immediately followed by one with new value
        final prevNominal = nominalSpots.last.y;
        final prevMin = minSpots.last.y;
        final prevMax = maxSpots.last.y;
        nominalSpots.add(FlSpot(cursor, prevNominal));
        minSpots.add(FlSpot(cursor, prevMin));
        maxSpots.add(FlSpot(cursor, prevMax));
      }

      nominalSpots.add(FlSpot(cursor, nominal));
      nominalSpots.add(FlSpot(end, nominal));
      minSpots.add(FlSpot(cursor, min));
      minSpots.add(FlSpot(end, min));
      maxSpots.add(FlSpot(cursor, max));
      maxSpots.add(FlSpot(end, max));

      if (max > globalMax) globalMax = max;
      if (nominal > globalMax) globalMax = nominal;
      cursor = end;
    }

    // Extend the chart 8% past the total duration for breathing room
    final totalDuration = cursor;

    return NominalCurveData(
      nominalSpots: nominalSpots,
      minBandSpots: minSpots,
      maxBandSpots: maxSpots,
      phaseMarkers: markers,
      totalDuration: totalDuration,
      maxPressure: globalMax * 1.25,
    );
  }

  /// Recomputes only the [PhaseMarker.isActive] flags when the current
  /// phase changes — cheaper than rebuilding the entire curve.
  static NominalCurveData updateActivePhase(
    NominalCurveData data,
    List<PhaseParameters> phases,
    int currentPhaseIndex,
  ) {
    final updatedMarkers = <PhaseMarker>[];

    for (int i = 0; i < data.phaseMarkers.length; i++) {
      updatedMarkers.add(PhaseMarker(
        timeSeconds: data.phaseMarkers[i].timeSeconds,
        label: data.phaseMarkers[i].label,
        isActive: i == currentPhaseIndex,
      ));
    }

    return NominalCurveData(
      nominalSpots: data.nominalSpots,
      minBandSpots: data.minBandSpots,
      maxBandSpots: data.maxBandSpots,
      phaseMarkers: updatedMarkers,
      totalDuration: data.totalDuration,
      maxPressure: data.maxPressure,
    );
  }
}
