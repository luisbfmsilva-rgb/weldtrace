import 'dart:async';
import 'dart:convert';
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
    // ── Traceability metadata ─────────────────────────────────────────────
    this.projectName              = '',
    this.machineId                = '',
    this.machineName              = '',
    this.machineModel             = '',
    this.machineSerialNumber      = '',
    this.hydraulicCylinderAreaMm2 = 0.0,
    this.operatorName             = '',
    this.operatorId               = '',
    this.pipeMaterial             = '',
    this.pipeDiameter             = 0.0,
    this.pipeSdr                  = '',
    this.wallThicknessStr         = '',
    this.standardUsed             = '',
    this.fusionPressureBar        = 0.0,
    this.heatingTimeSec           = 0.0,
    this.coolingTimeSec           = 0.0,
    this.beadHeightMm             = 0.0,
    this.jointId                  = '',
  });

  final String weldId;
  final List<PhaseParameters> phases;

  final String projectName;
  final String machineId;
  final String machineName;
  final String machineModel;
  final String machineSerialNumber;
  final double hydraulicCylinderAreaMm2;
  final String operatorName;
  final String operatorId;
  final String pipeMaterial;
  final double pipeDiameter;
  final String pipeSdr;
  final String wallThicknessStr;
  final String standardUsed;
  final double fusionPressureBar;
  final double heatingTimeSec;
  final double coolingTimeSec;
  final double beadHeightMm;
  final String jointId;
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
    required this.args,
  });

  final WeldSessionArgs args;

  String get weldId  => args.weldId;
  List<PhaseParameters> get phases => args.phases;

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
  Timer? _phaseTimer;
  int _phaseElapsedSeconds = 0;

  // ── Chart ──────────────────────────────────────────────────────────────────
  final List<SensorReading> _sensorReadings = [];
  DateTime? _weldStartedAt;
  late NominalCurveData _nominalData;
  final List<StreamSubscription> _subs = [];

  // ── Bead formation (heatingUp phase) ──────────────────────────────────────
  bool _beadConfirmed = false;
  final TextEditingController _beadHeightController = TextEditingController();

  // ── Pressure reduction countdown (after bead confirmation) ────────────────
  bool _inPressureReduction = false;
  int _pressureReductionElapsed = 0;
  int _pressureReductionTotal = 0;
  Timer? _pressureReductionTimer;

  // ── Cooling early finish ───────────────────────────────────────────────────
  bool _coolingIncomplete = false;

  // ── Resume support ─────────────────────────────────────────────────────────
  bool _sessionMetaSaved = false;

  @override
  void initState() {
    super.initState();
    _nominalData = NominalCurveBuilder.build(widget.phases);
    _initEngine();
    _listenToSensor();
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveSessionMeta());
  }

  void _initEngine() {
    final db     = ref.read(databaseProvider);
    final sensor = ref.read(sensorServiceProvider);
    final a      = widget.args;
    _engine = WeldWorkflowEngine(
      db:                      db,
      sensorService:           sensor,
      weldId:                  a.weldId,
      phases:                  a.phases,
      projectName:             a.projectName,
      machineId:               a.machineId,
      machineName:             a.machineName,
      machineModel:            a.machineModel,
      machineSerialNumber:     a.machineSerialNumber,
      hydraulicCylinderAreaMm2: a.hydraulicCylinderAreaMm2,
      operatorName:            a.operatorName,
      operatorId:              a.operatorId,
      pipeMaterial:            a.pipeMaterial,
      pipeDiameter:            a.pipeDiameter,
      pipeSdr:                 a.pipeSdr,
      wallThicknessStr:        a.wallThicknessStr,
      standardUsed:            a.standardUsed,
      fusionPressureBar:       a.fusionPressureBar,
      heatingTimeSec:          a.heatingTimeSec,
      coolingTimeSec:          a.coolingTimeSec,
      beadHeightMm:            a.beadHeightMm,
      jointId:                 a.jointId,
    );

    _subs.add(_engine!.stateStream.listen((s) {
      if (mounted) {
        setState(() => _workflowState = s);
        if (s == WeldWorkflowState.completed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(children: [
                Icon(Icons.verified, color: Colors.white),
                SizedBox(width: 10),
                Text('Solda concluída e certificada!'),
              ]),
              backgroundColor: const Color(0xFF2E7D32),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }));
    _subs.add(_engine!.violationStream.listen((v) {
      if (mounted) setState(() => _violations.add(v));
    }));
  }

  Future<void> _saveSessionMeta() async {
    if (_sessionMetaSaved) return;
    try {
      final a = widget.args;
      final phasesJson = jsonEncode(
        widget.phases.map((p) => p.toJson()).toList(),
      );
      final sessionMetaJson = jsonEncode({
        'projectName':             a.projectName,
        'machineId':               a.machineId,
        'machineName':             a.machineName,
        'machineModel':            a.machineModel,
        'machineSerialNumber':     a.machineSerialNumber,
        'hydraulicCylinderAreaMm2': a.hydraulicCylinderAreaMm2,
        'operatorName':            a.operatorName,
        'operatorId':              a.operatorId,
        'pipeMaterial':            a.pipeMaterial,
        'pipeDiameter':            a.pipeDiameter,
        'pipeSdr':                 a.pipeSdr,
        'wallThicknessStr':        a.wallThicknessStr,
        'standardUsed':            a.standardUsed,
        'fusionPressureBar':       a.fusionPressureBar,
        'heatingTimeSec':          a.heatingTimeSec,
        'coolingTimeSec':          a.coolingTimeSec,
        'beadHeightMm':            a.beadHeightMm,
        'jointId':                 a.jointId,
      });
      final db = ref.read(databaseProvider);
      await db.weldsDao.saveSessionMeta(
        id:              a.weldId,
        phasesJson:      phasesJson,
        sessionMetaJson: sessionMetaJson,
      );
      _sessionMetaSaved = true;
    } catch (_) {}
  }

  void _listenToSensor() {
    final sensor = ref.read(sensorServiceProvider);
    _subs.add(sensor.readingStream.listen((r) {
      if (mounted) {
        setState(() {
          _latestPressure = r.pressureBar;
          _latestTemperature = r.temperatureCelsius;
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
    for (final s in _subs) s.cancel();
    _phaseTimer?.cancel();
    _pressureReductionTimer?.cancel();
    _beadHeightController.dispose();
    _engine?.dispose();
    super.dispose();
  }

  // ── Phase management ───────────────────────────────────────────────────────

  Future<void> _startNextPhase() async {
    await _engine?.advancePhase();
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      // _currentPhaseIndex is already correct:
      // • First call (idle → phase 0): stays at 0.
      // • After _completePhase(): already incremented to the next index.
      _phaseElapsedSeconds = 0;
      _violations.clear();
      _beadConfirmed = false;
      _inPressureReduction = false;
      _weldStartedAt ??= now;
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
    _pressureReductionTimer?.cancel();
    await _engine?.completeCurrentPhase();
    if (!mounted) return;
    setState(() {
      _currentPhaseIndex++;
      _phaseElapsedSeconds = 0;
      _inPressureReduction = false;
      _nominalData = NominalCurveBuilder.updateActivePhase(
        _nominalData,
        widget.phases,
        _currentPhaseIndex,
      );
    });
  }

  Future<void> _finishWeld() async {
    _phaseTimer?.cancel();
    await _engine?.completeWeld(coolingIncomplete: _coolingIncomplete);
  }

  Future<void> _cancelWeld(String reason) async {
    _phaseTimer?.cancel();
    _pressureReductionTimer?.cancel();
    await _engine?.cancel(reason);
  }

  void _startPhaseTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _phaseElapsedSeconds++);
    });
  }

  // ── Bead formation ─────────────────────────────────────────────────────────

  Future<void> _confirmBead() async {
    final elapsed = _phaseElapsedSeconds;
    final height  = double.tryParse(
      _beadHeightController.text.replaceAll(',', '.'),
    );
    try {
      final db = ref.read(databaseProvider);
      await db.weldsDao.saveBeadData(
        id:                  widget.args.weldId,
        beadFormationSeconds: elapsed,
        beadHeightMm:        height,
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() => _beadConfirmed = true);
    _startPressureReductionCountdown();
  }

  // ── Pressure reduction countdown ───────────────────────────────────────────

  void _startPressureReductionCountdown() {
    final changeover = widget.phases.firstWhere(
      (p) => p.phase == WeldingPhase.changeover,
      orElse: () => PhaseParameters(
        phase:            WeldingPhase.changeover,
        nominalDuration:  30,
        minDuration:      0,
        maxDuration:      60,
      ),
    );
    final total = changeover.nominalDuration.toInt().clamp(5, 300);
    setState(() {
      _pressureReductionElapsed = 0;
      _pressureReductionTotal   = total;
      _inPressureReduction      = true;
    });

    _pressureReductionTimer?.cancel();
    _pressureReductionTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _pressureReductionElapsed++);

      if (_pressureReductionElapsed >= _pressureReductionTotal) {
        t.cancel();
        if (!mounted) return;
        // Timeout → auto-advance (completePhase advances heatingUp → heating)
        setState(() => _inPressureReduction = false);
        _completePhase();
      }
    });
  }

  // ── Cooling early-finish dialog ────────────────────────────────────────────

  Future<void> _showCoolingEarlyFinishDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar Resfriamento?'),
        content: const Text(
          'O tempo de resfriamento nominal ainda não terminou.\n\n'
          'Encerrar antes do tempo recomendado pode comprometer a qualidade '
          'da junta. O relatório PDF incluirá um aviso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continuar Resfriamento'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Encerrar Agora'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _coolingIncomplete = true);
      await _completePhase();
      if (mounted) await _finishWeld();
    }
  }

  // ── Leave-weld dialog (weld stays in_progress) ────────────────────────────

  void _showLeaveWeldDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deixar a Solda?'),
        content: const Text(
          'A solda continuará em progresso.\n'
          'Pode retomá-la mais tarde na lista do projecto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continuar'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/projects');
            },
            child: const Text('Deixar'),
          ),
        ],
      ),
    );
  }

  // ── Cancel-weld dialog ────────────────────────────────────────────────────

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final reasonController = TextEditingController();
        return AlertDialog(
          title: const Text('Cancelar Solda?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Isto cancela definitivamente a solda. '
                'Um relatório de cancelamento é gerado para rastreabilidade.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Motivo do cancelamento',
                  hintText: 'ex.: Falha de equipamento, erro de operador…',
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Continuar a Soldar'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () async {
                final reason = reasonController.text.trim();
                Navigator.of(ctx).pop();
                await _cancelWeld(
                    reason.isEmpty ? 'Sem motivo indicado' : reason);
              },
              child: const Text('Cancelar Solda'),
            ),
          ],
        );
      },
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPhase =
        _currentPhaseIndex < widget.phases.length
            ? widget.phases[_currentPhaseIndex]
            : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Solda · ${widget.weldId.substring(0, 8).toUpperCase()}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_workflowState == WeldWorkflowState.completed ||
                _workflowState == WeldWorkflowState.cancelled) {
              context.go('/projects');
            } else if (_workflowState == WeldWorkflowState.phaseActive ||
                _workflowState == WeldWorkflowState.parameterViolation) {
              _showLeaveWeldDialog();
            } else {
              context.go('/projects');
            }
          },
        ),
      ),
      body: Column(
        children: [

          // ── Pressure reduction overlay ─────────────────────────────────────
          if (_inPressureReduction) _PressureReductionBanner(
            elapsed: _pressureReductionElapsed,
            total:   _pressureReductionTotal,
            onSkip:  () {
              _pressureReductionTimer?.cancel();
              setState(() => _inPressureReduction = false);
              _completePhase();
            },
          ),

          // ── Cooling incomplete warning ─────────────────────────────────────
          if (_coolingIncomplete)
            Container(
              color: const Color(0xFFF57C00),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: const Row(children: [
                Icon(Icons.warning_amber, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Resfriamento encerrado antes do tempo nominal',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
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

    final bool isHeatingUpPhase = currentPhase?.phase == WeldingPhase.heatingUp;
    final bool isCoolingPhase   = currentPhase?.phase == WeldingPhase.cooling;

    switch (_workflowState) {
      // ── Idle — not yet started ─────────────────────────────────────────────
      case WeldWorkflowState.idle:
        return ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: Text('Iniciar — ${widget.phases.first.phase.displayName}'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          onPressed: _startNextPhase,
        );

      // ── Active / violation ─────────────────────────────────────────────────
      case WeldWorkflowState.phaseActive:
      case WeldWorkflowState.parameterViolation:
        // ── heatingUp: bead formation UI ──────────────────────────────────
        if (isHeatingUpPhase && !_beadConfirmed && !_inPressureReduction) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bead height input
              TextField(
                controller: _beadHeightController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Altura do cordão (mm) — opcional',
                  hintText: 'ex.: 2.0',
                  prefixIcon: Icon(Icons.straighten),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Cordão formado ✓'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  minimumSize: const Size(double.infinity, 52),
                ),
                onPressed: _confirmBead,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancelar Solda'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: _showCancelDialog,
              ),
            ],
          );
        }

        // ── cooling: allow early finish with warning ────────────────────────
        if (isCoolingPhase) {
          final nominal  = currentPhase?.nominalDuration ?? 0;
          final isOnTime = _phaseElapsedSeconds >= nominal.toInt();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.ac_unit),
                label: Text(isOnTime
                    ? 'Concluir Resfriamento'
                    : 'Encerrar Resfriamento Antes do Prazo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isOnTime ? const Color(0xFF2E7D32) : Colors.orange,
                  minimumSize: const Size(double.infinity, 52),
                ),
                onPressed: isOnTime
                    ? () async {
                        await _completePhase();
                        if (mounted) await _finishWeld();
                      }
                    : _showCoolingEarlyFinishDialog,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancelar Solda'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: _showCancelDialog,
              ),
            ],
          );
        }

        // ── normal phase ───────────────────────────────────────────────────
        {
          final nominalDuration = currentPhase?.nominalDuration ?? 0;
          final phaseComplete = nominalDuration > 0 &&
              _phaseElapsedSeconds >= nominalDuration.toInt();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.skip_next),
                label: Text(
                  _currentPhaseIndex < widget.phases.length - 1
                      ? 'Concluir — Próxima: ${widget.phases[_currentPhaseIndex + 1].phase.displayName}'
                      : 'Concluir Fase Final',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: phaseComplete
                      ? const Color(0xFF2E7D32)
                      : theme.colorScheme.primary,
                  minimumSize: const Size(double.infinity, 52),
                ),
                onPressed: _completePhase,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancelar Solda'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: _showCancelDialog,
              ),
            ],
          );
        }

      // ── Phase complete — waiting to start next ─────────────────────────────
      case WeldWorkflowState.phaseComplete:
        final isLastPhase = _currentPhaseIndex >= widget.phases.length;
        return ElevatedButton.icon(
          icon: Icon(isLastPhase ? Icons.check_circle : Icons.navigate_next),
          label: Text(isLastPhase
              ? 'Finalizar Solda'
              : 'Iniciar ${widget.phases[_currentPhaseIndex].phase.displayName}'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          onPressed: isLastPhase ? _finishWeld : _startNextPhase,
        );

      // ── Completed ──────────────────────────────────────────────────────────
      case WeldWorkflowState.completed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF2E7D32).withOpacity(0.4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified, color: Color(0xFF2E7D32), size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Solda concluída e certificada',
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar aos Projectos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                minimumSize: const Size(double.infinity, 52),
              ),
              onPressed: () => context.go('/projects'),
            ),
          ],
        );

      // ── Cancelled ──────────────────────────────────────────────────────────
      case WeldWorkflowState.cancelled:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.cancel,
                      color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Text('Solda cancelada — registo guardado',
                      style: TextStyle(
                          color: theme.colorScheme.onErrorContainer)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52)),
              onPressed: () => context.go('/projects'),
              child: const Text('Voltar aos Projectos'),
            ),
          ],
        );
    }
  }

}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// Overlay banner shown during pressure reduction countdown between heatingUp
/// confirmation and the start of the changeover / heat-soak phase.
class _PressureReductionBanner extends StatelessWidget {
  const _PressureReductionBanner({
    required this.elapsed,
    required this.total,
    required this.onSkip,
  });

  final int elapsed;
  final int total;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final remaining = (total - elapsed).clamp(0, total);
    final progress  = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0.0;
    final fmtR      = '${(remaining ~/ 60).toString().padLeft(2, '0')}:'
                      '${(remaining % 60).toString().padLeft(2, '0')}';

    return Container(
      color: const Color(0xFFE65100),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.compress, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Reduzir pressão / Remover calefator',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                fmtR,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onSkip,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Avançar',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: 1.0 - progress,
              minHeight: 5,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

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
