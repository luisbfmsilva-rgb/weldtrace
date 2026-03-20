import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../di/providers.dart';
import '../../services/sensor/sensor_service.dart';
import 'welding_session_screen.dart';

/// Three-step preparation flow before welding begins:
///
///   Step 1 – Define drag pressure  (live BLE sensor + button)
///   Step 2 – Facing the pipes      (max facing pressure display + "Facing done!")
///   Step 3 – Check misalignment    (inputs, validation, Done / Face again)
class PreparationScreen extends ConsumerStatefulWidget {
  const PreparationScreen({super.key, required this.args});

  final WeldSessionArgs args;

  @override
  ConsumerState<PreparationScreen> createState() => _PreparationScreenState();
}

class _PreparationScreenState extends ConsumerState<PreparationScreen> {
  int _step = 0;

  double? _measuredDragPressure;
  double? _latestPressure;
  SensorConnectionState _sensorState = SensorConnectionState.disconnected;

  final TextEditingController _misalignmentController =
      TextEditingController();
  bool _gapWidthChecked = false;
  bool _facingDoneAtLeastOnce = false;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _listenToSensor();
  }

  void _listenToSensor() {
    final sensor = ref.read(sensorServiceProvider);
    _subs.add(sensor.readingStream.listen((r) {
      if (mounted) {
        setState(() => _latestPressure = r.pressureBar);
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
    _misalignmentController.dispose();
    super.dispose();
  }

  // ── Gap width table per DVS / ISO standard ─────────────────────────────────
  static double _maxGapWidthMm(double odMm) {
    if (odMm <= 355) return 0.5;
    if (odMm <= 630) return 1.0;
    if (odMm <= 800) return 1.5;
    return 2.0;
  }

  // ── Initial bead height: 10 % of wall thickness, rounded UP to 0.5 mm ─────
  static double _minBeadHeight(double wallMm) {
    final raw = wallMm * 0.10;
    return (raw / 0.5).ceil() * 0.5;
  }

  // ── Step navigation ────────────────────────────────────────────────────────

  void _defineDragPressure() {
    final pressure = _latestPressure ?? 0.0;
    HapticFeedback.mediumImpact();
    setState(() {
      _measuredDragPressure = pressure;
      _step = 1;
    });
  }

  void _facingDone() {
    HapticFeedback.mediumImpact();
    setState(() {
      _facingDoneAtLeastOnce = true;
      _step = 2;
    });
  }

  void _faceAgain() {
    setState(() => _step = 1);
  }

  void _done() {
    final updatedArgs = widget.args.copyWith(
      dragPressureBar: _measuredDragPressure ?? 0.0,
    );
    context.go('/weld/session', extra: updatedArgs);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showAbortDialog();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Preparation — Step ${_step + 1} of 3'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _showAbortDialog,
          ),
        ),
        body: SafeArea(
          child: _buildCurrentStep(),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _StepDefineDrag(
          latestPressure: _latestPressure,
          sensorState: _sensorState,
          onDefine: _defineDragPressure,
        );
      case 1:
        return _StepFacingPipes(
          dragPressure: _measuredDragPressure ?? 0.0,
          latestPressure: _latestPressure,
          sensorState: _sensorState,
          onFacingDone: _facingDone,
        );
      case 2:
        return _StepCheckAlignment(
          wallThicknessMm: widget.args.wallThicknessMm,
          outerDiameterMm: widget.args.outerDiameterMm,
          maxGapWidth: _maxGapWidthMm(widget.args.outerDiameterMm),
          minBeadHeight: _minBeadHeight(widget.args.wallThicknessMm),
          misalignmentController: _misalignmentController,
          gapWidthChecked: _gapWidthChecked,
          onGapChecked: (v) => setState(() => _gapWidthChecked = v ?? false),
          onChanged: () => setState(() {}),
          onDone: _done,
          onFaceAgain: _faceAgain,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _showAbortDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abort Preparation?'),
        content: const Text(
          'The weld record has already been created.\n'
          'Returning now will leave it in "in progress" state.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continue Preparation'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/projects');
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Step 1 — Define drag pressure
// ════════════════════════════════════════════════════════════════════════════

class _StepDefineDrag extends StatelessWidget {
  const _StepDefineDrag({
    required this.latestPressure,
    required this.sensorState,
    required this.onDefine,
  });

  final double? latestPressure;
  final SensorConnectionState sensorState;
  final VoidCallback onDefine;

  @override
  Widget build(BuildContext context) {
    final isConnected = sensorState == SensorConnectionState.connected;
    final pressureStr = latestPressure != null
        ? '${latestPressure!.toStringAsFixed(2)} bar'
        : '--';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(
            stepNumber: 1,
            title: 'Define Drag Pressure',
            subtitle:
                'Ensure no load on the clamps. The machine must move freely.',
          ),
          const SizedBox(height: 32),
          _BigValueCard(
            label: 'Current Pressure',
            value: pressureStr,
            icon: Icons.speed,
            color: isConnected ? const Color(0xFF1565C0) : Colors.grey,
          ),
          if (!isConnected) ...[
            const SizedBox(height: 12),
            _InfoBanner(
              message: 'Sensor not connected — pressure will be recorded as '
                  '${latestPressure?.toStringAsFixed(2) ?? '0.00'} bar.',
              color: Colors.orange,
            ),
          ],
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.fingerprint),
            label: const Text('Define Drag Pressure'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
            ),
            onPressed: onDefine,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Step 2 — Facing the pipes
// ════════════════════════════════════════════════════════════════════════════

class _StepFacingPipes extends StatelessWidget {
  const _StepFacingPipes({
    required this.dragPressure,
    required this.latestPressure,
    required this.sensorState,
    required this.onFacingDone,
  });

  final double dragPressure;
  final double? latestPressure;
  final SensorConnectionState sensorState;
  final VoidCallback onFacingDone;

  @override
  Widget build(BuildContext context) {
    final maxFacing = dragPressure + 25.0;
    final isConnected = sensorState == SensorConnectionState.connected;
    final pressureStr = latestPressure != null
        ? '${latestPressure!.toStringAsFixed(2)} bar'
        : '--';

    final aboveMax =
        latestPressure != null && latestPressure! > maxFacing;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(
            stepNumber: 2,
            title: 'Facing the Pipes',
            subtitle:
                'Face both pipe ends until all burrs are removed. '
                'Do not exceed the maximum facing pressure.',
          ),
          const SizedBox(height: 24),
          _LimitCard(
            label: 'Maximum Facing Pressure',
            value: '${maxFacing.toStringAsFixed(1)} bar',
            subtitle: 'Drag pressure (${dragPressure.toStringAsFixed(2)} bar) + 25 bar',
            color: Colors.deepOrange,
          ),
          const SizedBox(height: 16),
          _BigValueCard(
            label: 'Current Pressure',
            value: pressureStr,
            icon: Icons.speed,
            color: aboveMax
                ? Colors.red
                : isConnected
                    ? const Color(0xFF1565C0)
                    : Colors.grey,
          ),
          if (aboveMax)
            _InfoBanner(
              message:
                  'Pressure exceeds maximum facing pressure! Reduce load.',
              color: Colors.red,
            ),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Facing Done!'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
            ),
            onPressed: onFacingDone,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Step 3 — Check misalignment & gap width
// ════════════════════════════════════════════════════════════════════════════

class _StepCheckAlignment extends StatelessWidget {
  const _StepCheckAlignment({
    required this.wallThicknessMm,
    required this.outerDiameterMm,
    required this.maxGapWidth,
    required this.minBeadHeight,
    required this.misalignmentController,
    required this.gapWidthChecked,
    required this.onGapChecked,
    required this.onChanged,
    required this.onDone,
    required this.onFaceAgain,
  });

  final double wallThicknessMm;
  final double outerDiameterMm;
  final double maxGapWidth;
  final double minBeadHeight;
  final TextEditingController misalignmentController;
  final bool gapWidthChecked;
  final ValueChanged<bool?> onGapChecked;
  final VoidCallback onChanged;
  final VoidCallback onDone;
  final VoidCallback onFaceAgain;

  @override
  Widget build(BuildContext context) {
    final maxMisalign = wallThicknessMm * 0.10;
    final measured = double.tryParse(
        misalignmentController.text.replaceAll(',', '.'));
    final misalignOk = measured != null && measured <= maxMisalign;
    final isDoneEnabled = misalignOk && gapWidthChecked;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(
            stepNumber: 3,
            title: 'Check Alignment & Gap Width',
            subtitle:
                'Verify pipe alignment and gap before starting the weld.',
          ),
          const SizedBox(height: 24),

          // Limits row
          Row(
            children: [
              Expanded(
                child: _LimitCard(
                  label: 'Maximum Misalignment',
                  value:
                      '${maxMisalign.toStringAsFixed(1)} mm',
                  subtitle: '10 % of wall (${wallThicknessMm.toStringAsFixed(2)} mm)',
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LimitCard(
                  label: 'Maximum Gap Width',
                  value: '${maxGapWidth.toStringAsFixed(1)} mm',
                  subtitle: 'OD ${outerDiameterMm.toStringAsFixed(0)} mm',
                  color: Colors.teal,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          _LimitCard(
            label: 'Min. Initial Bead Height',
            value: '${minBeadHeight.toStringAsFixed(1)} mm',
            subtitle: '≥ 10 % of wall thickness, rounded to 0.5 mm',
            color: Colors.indigo,
          ),

          const SizedBox(height: 24),

          // Misalignment input
          TextField(
            controller: misalignmentController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,3}(\.\d{0,2})?')),
            ],
            decoration: InputDecoration(
              labelText: 'Measured Misalignment (mm)',
              hintText: 'e.g. 1.2',
              suffixText: 'mm',
              prefixIcon: const Icon(Icons.straighten),
              errorText: measured != null && measured > maxMisalign
                  ? 'Exceeds maximum (${maxMisalign.toStringAsFixed(1)} mm)'
                  : null,
            ),
            onChanged: (_) => onChanged(),
          ),

          const SizedBox(height: 16),

          // Gap width checkbox
          Card(
            child: CheckboxListTile(
              title: const Text('Maximum gap width checked ✓'),
              subtitle: Text(
                  'Gap is ≤ ${maxGapWidth.toStringAsFixed(1)} mm and acceptable'),
              value: gapWidthChecked,
              onChanged: onGapChecked,
            ),
          ),

          const SizedBox(height: 32),

          ElevatedButton.icon(
            icon: const Icon(Icons.play_circle_fill),
            label: const Text('Done! — Start Welding'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: isDoneEnabled
                  ? const Color(0xFF2E7D32)
                  : null,
            ),
            onPressed: isDoneEnabled ? onDone : null,
          ),

          const SizedBox(height: 12),

          OutlinedButton.icon(
            icon: const Icon(Icons.replay),
            label: const Text('Face the Pipes Again'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: onFaceAgain,
          ),

          const SizedBox(height: 8),

          if (!isDoneEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                !misalignOk && measured != null
                    ? 'Misalignment exceeds the limit. Face the pipes again.'
                    : measured == null
                        ? 'Enter the measured misalignment to continue.'
                        : 'Confirm the gap width is acceptable.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ════════════════════════════════════════════════════════════════════════════

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.stepNumber,
    required this.title,
    this.subtitle,
  });

  final int stepNumber;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              child: Text('$stepNumber',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ],
    );
  }
}

class _BigValueCard extends StatelessWidget {
  const _BigValueCard({
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LimitCard extends StatelessWidget {
  const _LimitCard({
    required this.label,
    required this.value,
    this.subtitle,
    required this.color,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color)),
          if (subtitle != null)
            Text(subtitle!,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}
