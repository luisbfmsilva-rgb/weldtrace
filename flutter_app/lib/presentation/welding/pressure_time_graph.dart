import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../services/sensor/sensor_reading.dart';
import '../../workflow/welding_phase.dart';
import 'nominal_curve_builder.dart';

// ── Chart mode ────────────────────────────────────────────────────────────────

enum ChartMode {
  /// DVS-style: X axis normalized so every stage occupies a fixed visual
  /// proportion, regardless of its real duration.
  operational,

  /// Real-time: X axis in seconds with a sliding 5-minute window.
  technical,
}

// ── Visual stage weights for Operational Mode ─────────────────────────────────
//
// The total must equal 1.0.  Stages not listed fall back to an even
// distribution of the remaining weight.

const _stageWeights = {
  WeldingPhase.beadUpAdjust: 0.05,
  WeldingPhase.heatingUp:    0.15,
  WeldingPhase.heating:      0.20,
  WeldingPhase.changeover:   0.10,
  WeldingPhase.buildup:      0.15,
  WeldingPhase.fusion:       0.05,
  WeldingPhase.cooling:      0.30,
};

// ── Normalization helpers ─────────────────────────────────────────────────────

/// Converts a list of [FlSpot] from real-time coordinates to normalized
/// coordinates given [phases].  Used for both actual and nominal series.
///
/// normalizedEnd is 100 (i.e. 100 % = "end of weld").
List<FlSpot> normalizeSpots(
  List<FlSpot> realSpots,
  List<PhaseParameters> phases,
) {
  if (phases.isEmpty || realSpots.isEmpty) return realSpots;

  // Build real start/end for each phase
  final starts = <double>[];
  double cursor = 0;
  for (final p in phases) {
    starts.add(cursor);
    cursor += p.nominalDuration;
  }
  final totalReal = cursor;

  // Resolve visual weights
  double allocatedWeight = 0;
  int unweighted = 0;
  for (final p in phases) {
    final w = _stageWeights[p.phase];
    if (w != null) {
      allocatedWeight += w;
    } else {
      unweighted++;
    }
  }
  final remainingWeight = (1.0 - allocatedWeight).clamp(0.0, 1.0);
  final perUnweighted   = unweighted > 0 ? remainingWeight / unweighted : 0.0;

  List<double> weights = phases.map((p) {
    return _stageWeights[p.phase] ?? perUnweighted;
  }).toList();

  // Normalize each spot
  final normalized = <FlSpot>[];
  for (final s in realSpots) {
    final t = s.x;
    if (t < 0) continue;
    if (t > totalReal + 0.001) {
      // Out of range — clamp to 100 %
      normalized.add(FlSpot(100, s.y));
      continue;
    }

    // Find the phase this point belongs to
    int phaseIdx = phases.length - 1;
    for (int i = 0; i < phases.length; i++) {
      final nextStart = (i + 1 < phases.length) ? starts[i + 1] : totalReal;
      if (t < nextStart || i == phases.length - 1) {
        phaseIdx = i;
        break;
      }
    }

    // Normalized start of the phase
    double normStart = 0;
    for (int j = 0; j < phaseIdx; j++) {
      normStart += weights[j];
    }

    // Position within phase (0..1)
    final realDuration = phases[phaseIdx].nominalDuration;
    final posInPhase = realDuration > 0
        ? (t - starts[phaseIdx]) / realDuration
        : 0.0;

    final normX = (normStart + posInPhase * weights[phaseIdx]) * 100.0;
    normalized.add(FlSpot(normX.clamp(0.0, 100.0), s.y));
  }
  return normalized;
}

// ── PressureTimeGraph ─────────────────────────────────────────────────────────

/// Dual-mode pressure × time chart for the welding session screen.
///
/// **Operational Mode** (default, DVS-style):
///   • X axis = 0–100 % (normalized, each phase proportional to its weight)
///   • Phase labels always visible
///
/// **Technical Mode** (real-time):
///   • X axis = seconds from weld start
///   • Sliding 5-minute window follows live data
class PressureTimeGraph extends StatefulWidget {
  const PressureTimeGraph({
    super.key,
    required this.phases,
    required this.nominalData,
    required this.readings,
    required this.weldStartedAt,
    required this.currentPhaseIndex,
    this.height = 280,
    this.showModeToggle = true,
  });

  final List<PhaseParameters> phases;
  final NominalCurveData nominalData;
  final List<SensorReading> readings;
  final DateTime weldStartedAt;
  final int currentPhaseIndex;
  final double height;

  /// Whether to render the Operational / Technical toggle button.
  final bool showModeToggle;

  @override
  State<PressureTimeGraph> createState() => _PressureTimeGraphState();

  // ── Static utility: build spots for PDF (always operational mode) ──────────

  /// Build normalized actual-pressure spots for embedding in a PDF report.
  static List<FlSpot> buildNormalizedActualSpots(
    List<SensorReading> readings,
    DateTime weldStartedAt,
    List<PhaseParameters> phases,
  ) {
    final raw = <FlSpot>[];
    for (final r in readings) {
      if (r.pressureBar == null) continue;
      final t = r.recordedAt.difference(weldStartedAt).inMilliseconds / 1000.0;
      if (t < 0) continue;
      raw.add(FlSpot(t, r.pressureBar!));
    }
    return normalizeSpots(raw, phases);
  }

  /// Build normalized nominal-curve spots for embedding in a PDF report.
  static List<FlSpot> buildNormalizedNominalSpots(
    NominalCurveData nominalData,
    List<PhaseParameters> phases,
  ) => normalizeSpots(nominalData.nominalSpots, phases);
}

class _PressureTimeGraphState extends State<PressureTimeGraph> {
  ChartMode _mode = ChartMode.operational;

  // ── Chart line indices ──────────────────────────────────────────────────────
  static const _idxActual   = 0;
  // ignore: unused_field
  static const _idxNominal  = 1;
  static const _idxMinBand  = 2;
  static const _idxMaxBand  = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final actualRaw = _buildActualRawSpots();
    final isOperational = _mode == ChartMode.operational;

    final actualSpots  = isOperational
        ? normalizeSpots(actualRaw, widget.phases)
        : actualRaw;

    final nominalSpots = isOperational
        ? normalizeSpots(widget.nominalData.nominalSpots, widget.phases)
        : widget.nominalData.nominalSpots;

    final minBandSpots = isOperational
        ? normalizeSpots(widget.nominalData.minBandSpots, widget.phases)
        : widget.nominalData.minBandSpots;

    final maxBandSpots = isOperational
        ? normalizeSpots(widget.nominalData.maxBandSpots, widget.phases)
        : widget.nominalData.maxBandSpots;

    final xMax = _computeXMax(isOperational, actualSpots);
    final xMin = _computeXMin(isOperational, actualSpots);
    final yMax = _computeYMax(actualSpots);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Mode toggle ────────────────────────────────────────────────────
        if (widget.showModeToggle)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ModeToggle(
              current: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
          ),

        // ── Chart ──────────────────────────────────────────────────────────
        Container(
          height: widget.height,
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
            _buildChartData(
              theme: theme,
              actualSpots:  actualSpots,
              nominalSpots: nominalSpots,
              minBandSpots: minBandSpots,
              maxBandSpots: maxBandSpots,
              xMin: xMin,
              xMax: xMax,
              yMax: yMax,
              isOperational: isOperational,
            ),
            duration: Duration.zero,
          ),
        ),

        // ── Legend ─────────────────────────────────────────────────────────
        const SizedBox(height: 6),
        _ChartLegend(isOperational: isOperational),
      ],
    );
  }

  // ── Spot builders ─────────────────────────────────────────────────────────

  List<FlSpot> _buildActualRawSpots() {
    final spots = <FlSpot>[];
    for (final r in widget.readings) {
      if (r.pressureBar == null) continue;
      final t = r.recordedAt
          .difference(widget.weldStartedAt)
          .inMilliseconds / 1000.0;
      if (t < 0) continue;
      spots.add(FlSpot(t, r.pressureBar!));
    }
    return spots;
  }

  // ── Domain calculation ────────────────────────────────────────────────────

  double _computeXMax(bool isOperational, List<FlSpot> actualSpots) {
    if (isOperational) return 100.0;          // always 0–100 % in OP mode
    // Technical: sliding window — show last 300 s; minimum range = 30 s
    if (actualSpots.isEmpty) {
      return math.max(widget.nominalData.totalDuration * 1.08, 30.0);
    }
    final latest = actualSpots.last.x;
    return math.max(latest + 10, 300.0);
  }

  double _computeXMin(bool isOperational, List<FlSpot> actualSpots) {
    if (isOperational) return 0.0;
    if (actualSpots.isEmpty) return 0.0;
    final latest = actualSpots.last.x;
    return math.max(0.0, latest - 300.0);    // 5-minute sliding window
  }

  double _computeYMax(List<FlSpot> spots) {
    var yMax = widget.nominalData.maxPressure;
    for (final s in spots) {
      if (s.y > yMax) yMax = s.y * 1.1;
    }
    return yMax < 0.5 ? 2.0 : yMax;
  }

  // ── Chart data ────────────────────────────────────────────────────────────

  LineChartData _buildChartData({
    required ThemeData     theme,
    required List<FlSpot>  actualSpots,
    required List<FlSpot>  nominalSpots,
    required List<FlSpot>  minBandSpots,
    required List<FlSpot>  maxBandSpots,
    required double        xMin,
    required double        xMax,
    required double        yMax,
    required bool          isOperational,
  }) {
    return LineChartData(
      minX: xMin,
      maxX: xMax,
      minY: 0,
      maxY: yMax,

      clipData: const FlClipData.all(),

      // ── Grid ───────────────────────────────────────────────────────────
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: _niceInterval(yMax, 5),
        verticalInterval: isOperational
            ? 10.0   // every 10 % in OP mode
            : _niceInterval(xMax - xMin, 6),
        getDrawingHorizontalLine: (_) => FlLine(
          color: theme.colorScheme.outline.withOpacity(0.12),
          strokeWidth: 1,
        ),
        getDrawingVerticalLine: (_) => FlLine(
          color: theme.colorScheme.outline.withOpacity(0.10),
          strokeWidth: 1,
        ),
      ),

      // ── Axes titles ────────────────────────────────────────────────────
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget: _AxisLabel(label: 'P (bar)', rotate: true),
          axisNameSize: 22,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            interval: _niceInterval(yMax, 5),
            getTitlesWidget: (v, _) => _YTitle(value: v),
          ),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: _AxisLabel(
            label: isOperational ? 'Progress (%)' : 'Time (s)',
            rotate: false,
          ),
          axisNameSize: 18,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: isOperational ? 10.0 : _niceInterval(xMax - xMin, 6),
            getTitlesWidget: (v, m) => isOperational
                ? _XTitlePct(value: v)
                : _XTitle(value: v),
          ),
        ),
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),

      // ── Border ────────────────────────────────────────────────────────
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3), width: 1),
          left:   BorderSide(color: theme.colorScheme.outline.withOpacity(0.3), width: 1),
          top:    BorderSide.none,
          right:  BorderSide.none,
        ),
      ),

      // ── Tooltip ────────────────────────────────────────────────────────
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (spots) => spots.map((s) {
            if (s.barIndex == _idxActual) {
              final xLabel = isOperational
                  ? '${s.x.toStringAsFixed(1)} %'
                  : 't=${s.x.toStringAsFixed(1)} s';
              return LineTooltipItem(
                '$xLabel\n${s.y.toStringAsFixed(3)} bar',
                const TextStyle(color: Colors.white, fontSize: 11, height: 1.5),
              );
            }
            return null;
          }).toList(),
        ),
      ),

      // ── Phase marker vertical lines (normalized if OP mode) ────────────
      extraLinesData: ExtraLinesData(
        verticalLines: _buildPhaseMarkerLines(theme, yMax, isOperational),
      ),

      // ── Line series ────────────────────────────────────────────────────
      lineBarsData: [
        _actualLine(actualSpots),           // 0 — real pressure (red, solid)
        _nominalLine(nominalSpots),          // 1 — ideal pressure (black, dashed)
        _bandEdgeLine(minBandSpots),         // 2 — min-band edge (transparent)
        _bandEdgeLine(maxBandSpots),         // 3 — max-band edge (transparent)
      ],

      // ── Tolerance band shading ─────────────────────────────────────────
      betweenBarsData: [
        BetweenBarsData(
          fromIndex: _idxMinBand,
          toIndex:   _idxMaxBand,
          color: const Color(0xFF0052CC).withOpacity(0.07),
        ),
      ],
    );
  }

  // ── Line definitions ──────────────────────────────────────────────────────

  LineChartBarData _actualLine(List<FlSpot> spots) => LineChartBarData(
        spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
        isCurved: false,
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

  LineChartBarData _nominalLine(List<FlSpot> spots) => LineChartBarData(
        spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
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

  List<VerticalLine> _buildPhaseMarkerLines(
    ThemeData theme,
    double yMax,
    bool isOperational,
  ) {
    final markers  = widget.nominalData.phaseMarkers;
    final phases   = widget.phases;
    final lines    = <VerticalLine>[];

    for (int i = 0; i < markers.length; i++) {
      final marker = markers[i];
      double xPos  = marker.timeSeconds; // default: real seconds

      if (isOperational && phases.isNotEmpty) {
        // Map real timestamp to normalized 0–100 using normalizeSpots
        final normalized = normalizeSpots(
          [FlSpot(marker.timeSeconds, 0)],
          phases,
        );
        xPos = normalized.isNotEmpty ? normalized.first.x : xPos;
      }

      final isActive = marker.isActive;
      final color = isActive
          ? const Color(0xFF0052CC).withOpacity(0.55)
          : theme.colorScheme.outline.withOpacity(0.25);

      lines.add(VerticalLine(
        x: xPos,
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
            final name = marker.label;
            return name.length > 8 ? '${name.substring(0, 7)}…' : name;
          },
        ),
      ));
    }
    return lines;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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

// ── Mode toggle button ────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.current, required this.onChanged});
  final ChartMode current;
  final ValueChanged<ChartMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleChip(
          label: 'Operational',
          icon: Icons.show_chart,
          selected: current == ChartMode.operational,
          onTap: () => onChanged(ChartMode.operational),
          theme: theme,
        ),
        const SizedBox(width: 6),
        _ToggleChip(
          label: 'Technical',
          icon: Icons.timeline,
          selected: current == ChartMode.technical,
          onTap: () => onChanged(ChartMode.technical),
          theme: theme,
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String    label;
  final IconData  icon;
  final bool      selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bg  = selected ? theme.colorScheme.primary : Colors.transparent;
    final fg  = selected ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.6);
    final bdr = selected ? Colors.transparent : theme.colorScheme.outline.withOpacity(0.3);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: bdr),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.isOperational});
  final bool isOperational;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withOpacity(0.5);
    return Row(
      children: [
        _LegendDot(color: const Color(0xFFD32F2F), dashed: false),
        const SizedBox(width: 4),
        Text('Real', style: TextStyle(fontSize: 10, color: color)),
        const SizedBox(width: 12),
        _LegendDot(color: Colors.black87, dashed: true),
        const SizedBox(width: 4),
        Text(
          isOperational ? 'Ideal (DVS)' : 'Nominal',
          style: TextStyle(fontSize: 10, color: color),
        ),
        const SizedBox(width: 12),
        Container(width: 18, height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF0052CC).withOpacity(0.12),
            border: Border.all(color: const Color(0xFF0052CC).withOpacity(0.2)),
          ),
        ),
        const SizedBox(width: 4),
        Text('Tolerance', style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.dashed});
  final Color color;
  final bool  dashed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 2,
      child: CustomPaint(
        painter: _LinePainter(color: color, dashed: dashed),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({required this.color, required this.dashed});
  final Color color;
  final bool  dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), paint);
    } else {
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset(math.min(x + 4, size.width), size.height / 2),
          paint,
        );
        x += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.color != color || old.dashed != dashed;
}

// ── Small axis label widgets ──────────────────────────────────────────────────

class _AxisLabel extends StatelessWidget {
  const _AxisLabel({required this.label, required this.rotate});
  final String label;
  final bool   rotate;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 10,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
      ),
    );
    return rotate ? RotatedBox(quarterTurns: 3, child: text) : text;
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
  Widget build(BuildContext context) => Text(
        value.toStringAsFixed(0),
        style: TextStyle(
          fontSize: 9,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        ),
      );
}

class _XTitlePct extends StatelessWidget {
  const _XTitlePct({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Text(
        '${value.toStringAsFixed(0)}%',
        style: TextStyle(
          fontSize: 8,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        ),
      );
}

// ── PressureGraphLegend ───────────────────────────────────────────────────────

/// Small header bar placed above [PressureTimeGraph] in the session screen.
/// Shows the active phase name and live sensor reading count.
class PressureGraphLegend extends StatelessWidget {
  const PressureGraphLegend({
    super.key,
    required this.currentPhaseName,
    required this.readingCount,
  });

  final String currentPhaseName;
  final int    readingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              currentPhaseName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '$readingCount pts',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withOpacity(0.45),
            ),
          ),
        ],
      ),
    );
  }
}
