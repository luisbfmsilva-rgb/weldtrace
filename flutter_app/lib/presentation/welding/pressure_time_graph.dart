import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../services/sensor/sensor_reading.dart';
import '../../workflow/welding_phase.dart';
import 'nominal_curve_builder.dart';

/// Real-time pressure vs time chart for the welding session screen.
///
/// Renders three layers over a shared time axis (seconds from weld start):
///
///   1. Tolerance band — grey shaded area between min and max pressure,
///      derived from [NominalCurveData.minBandSpots] /
///      [NominalCurveData.maxBandSpots].
///
///   2. Nominal pressure curve — black step-function line showing the
///      target pressure for each phase.
///
///   3. Actual pressure curve — red line updated at 1 Hz from the
///      sensor stream.
///
/// Phase transitions are drawn as semi-transparent vertical lines with
/// the phase name as a rotated label.
///
/// This widget is stateless — all mutable data is owned by the parent
/// ([WeldingSessionScreen]) and passed in via constructor arguments.
class PressureTimeGraph extends StatelessWidget {
  const PressureTimeGraph({
    super.key,
    required this.phases,
    required this.nominalData,
    required this.readings,
    required this.weldStartedAt,
    required this.currentPhaseIndex,
    this.height = 260,
  });

  final List<PhaseParameters> phases;

  /// Pre-built nominal/band data from [NominalCurveBuilder].
  final NominalCurveData nominalData;

  /// Live sensor readings accumulated since [weldStartedAt].
  final List<SensorReading> readings;

  final DateTime weldStartedAt;
  final int currentPhaseIndex;
  final double height;

  // ── Chart line indices ────────────────────────────────────────────────────
  //   0: actual readings    (red)
  //   1: nominal curve      (black)
  //   2: min-band edge      (transparent — used for BetweenBarsData)
  //   3: max-band edge      (transparent — used for BetweenBarsData)
  static const _idxActual = 0;
  static const _idxNominal = 1;
  static const _idxMinBand = 2;
  static const _idxMaxBand = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actualSpots = _buildActualSpots();
    final xMax = _computeXMax(actualSpots);

    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LineChart(
        _buildChartData(theme, actualSpots, xMax),
        duration: Duration.zero,   // disable animation for real-time rendering
      ),
    );
  }

  // ── Spot builders ─────────────────────────────────────────────────────────

  List<FlSpot> _buildActualSpots() {
    final spots = <FlSpot>[];
    for (final r in readings) {
      if (r.pressureBar == null) continue;
      final t = r.recordedAt.difference(weldStartedAt).inMilliseconds / 1000.0;
      if (t < 0) continue;
      spots.add(FlSpot(t, r.pressureBar!));
    }
    return spots;
  }

  double _computeXMax(List<FlSpot> actualSpots) {
    final dataMax = actualSpots.isEmpty ? 0.0 : actualSpots.last.x;
    return (dataMax > nominalData.totalDuration
            ? dataMax * 1.05
            : nominalData.totalDuration * 1.08)
        .clamp(10.0, double.infinity);
  }

  // ── Chart data ────────────────────────────────────────────────────────────

  LineChartData _buildChartData(
    ThemeData theme,
    List<FlSpot> actualSpots,
    double xMax,
  ) {
    final yMax = _computeYMax(actualSpots);

    return LineChartData(
      // ── Axes ─────────────────────────────────────────────────────────────
      minX: 0,
      maxX: xMax,
      minY: 0,
      maxY: yMax,

      // ── Grid ─────────────────────────────────────────────────────────────
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: _niceInterval(yMax, 5),
        verticalInterval: _niceInterval(xMax, 6),
        getDrawingHorizontalLine: (v) => FlLine(
          color: theme.colorScheme.outline.withOpacity(0.12),
          strokeWidth: 1,
        ),
        getDrawingVerticalLine: (v) => FlLine(
          color: theme.colorScheme.outline.withOpacity(0.10),
          strokeWidth: 1,
        ),
      ),

      // ── Titles ───────────────────────────────────────────────────────────
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget: _AxisLabel(label: 'Pressure (bar)', rotate: true),
          axisNameSize: 22,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            interval: _niceInterval(yMax, 5),
            getTitlesWidget: (v, meta) => _YTitle(value: v),
          ),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: _AxisLabel(label: 'Time (s)', rotate: false),
          axisNameSize: 18,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: _niceInterval(xMax, 6),
            getTitlesWidget: (v, meta) => _XTitle(value: v),
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),

      // ── Border ───────────────────────────────────────────────────────────
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outline.withOpacity(0.3), width: 1),
          left: BorderSide(
              color: theme.colorScheme.outline.withOpacity(0.3), width: 1),
        ),
      ),

      // ── Tooltip ──────────────────────────────────────────────────────────
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (spots) {
            return spots.map((s) {
              if (s.barIndex == _idxActual) {
                return LineTooltipItem(
                  't=${s.x.toStringAsFixed(1)}s\n'
                  '${s.y.toStringAsFixed(3)} bar',
                  const TextStyle(
                      color: Colors.white, fontSize: 11, height: 1.5),
                );
              }
              return null;
            }).toList();
          },
        ),
      ),

      // ── Phase marker vertical lines ───────────────────────────────────────
      extraLinesData: ExtraLinesData(
        verticalLines: _buildPhaseMarkerLines(theme, yMax),
      ),

      // ── Line series ───────────────────────────────────────────────────────
      lineBarsData: [
        _actualLine(actualSpots, theme),
        _nominalLine(theme),
        _bandEdgeLine(nominalData.minBandSpots),
        _bandEdgeLine(nominalData.maxBandSpots),
      ],

      // ── Tolerance band shading (between minBand and maxBand lines) ────────
      betweenBarsData: [
        BetweenBarsData(
          fromIndex: _idxMinBand,
          toIndex: _idxMaxBand,
          color: const Color(0xFF0052CC).withOpacity(0.07),
        ),
      ],

      clipData: const FlClipData.all(),
    );
  }

  // ── Line definitions ──────────────────────────────────────────────────────

  LineChartBarData _actualLine(List<FlSpot> spots, ThemeData theme) =>
      LineChartBarData(
        spots: spots.isEmpty
            ? [const FlSpot(0, 0)] // prevent fl_chart crash on empty list
            : spots,
        isCurved: false,           // straight line between 1Hz samples
        color: const Color(0xFFD32F2F),
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
        shadow: const Shadow(
          color: Color(0x30D32F2F),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      );

  LineChartBarData _nominalLine(ThemeData theme) => LineChartBarData(
        spots: nominalData.nominalSpots.isEmpty
            ? [const FlSpot(0, 0)]
            : nominalData.nominalSpots,
        isCurved: false,
        color: Colors.black87,
        barWidth: 1.5,
        isStrokeCapRound: false,
        dotData: const FlDotData(show: false),
        dashArray: [6, 3],
        belowBarData: BarAreaData(show: false),
      );

  LineChartBarData _bandEdgeLine(List<FlSpot> spots) => LineChartBarData(
        spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
        isCurved: false,
        color: Colors.transparent,
        barWidth: 0,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );

  // ── Phase marker lines ────────────────────────────────────────────────────

  List<VerticalLine> _buildPhaseMarkerLines(ThemeData theme, double yMax) {
    return nominalData.phaseMarkers.map((marker) {
      final isActive = marker.isActive;
      final color = isActive
          ? const Color(0xFF0052CC).withOpacity(0.55)
          : theme.colorScheme.outline.withOpacity(0.25);

      return VerticalLine(
        x: marker.timeSeconds,
        color: color,
        strokeWidth: isActive ? 1.5 : 1.0,
        dashArray: [4, 4],
        label: VerticalLineLabel(
          show: true,
          alignment: Alignment.topRight,
          style: TextStyle(
            fontSize: 8,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: isActive
                ? const Color(0xFF0052CC)
                : theme.colorScheme.outline.withOpacity(0.6),
          ),
          labelResolver: (_) {
            // Abbreviate long phase names to keep labels compact
            final name = marker.label;
            return name.length > 8 ? '${name.substring(0, 7)}…' : name;
          },
        ),
      );
    }).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double _computeYMax(List<FlSpot> actualSpots) {
    var yMax = nominalData.maxPressure;
    for (final s in actualSpots) {
      if (s.y > yMax) yMax = s.y * 1.1;
    }
    return yMax == 0 ? 2.0 : yMax;
  }

  /// Returns a "nice" grid interval: the range divided by [targetCount],
  /// rounded up to the nearest 1, 2, 5 or 10 × power-of-10.
  static double _niceInterval(double range, int targetCount) {
    if (range <= 0) return 1;
    final raw = range / targetCount;
    if (raw <= 0) return 1;
    final magnitude =
        math.pow(10, (math.log(raw) / math.ln10).floorToDouble()).toDouble();
    final normalised = raw / magnitude;
    double nice;
    if (normalised <= 1) {
      nice = 1;
    } else if (normalised <= 2) {
      nice = 2;
    } else if (normalised <= 5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * magnitude;
  }
}

// ── Small axis label widgets ──────────────────────────────────────────────────

class _AxisLabel extends StatelessWidget {
  const _AxisLabel({required this.label, required this.rotate});
  final String label;
  final bool rotate;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 10,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
      ),
    );
    return rotate
        ? RotatedBox(quarterTurns: 3, child: text)
        : text;
  }
}

class _YTitle extends StatelessWidget {
  const _YTitle({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(
          value.toStringAsFixed(value < 10 ? 1 : 0),
          style: TextStyle(
            fontSize: 9,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          textAlign: TextAlign.right,
        ),
      );
}

class _XTitle extends StatelessWidget {
  const _XTitle({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          value >= 60
              ? '${(value ~/ 60)}m${(value % 60).toInt() > 0 ? (value % 60).toInt().toString() + 's' : ''}'
              : '${value.toInt()}s',
          style: TextStyle(
            fontSize: 9,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          textAlign: TextAlign.center,
        ),
      );
}

// ── Legend widget ─────────────────────────────────────────────────────────────

/// Compact legend displayed above [PressureTimeGraph].
class PressureGraphLegend extends StatelessWidget {
  const PressureGraphLegend({
    super.key,
    required this.currentPhaseName,
    required this.readingCount,
  });

  final String currentPhaseName;
  final int readingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          _LegendDot(color: const Color(0xFFD32F2F), label: 'Actual'),
          const SizedBox(width: 16),
          _LegendDot(
              color: Colors.black87,
              label: 'Nominal',
              isDashed: true),
          const SizedBox(width: 16),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF0052CC).withOpacity(0.12),
              border: Border.all(
                  color: const Color(0xFF0052CC).withOpacity(0.3), width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Text('Tolerance band',
              style: TextStyle(
                  fontSize: 10,
                  color:
                      theme.colorScheme.onSurface.withOpacity(0.55))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0052CC).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              currentPhaseName,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0052CC)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$readingCount pts',
            style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withOpacity(0.4)),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(
      {required this.color, required this.label, this.isDashed = false});
  final Color color;
  final String label;
  final bool isDashed;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(20, 2),
            painter: _LinePainter(color: color, dashed: isDashed),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.6)),
          ),
        ],
      );
}

class _LinePainter extends CustomPainter {
  const _LinePainter({required this.color, required this.dashed});
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      const dashW = 4.0;
      const gapW = 2.0;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
            Offset(x, y), Offset((x + dashW).clamp(0, size.width), y), paint);
        x += dashW + gapW;
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.color != color;
}
