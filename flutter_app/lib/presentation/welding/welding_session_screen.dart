import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../di/providers.dart';
import '../../services/sensor/sensor_service.dart';
import '../../services/sensor/sensor_reading.dart';
import '../../workflow/weld_workflow_engine.dart';
import '../../workflow/welding_phase.dart';
import 'nominal_curve_builder.dart';
import 'pressure_time_graph.dart';

/// Arguments passed via GoRouter [extra] from WeldSetupScreen.
class WeldSessionArgs {
  const WeldSessionArgs({
    required this.weldId,
    required this.phases,
  });

  final String weldId;
  final List<PhaseParameters> phases;
}

/// Live welding session screen.
///
/// Receives a pre-created [weldId] (already written to local SQLite) and
/// the ordered [phases] computed from the welding parameters lookup.
///
/// Responsibilities:
///   - Instantiates [WeldWorkflowEngine] for phase state machine
///   - Subscribes to [SensorService] for live pressure / temperature
///   - Displays phase progress, live values, violation banners
///   - Handles manual phase advance, weld completion, and cancellation
class WeldingSessionScreen extends ConsumerStatefulWidget {
  const WeldingSessionScreen({
    super.key,
    required this.weldId,
    required this.phases,
  });

  final String weldId;
  final List<PhaseParameters> phases;

  @override
  ConsumerState<WeldingSessionScreen> createState() =>
      _WeldingSessionScreenState();
}

class _WeldingSessionScreenState extends ConsumerState<WeldingSessionScreen> {
  WeldWorkflowEngine? _engine;

  WeldWorkflowState _workflowState = WeldWorkflowState.idle;
  SensorConnectionState _sensorState = SensorConnectionState.disconnected;
  double? _latestPressure;
  double? _latestTemperature;
  final List<ParameterViolation> _violations = [];

  int _currentPhaseIndex = 0;
  DateTime? _phaseStartedAt;
  Timer? _phaseTimer;
  int _phaseElapsedSeconds = 0;

  // ── Chart state ─────────────────────────────────────────────────────────────
  /// Accumulated 1-Hz readings for the actual pressure curve.
  final List<SensorReading> _sensorReadings = [];

  /// Timestamp when the first phase started — used as chart x=0.
  DateTime? _weldStartedAt;

  /// Pre-computed nominal curve data derived from [widget.phases].
  late NominalCurveData _nominalData;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _nominalData = NominalCurveBuilder.build(widget.phases);
    _initEngine();
    _listenToSensor();
  }

  void _initEngine() {
    final db = ref.read(databaseProvider);
    final sensor = ref.read(sensorServiceProvider);
    _engine = WeldWorkflowEngine(
      db: db,
      sensorService: sensor,
      weldId: widget.weldId,
      phases: widget.phases,
    );

    _subs.add(_engine!.stateStream.listen((s) {
      if (mounted) setState(() => _workflowState = s);
    }));
    _subs.add(_engine!.violationStream.listen((v) {
      if (mounted) setState(() => _violations.add(v));
    }));
  }

  void _listenToSensor() {
    final sensor = ref.read(sensorServiceProvider);
    _subs.add(sensor.readingStream.listen((r) {
      if (mounted) {
        setState(() {
          _latestPressure = r.pressureBar;
          _latestTemperature = r.temperatureCelsius;
          // Accumulate readings for the chart only during an active weld.
          if (_weldStartedAt != null &&
              _workflowState != WeldWorkflowState.completed &&
              _workflowState != WeldWorkflowState.cancelled) {
            _sensorReadings.add(r);
          }
        });
      }
    }));
    _subs.add(sensor.connectionStateStream.listen((s) {
      if (mounted) setState(() => _sensorState = s);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _phaseTimer?.cancel();
    _engine?.dispose();
    super.dispose();
  }

  // ── Phase management ──────────────────────────────────────────────────────

  Future<void> _startNextPhase() async {
    await _engine?.advancePhase();
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _currentPhaseIndex = _engine != null
          ? (_engine!.state == WeldWorkflowState.completed
              ? widget.phases.length
              : widget.phases.length - 1)
          : 0;
      _phaseStartedAt = now;
      _phaseElapsedSeconds = 0;
      _violations.clear();
      // Record the weld-level start time the very first time a phase begins.
      _weldStartedAt ??= now;
      // Refresh phase marker highlight on the nominal curve.
      _nominalData = NominalCurveBuilder.updateActivePhase(
        _nominalData,
        widget.phases,
        _currentPhaseIndex,
      );
    });
    _startPhaseTimer();
  }

  Future<void> _completePhase() async {
    _phaseTimer?.cancel();
    await _engine?.completeCurrentPhase();
    if (!mounted) return;
    setState(() {
      _currentPhaseIndex++;
      _phaseElapsedSeconds = 0;
      // Update active-phase highlight on the chart.
      _nominalData = NominalCurveBuilder.updateActivePhase(
        _nominalData,
        widget.phases,
        _currentPhaseIndex,
      );
    });
  }

  Future<void> _finishWeld() async {
    _phaseTimer?.cancel();
    await _engine?.completeWeld();
  }

  Future<void> _cancelWeld(String reason) async {
    _phaseTimer?.cancel();
    await _engine?.cancel(reason);
  }

  void _startPhaseTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _phaseElapsedSeconds++);
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPhase =
        _currentPhaseIndex < widget.phases.length
            ? widget.phases[_currentPhaseIndex]
            : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Weld · ${widget.weldId.substring(0, 8).toUpperCase()}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_workflowState == WeldWorkflowState.phaseActive ||
                _workflowState == WeldWorkflowState.parameterViolation) {
              _showCancelDialog();
            } else {
              context.go('/projects');
            }
          },
        ),
      ),
      body: Column(
        children: [
          // ── Sensor status bar ────────────────────────────────────────────
          _SensorStatusBar(state: _sensorState),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ── Phase progress stepper ───────────────────────────────
                  _PhaseProgressStepper(
                    phases: widget.phases,
                    currentIndex: _currentPhaseIndex,
                    workflowState: _workflowState,
                  ),
                  const SizedBox(height: 16),

                  // ── Phase timer ──────────────────────────────────────────
                  if (currentPhase != null &&
                      (_workflowState == WeldWorkflowState.phaseActive ||
                          _workflowState ==
                              WeldWorkflowState.parameterViolation))
                    _PhaseTimerCard(
                      phase: currentPhase,
                      elapsedSeconds: _phaseElapsedSeconds,
                    ),
                  const SizedBox(height: 12),

                  // ── Live readings ────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _ReadingCard(
                          label: 'Pressure',
                          value: _latestPressure != null
                              ? '${_latestPressure!.toStringAsFixed(2)} bar'
                              : '— bar',
                          icon: Icons.compress,
                          color: theme.colorScheme.primary,
                          isAlert: currentPhase != null &&
                              _latestPressure != null &&
                              !currentPhase.isPressureInRange(_latestPressure!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ReadingCard(
                          label: 'Temperature',
                          value: _latestTemperature != null
                              ? '${_latestTemperature!.toStringAsFixed(1)} °C'
                              : '— °C',
                          icon: Icons.thermostat,
                          color: theme.colorScheme.error,
                          isAlert: currentPhase != null &&
                              _latestTemperature != null &&
                              !currentPhase
                                  .isTemperatureInRange(_latestTemperature!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Pressure / time chart ────────────────────────────────
                  if (_weldStartedAt != null ||
                      _workflowState == WeldWorkflowState.phaseActive ||
                      _workflowState == WeldWorkflowState.parameterViolation ||
                      _workflowState == WeldWorkflowState.completed) ...[
                    PressureGraphLegend(
                      currentPhaseName: currentPhase?.phase.displayName ??
                          (_workflowState == WeldWorkflowState.completed
                              ? 'Complete'
                              : 'Idle'),
                      readingCount: _sensorReadings.length,
                    ),
                    PressureTimeGraph(
                      phases: widget.phases,
                      nominalData: _nominalData,
                      readings: _sensorReadings,
                      weldStartedAt:
                          _weldStartedAt ?? DateTime.now(),
                      currentPhaseIndex: _currentPhaseIndex,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Violations log ───────────────────────────────────────
                  if (_violations.isNotEmpty)
                    _ViolationsBanner(violations: _violations),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Action buttons ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: _buildActionButtons(context, currentPhase),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, PhaseParameters? currentPhase) {
    final theme = Theme.of(context);

    switch (_workflowState) {
      case WeldWorkflowState.idle:
        return ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: Text('Start — ${widget.phases.first.phase.displayName}'),
          onPressed: _startNextPhase,
        );

      case WeldWorkflowState.phaseActive:
      case WeldWorkflowState.parameterViolation:
        final nominalDuration = currentPhase?.nominalDuration ?? 0;
        final phaseComplete = nominalDuration > 0 &&
            _phaseElapsedSeconds >= nominalDuration.toInt();

        return Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.skip_next),
              label: Text(
                _currentPhaseIndex < widget.phases.length - 1
                    ? 'Complete Phase — Next: ${widget.phases[_currentPhaseIndex + 1].phase.displayName}'
                    : 'Complete Final Phase',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: phaseComplete
                    ? const Color(0xFF2E7D32)
                    : theme.colorScheme.primary,
              ),
              onPressed: _completePhase,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Weld'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
                minimumSize: const Size(double.infinity, 52),
              ),
              onPressed: _showCancelDialog,
            ),
          ],
        );

      case WeldWorkflowState.phaseComplete:
        final isLastPhase = _currentPhaseIndex >= widget.phases.length;
        return ElevatedButton.icon(
          icon: Icon(isLastPhase ? Icons.check_circle : Icons.navigate_next),
          label: Text(isLastPhase
              ? 'Finish Weld'
              : 'Start ${widget.phases[_currentPhaseIndex].phase.displayName}'),
          onPressed: isLastPhase ? _finishWeld : _startNextPhase,
        );

      case WeldWorkflowState.completed:
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF2E7D32).withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.verified, color: Color(0xFF2E7D32), size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Weld complete',
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Projects'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32)),
              onPressed: () => context.go('/projects'),
            ),
          ],
        );

      case WeldWorkflowState.cancelled:
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.cancel, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Text('Weld cancelled — record saved',
                      style: TextStyle(
                          color: theme.colorScheme.onErrorContainer)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/projects'),
              child: const Text('Back to Projects'),
            ),
          ],
        );
    }
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final reasonController = TextEditingController();
        return AlertDialog(
          title: const Text('Cancel Weld?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This permanently cancels the weld. A cancellation record '
                'is saved for traceability.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Cancellation reason',
                  hintText: 'e.g. Equipment failure, operator error…',
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Keep Welding'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () async {
                final reason = reasonController.text.trim();
                Navigator.of(ctx).pop();
                await _cancelWeld(
                    reason.isEmpty ? 'No reason provided' : reason);
              },
              child: const Text('Cancel Weld'),
            ),
          ],
        );
      },
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SensorStatusBar extends StatelessWidget {
  const _SensorStatusBar({required this.state});
  final SensorConnectionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = switch (state) {
      SensorConnectionState.connected => (
          'Sensor Connected',
          const Color(0xFF2E7D32),
          Icons.bluetooth_connected
        ),
      SensorConnectionState.connecting ||
      SensorConnectionState.scanning => (
          'Connecting to sensor…',
          Colors.orange,
          Icons.bluetooth_searching
        ),
      SensorConnectionState.error => (
          'Sensor Error',
          theme.colorScheme.error,
          Icons.bluetooth_disabled
        ),
      SensorConnectionState.disconnected => (
          'No sensor — manual monitoring mode',
          theme.colorScheme.outline,
          Icons.bluetooth_disabled
        ),
    };

    return Container(
      color: color.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _PhaseProgressStepper extends StatelessWidget {
  const _PhaseProgressStepper({
    required this.phases,
    required this.currentIndex,
    required this.workflowState,
  });

  final List<PhaseParameters> phases;
  final int currentIndex;
  final WeldWorkflowState workflowState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Phases',
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary)),
          const SizedBox(height: 12),
          ...phases.asMap().entries.map((e) {
            final i = e.key;
            final phase = e.value;
            final isDone = i < currentIndex;
            final isActive = i == currentIndex;
            final isPending = i > currentIndex;

            final color = isDone
                ? const Color(0xFF2E7D32)
                : isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withOpacity(0.4);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    isDone
                        ? Icons.check_circle
                        : isActive
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                    color: color,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      phase.phase.displayName,
                      style: TextStyle(
                        color: color,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    '${phase.nominalDuration.toInt()} s',
                    style:
                        TextStyle(color: color, fontSize: 12),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PhaseTimerCard extends StatelessWidget {
  const _PhaseTimerCard({
    required this.phase,
    required this.elapsedSeconds,
  });

  final PhaseParameters phase;
  final int elapsedSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nominal = phase.nominalDuration.toInt();
    final progress = nominal > 0
        ? (elapsedSeconds / nominal).clamp(0.0, 1.0)
        : 0.0;

    final isOvertime = elapsedSeconds > phase.maxDuration.toInt();
    final isComplete = elapsedSeconds >= nominal;

    final barColor = isOvertime
        ? theme.colorScheme.error
        : isComplete
            ? const Color(0xFF2E7D32)
            : theme.colorScheme.primary;

    String _fmt(int s) =>
        '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: barColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: barColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                phase.phase.displayName,
                style: TextStyle(
                    color: barColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
              Text(
                _fmt(elapsedSeconds),
                style: TextStyle(
                    color: barColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: barColor.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Target: ${_fmt(nominal)}',
                  style: TextStyle(fontSize: 11, color: barColor.withOpacity(0.7))),
              if (phase.maxDuration > 0)
                Text('Max: ${_fmt(phase.maxDuration.toInt())}',
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.error.withOpacity(0.7))),
            ],
          ),
          if (isOvertime)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber,
                      color: theme.colorScheme.error, size: 14),
                  const SizedBox(width: 4),
                  Text('Exceeded maximum duration',
                      style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isAlert = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    final displayColor = isAlert ? Theme.of(context).colorScheme.error : color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: displayColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: displayColor.withOpacity(isAlert ? 0.8 : 0.2),
          width: isAlert ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(isAlert ? Icons.warning_amber : icon,
                color: displayColor, size: 16),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: displayColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: displayColor)),
        ],
      ),
    );
  }
}

class _ViolationsBanner extends StatelessWidget {
  const _ViolationsBanner({required this.violations});
  final List<ParameterViolation> violations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Show only the 5 most recent violations
    final recent = violations.reversed.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber,
                  color: theme.colorScheme.onErrorContainer, size: 16),
              const SizedBox(width: 6),
              Text(
                'Parameter Violations (${violations.length})',
                style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recent.map((v) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• ${v.parameterName.toUpperCase()}: '
                  '${v.actualValue.toStringAsFixed(2)} '
                  '(allowed ${v.allowedMin?.toStringAsFixed(2) ?? '—'}'
                  '–${v.allowedMax?.toStringAsFixed(2) ?? '—'})',
                  style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                      fontSize: 12),
                ),
              )),
        ],
      ),
    );
  }
}
