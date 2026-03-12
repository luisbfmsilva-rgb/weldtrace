import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../di/providers.dart';
import '../../services/sensor/sensor_service.dart';
import '../../workflow/weld_workflow_engine.dart';

/// Welding session screen — guides the welder through each phase,
/// displays live sensor readings, and handles parameter violations.
class WeldingSessionScreen extends ConsumerStatefulWidget {
  const WeldingSessionScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<WeldingSessionScreen> createState() =>
      _WeldingSessionScreenState();
}

class _WeldingSessionScreenState
    extends ConsumerState<WeldingSessionScreen> {

  WeldWorkflowState _workflowState = WeldWorkflowState.idle;
  SensorConnectionState _sensorState = SensorConnectionState.disconnected;
  double? _latestPressure;
  double? _latestTemperature;
  final List<String> _violations = [];

  @override
  void initState() {
    super.initState();
    _listenToSensor();
  }

  void _listenToSensor() {
    final sensor = ref.read(sensorServiceProvider);
    sensor.readingStream.listen((reading) {
      if (mounted) {
        setState(() {
          _latestPressure = reading.pressureBar;
          _latestTemperature = reading.temperatureCelsius;
        });
      }
    });
    sensor.connectionStateStream.listen((state) {
      if (mounted) setState(() => _sensorState = state);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welding Session'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_workflowState == WeldWorkflowState.phaseActive) {
              _showCancelDialog();
            } else {
              context.pop();
            }
          },
        ),
      ),
      body: Column(
        children: [
          // ── Sensor connection status bar ─────────────────────────────────
          _SensorStatusBar(sensorState: _sensorState),

          // ── Live readings ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _ReadingCard(
                    label: 'Pressure',
                    value: _latestPressure != null
                        ? '${_latestPressure!.toStringAsFixed(2)} bar'
                        : '— bar',
                    icon: Icons.compress,
                    color: theme.colorScheme.primary,
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
                  ),
                ),
              ],
            ),
          ),

          // ── Violations ───────────────────────────────────────────────────
          if (_violations.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.error),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.warning_amber, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Text('Parameter Violations',
                        style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 8),
                  ..._violations
                      .map((v) => Text('• $v',
                          style:
                              TextStyle(color: theme.colorScheme.error, fontSize: 13)))
                      ,
                ],
              ),
            ),

          const Spacer(),

          // ── Workflow state ────────────────────────────────────────────────
          _WorkflowStateDisplay(state: _workflowState),

          const SizedBox(height: 16),

          // ── Action buttons ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: _buildActionButtons(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    switch (_workflowState) {
      case WeldWorkflowState.idle:
        return ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Weld Session'),
          onPressed: () {
            // In the next step, this will open the weld creation form
            // and then start the workflow engine
            setState(() => _workflowState = WeldWorkflowState.phaseActive);
          },
        );

      case WeldWorkflowState.phaseActive:
      case WeldWorkflowState.parameterViolation:
        return Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.skip_next),
              label: const Text('Complete Phase'),
              onPressed: () =>
                  setState(() => _workflowState = WeldWorkflowState.phaseComplete),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Weld'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
                minimumSize: const Size(double.infinity, 56),
              ),
              onPressed: _showCancelDialog,
            ),
          ],
        );

      case WeldWorkflowState.phaseComplete:
        return ElevatedButton.icon(
          icon: const Icon(Icons.navigate_next),
          label: const Text('Next Phase'),
          onPressed: () =>
              setState(() => _workflowState = WeldWorkflowState.phaseActive),
        );

      case WeldWorkflowState.completed:
        return ElevatedButton.icon(
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Weld Complete — Back to Projects'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
          ),
          onPressed: () => context.go('/projects'),
        );

      case WeldWorkflowState.cancelled:
        return ElevatedButton(
          onPressed: () => context.go('/projects'),
          child: const Text('Back to Projects'),
        );
    }
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Weld?'),
        content: const Text(
          'This will permanently cancel the weld session. '
          'A cancellation record will be created for traceability.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep Welding'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _workflowState = WeldWorkflowState.cancelled);
            },
            child: const Text('Cancel Weld'),
          ),
        ],
      ),
    );
  }
}

class _SensorStatusBar extends StatelessWidget {
  const _SensorStatusBar({required this.sensorState});
  final SensorConnectionState sensorState;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (sensorState) {
      SensorConnectionState.connected => ('Sensor Connected', const Color(0xFF2E7D32), Icons.bluetooth_connected),
      SensorConnectionState.connecting => ('Connecting...', Colors.orange, Icons.bluetooth_searching),
      SensorConnectionState.scanning => ('Scanning for sensor...', Colors.orange, Icons.bluetooth_searching),
      SensorConnectionState.error => ('Sensor Error', Theme.of(context).colorScheme.error, Icons.bluetooth_disabled),
      SensorConnectionState.disconnected => ('No Sensor', Colors.grey, Icons.bluetooth_disabled),
    };

    return Container(
      color: color.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
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
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _WorkflowStateDisplay extends StatelessWidget {
  const _WorkflowStateDisplay({required this.state});
  final WeldWorkflowState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon, color) = switch (state) {
      WeldWorkflowState.idle => ('Ready to start', Icons.radio_button_unchecked, theme.colorScheme.outline),
      WeldWorkflowState.phaseActive => ('Phase in progress', Icons.play_circle_outline, theme.colorScheme.primary),
      WeldWorkflowState.phaseComplete => ('Phase complete', Icons.check_circle_outline, const Color(0xFF2E7D32)),
      WeldWorkflowState.parameterViolation => ('Parameter violation detected', Icons.warning_amber, theme.colorScheme.error),
      WeldWorkflowState.completed => ('Weld complete', Icons.verified_outlined, const Color(0xFF2E7D32)),
      WeldWorkflowState.cancelled => ('Weld cancelled', Icons.cancel_outlined, theme.colorScheme.error),
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 16)),
        ],
      ),
    );
  }
}
