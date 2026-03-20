import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../di/providers.dart';
import '../../services/sensor/sensor_service.dart';
import '../../services/sensor/sensor_reading.dart';
import '../../workflow/weld_workflow_engine.dart';
import '../../workflow/welding_phase.dart';
import 'nominal_curve_builder.dart';
import 'pressure_time_graph.dart';

/// Arguments passed via GoRouter [extra] from WeldSetupScreen / PreparationScreen.
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
    // ── Preparation-phase data ────────────────────────────────────────────
    this.dragPressureBar          = 0.0,
    this.wallThicknessMm          = 0.0,
    this.outerDiameterMm          = 0.0,
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

  /// Drag pressure measured live during the preparation phase [bar].
  final double dragPressureBar;

  /// Pipe wall thickness in mm (numeric; used for bead-height / misalignment calcs).
  final double wallThicknessMm;

  /// Pipe outer diameter in mm (numeric; used for gap-width table in preparation).
  final double outerDiameterMm;

  WeldSessionArgs copyWith({
    double? dragPressureBar,
  }) =>
      WeldSessionArgs(
        weldId:                  weldId,
        phases:                  phases,
        projectName:             projectName,
        machineId:               machineId,
        machineName:             machineName,
        machineModel:            machineModel,
        machineSerialNumber:     machineSerialNumber,
        hydraulicCylinderAreaMm2: hydraulicCylinderAreaMm2,
        operatorName:            operatorName,
        operatorId:              operatorId,
        pipeMaterial:            pipeMaterial,
        pipeDiameter:            pipeDiameter,
        pipeSdr:                 pipeSdr,
        wallThicknessStr:        wallThicknessStr,
        standardUsed:            standardUsed,
        fusionPressureBar:       fusionPressureBar,
        heatingTimeSec:          heatingTimeSec,
        coolingTimeSec:          coolingTimeSec,
        beadHeightMm:            beadHeightMm,
        jointId:                 jointId,
        dragPressureBar:         dragPressureBar ?? this.dragPressureBar,
        wallThicknessMm:         wallThicknessMm,
        outerDiameterMm:         outerDiameterMm,
      );
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

  // ── beadUpAdjust phase ────────────────────────────────────────────────────
  // (operator manually confirms pressure adjustment before bead-up)

  // ── heatingUp (Bead Up) phase ─────────────────────────────────────────────
  int _beadUpViolationSeconds = 0; // consecutive seconds of pressure violation

  // ── changeover (t3) / buildup (t4) ───────────────────────────────────────
  bool _changeoverT4Started = false;    // true once pressure starts rising
  double? _changeoverMinPressure;       // lowest pressure seen during t3
  int _t4ElapsedSeconds = 0;
  Timer? _t4Timer;

  // ── Guards against re-entrancy during auto-advance ────────────────────────
  bool _isAutoAdvancing = false;

  // ── Cooling pressure monitoring ───────────────────────────────────────────
  bool _coolingIncomplete = false;
  int _coolingViolationSeconds = 0;
  String _coolingWarningMessage = '';

  // ── GPS coordinates (captured on weld complete) ───────────────────────────
  double? _gpsLat;
  double? _gpsLng;

  // ── Wakelock ──────────────────────────────────────────────────────────────
  bool _wakelockEnabled = false;

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
      if (!mounted) return;
      setState(() {
        _latestPressure    = r.pressureBar;
        _latestTemperature = r.temperatureCelsius;
        if (_weldStartedAt != null &&
            _workflowState != WeldWorkflowState.completed &&
            _workflowState != WeldWorkflowState.cancelled) {
          _sensorReadings.add(r);
        }
      });

      // Changeover: detect pressure rise for t4
      final currentPhase = _currentPhaseIndex < widget.phases.length
          ? widget.phases[_currentPhaseIndex]
          : null;
      if (currentPhase?.phase == WeldingPhase.changeover &&
          r.pressureBar != null &&
          (_workflowState == WeldWorkflowState.phaseActive ||
           _workflowState == WeldWorkflowState.parameterViolation)) {
        _onChangeoverPressureUpdate(r.pressureBar!);
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
    _t4Timer?.cancel();
    _engine?.dispose();
    _disableWakelock();
    super.dispose();
  }

  // ── Phase management ───────────────────────────────────────────────────────

  Future<void> _startNextPhase() async {
    await _engine?.advancePhase();
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _phaseElapsedSeconds = 0;
      _violations.clear();
      _weldStartedAt ??= now;
      // reset phase-specific state
      _beadUpViolationSeconds   = 0;
      _changeoverT4Started      = false;
      _changeoverMinPressure    = null;
      _t4ElapsedSeconds         = 0;
      _coolingViolationSeconds  = 0;
      _coolingWarningMessage    = '';
      _isAutoAdvancing          = false;
      _nominalData = NominalCurveBuilder.updateActivePhase(
        _nominalData,
        widget.phases,
        _currentPhaseIndex,
      );
    });
    _t4Timer?.cancel();
    _startPhaseTimer();
    _enableWakelock();
  }

  Future<void> _completePhase() async {
    _phaseTimer?.cancel();
    _t4Timer?.cancel();
    final completedPhase = _currentPhaseIndex < widget.phases.length
        ? widget.phases[_currentPhaseIndex].phase
        : null;

    await _engine?.completeCurrentPhase();
    if (!mounted) return;
    setState(() {
      _currentPhaseIndex++;
      _phaseElapsedSeconds  = 0;
      _coolingViolationSeconds = 0;
      _coolingWarningMessage   = '';
      _nominalData = NominalCurveBuilder.updateActivePhase(
        _nominalData,
        widget.phases,
        _currentPhaseIndex,
      );
    });

    // Auto-advance: heating → changeover (t3 starts immediately)
    if (completedPhase == WeldingPhase.heating) {
      await _startNextPhase();
    }

    // Auto-skip: fusion (zero-duration) → cooling
    if (completedPhase == WeldingPhase.buildup) {
      // advance to fusion
      await _startNextPhase();
      // immediately complete fusion and start cooling
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) await _completePhase();
        if (mounted) await _startNextPhase(); // start cooling
      }
    }
  }

  Future<void> _finishWeld() async {
    _phaseTimer?.cancel();
    _t4Timer?.cancel();
    await _captureGps();
    _disableWakelock();
    await _engine?.completeWeld(
      coolingIncomplete: _coolingIncomplete,
      gpsLat: _gpsLat,
      gpsLng: _gpsLng,
    );
  }

  Future<void> _cancelWeld(String reason) async {
    _phaseTimer?.cancel();
    _t4Timer?.cancel();
    _disableWakelock();
    await _engine?.cancel(reason);
  }

  void _startPhaseTimer() {
    _phaseTimer?.cancel();
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _phaseElapsedSeconds++);

      final currentPhase = _currentPhaseIndex < widget.phases.length
          ? widget.phases[_currentPhaseIndex]
          : null;
      if (currentPhase == null) return;

      // heatingUp (Bead Up): auto-cancel if pressure violates >3s
      if (currentPhase.phase == WeldingPhase.heatingUp) {
        final p = _latestPressure;
        final nom = currentPhase.nominalPressureBar;
        if (p != null && nom != null) {
          final inRange = (p - nom).abs() / nom <= 0.10;
          if (!inRange) {
            setState(() => _beadUpViolationSeconds++);
            if (_beadUpViolationSeconds >= 3) {
              _.cancel();
              _cancelWeld('Pressure violation >3 s during Bead Up phase');
            }
          } else {
            setState(() => _beadUpViolationSeconds = 0);
          }
        }
      }

      // heating: beep last 10 s; auto-cancel on maxDuration exceeded
      if (currentPhase.phase == WeldingPhase.heating) {
        final nom = currentPhase.nominalDuration.toInt();
        final max = currentPhase.maxDuration.toInt();
        final elapsed = _phaseElapsedSeconds;
        if (nom > 10 && elapsed == nom - 10) {
          SystemSound.play(SystemSoundType.click); // last 10-second warning
        }
        if (elapsed >= max && !_isAutoAdvancing) {
          setState(() => _isAutoAdvancing = true);
          _.cancel();
          _cancelWeld('Excessive heating time — weld cycle aborted');
        }
      }

      // t4 (buildup): auto-advance when pressure reaches cooling target
      if (currentPhase.phase == WeldingPhase.buildup && !_isAutoAdvancing) {
        final p = _latestPressure;
        final target = currentPhase.nominalPressureBar;
        if (p != null && target != null && p >= target * 0.95) {
          setState(() => _isAutoAdvancing = true);
          _.cancel();
          _completePhase(); // auto: buildup → fusion → cooling
        }
      }

      // cooling: ±8 % warn; ±10 % >2s cancel
      if (currentPhase.phase == WeldingPhase.cooling) {
        final p = _latestPressure;
        final nom = currentPhase.nominalPressureBar;
        if (p != null && nom != null) {
          final dev = (p - nom).abs() / nom;
          if (dev > 0.10) {
            setState(() {
              _coolingViolationSeconds++;
              _coolingWarningMessage =
                  'Pressure deviation ${(dev * 100).toStringAsFixed(1)} %'
                  ' — will cancel in ${(2 - _coolingViolationSeconds).clamp(0, 2)} s';
            });
            if (_coolingViolationSeconds >= 2 && !_isAutoAdvancing) {
              setState(() => _isAutoAdvancing = true);
              _.cancel();
              _cancelWeld(
                  'Cooling pressure deviation >10 % for >2 s — weld cancelled');
            }
          } else {
            setState(() {
              _coolingViolationSeconds = 0;
              _coolingWarningMessage =
                  dev > 0.08 ? 'Pressure deviation ${(dev * 100).toStringAsFixed(1)} %' : '';
            });
            if (dev > 0.08) SystemSound.play(SystemSoundType.click);
          }
        }
      }
    });
  }

  // ── Wakelock ────────────────────────────────────────────────────────────────

  Future<void> _enableWakelock() async {
    if (_wakelockEnabled) return;
    try {
      await WakelockPlus.enable();
      if (mounted) setState(() => _wakelockEnabled = true);
    } catch (_) {}
  }

  Future<void> _disableWakelock() async {
    if (!_wakelockEnabled) return;
    try {
      await WakelockPlus.disable();
      if (mounted) setState(() => _wakelockEnabled = false);
    } catch (_) {}
  }

  // ── GPS capture ─────────────────────────────────────────────────────────────

  Future<void> _captureGps() async {
    try {
      final perm = await Geolocator.checkPermission();
      LocationPermission eff = perm;
      if (perm == LocationPermission.denied) {
        eff = await Geolocator.requestPermission();
      }
      if (eff == LocationPermission.denied ||
          eff == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (mounted) {
        setState(() {
          _gpsLat = pos.latitude;
          _gpsLng = pos.longitude;
        });
      }
    } catch (_) {}
  }

  // ── Changeover t4 detection ─────────────────────────────────────────────────

  void _onChangeoverPressureUpdate(double pressureBar) {
    if (_changeoverT4Started || _isAutoAdvancing) return;

    // Track the minimum pressure seen (pipe gap after plate removal)
    if (_changeoverMinPressure == null ||
        pressureBar < _changeoverMinPressure!) {
      setState(() => _changeoverMinPressure = pressureBar);
    }

    // Pressure rising ≥ 2 bar above minimum → machine closing (t4)
    final minP = _changeoverMinPressure ?? pressureBar;
    if (pressureBar >= minP + 2.0 && !_isAutoAdvancing) {
      setState(() {
        _changeoverT4Started = true;
        _isAutoAdvancing = true;
      });
      _t4Timer?.cancel();
      _t4ElapsedSeconds = 0;
      _t4Timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() => _t4ElapsedSeconds++);
      });
      // Auto-complete changeover → buildup
      _isAutoAdvancing = false;
      _completePhase();
    }
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

          // ── Changeover banner (t3 / t4) ───────────────────────────────────
          if (_workflowState == WeldWorkflowState.phaseActive &&
              _currentPhaseIndex < widget.phases.length &&
              widget.phases[_currentPhaseIndex].phase ==
                  WeldingPhase.changeover)
            _ChangeoverBanner(
              t3Seconds: _phaseElapsedSeconds,
              t4Started: _changeoverT4Started,
              t4Seconds: _t4ElapsedSeconds,
            ),

          // ── Cooling pressure warning ───────────────────────────────────────
          if (_coolingWarningMessage.isNotEmpty)
            Container(
              color: _coolingViolationSeconds >= 1
                  ? const Color(0xFFB71C1C)
                  : const Color(0xFFF57C00),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(children: [
                const Icon(Icons.warning_amber, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _coolingWarningMessage,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
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

    final WeldingPhase? phase = currentPhase?.phase;

    switch (_workflowState) {
      // ── Idle — not yet started ─────────────────────────────────────────────
      case WeldWorkflowState.idle:
        return ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: Text('Start — ${widget.phases.first.phase.displayName}'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          onPressed: _startNextPhase,
        );

      // ── Active / violation ─────────────────────────────────────────────────
      case WeldWorkflowState.phaseActive:
      case WeldWorkflowState.parameterViolation:

        // ── beadUpAdjust: pressure adjustment before bead-up ───────────────
        if (phase == WeldingPhase.beadUpAdjust) {
          final nom = currentPhase?.nominalPressureBar ?? widget.args.fusionPressureBar;
          final drag = widget.args.dragPressureBar;
          final targetMachine = nom + drag;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TargetCard(
                label: 'Target Machine Pressure',
                value: '${targetMachine.toStringAsFixed(1)} bar',
                subtitle: 'Gauge ${nom.toStringAsFixed(1)} bar + drag ${drag.toStringAsFixed(1)} bar',
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Pressure Set — Done!'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  minimumSize: const Size(double.infinity, 52),
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
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: _showCancelDialog,
              ),
            ],
          );
        }

        // ── heatingUp (Bead Up): form bead; auto-cancel >3s violation ─────
        if (phase == WeldingPhase.heatingUp) {
          final nom = currentPhase?.nominalPressureBar ?? 0.0;
          final drag = widget.args.dragPressureBar;
          final targetMachine = nom + drag;
          final beadTarget = widget.args.beadHeightMm > 0
              ? widget.args.beadHeightMm
              : (widget.args.wallThicknessMm * 0.10 / 0.5).ceil() * 0.5;
          final mm = _beadUpViolationSeconds > 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TargetCard(
                label: 'Target Machine Pressure',
                value: '${targetMachine.toStringAsFixed(1)} bar',
                subtitle: 'Min bead height: ${beadTarget.toStringAsFixed(1)} mm',
              ),
              if (mm) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Text(
                    'Pressure deviation! Auto-cancel in ${(3 - _beadUpViolationSeconds).clamp(0, 3)} s',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Bead Formed — Done!'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  minimumSize: const Size(double.infinity, 52),
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
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: _showCancelDialog,
              ),
            ],
          );
        }

        // ── heating: countdown, max pressure, last-10s warning, Done! ─────
        if (phase == WeldingPhase.heating) {
          final nomSec    = (currentPhase?.nominalDuration ?? 0).toInt();
          final minSec    = (currentPhase?.minDuration    ?? 0).toInt();
          final maxPbar   = currentPhase?.maxPressureBar ?? 0.0;
          final drag      = widget.args.dragPressureBar;
          final remaining = (nomSec - _phaseElapsedSeconds).clamp(0, nomSec);
          final fmtR      = '${(remaining ~/ 60).toString().padLeft(2, '0')}:'
                            '${(remaining % 60).toString().padLeft(2, '0')}';
          final afterMin  = _phaseElapsedSeconds >= minSec;
          final lastTen   = remaining <= 10 && remaining > 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _TargetCard(
                      label: 'Remaining',
                      value: fmtR,
                      subtitle: 'Min: ${minSec}s — heating time',
                      highlight: lastTen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TargetCard(
                      label: 'Max Machine Pressure',
                      value: '${(maxPbar + drag).toStringAsFixed(1)} bar',
                      subtitle: 'p2 ${maxPbar.toStringAsFixed(1)} + drag ${drag.toStringAsFixed(1)}',
                    ),
                  ),
                ],
              ),
              if (lastTen) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text(
                    '⚡ Last 10 seconds of heating — prepare to remove plate!',
                    style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('Remove Heater Plate — Done!'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: afterMin ? const Color(0xFF2E7D32) : Colors.grey,
                  minimumSize: const Size(double.infinity, 52),
                ),
                onPressed: afterMin ? _completePhase : null,
              ),
              if (!afterMin) ...[
                const SizedBox(height: 6),
                Text(
                  'Button unlocks after ${minSec}s of heating',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel Weld'),
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

        // ── changeover (t3): waiting for pressure to rise (banner handles) ─
        if (phase == WeldingPhase.changeover) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: const Text(
                  'Remove the heater plate and close the machine.\n'
                  'Changeover (t4) starts automatically when pressure rises.',
                  style: TextStyle(fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel Weld'),
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

        // ── buildup (t4): auto-advancing to cooling ────────────────────────
        if (phase == WeldingPhase.buildup) {
          final target = currentPhase?.nominalPressureBar ?? 0.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TargetCard(
                label: 'Auto-advancing to Cooling when…',
                value: 'P ≥ ${target.toStringAsFixed(1)} bar',
                subtitle: 'Machine closing — maintain fusion pressure',
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel Weld'),
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

        // ── cooling: countdown + early finish ─────────────────────────────
        if (phase == WeldingPhase.cooling) {
          final nomSec  = (currentPhase?.nominalDuration ?? 0).toInt();
          final isOnTime = _phaseElapsedSeconds >= nomSec;
          final remaining = (nomSec - _phaseElapsedSeconds).clamp(0, nomSec);
          final fmtR   = '${(remaining ~/ 60).toString().padLeft(2, '0')}:'
                         '${(remaining % 60).toString().padLeft(2, '0')}';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TargetCard(
                label: isOnTime ? 'Cooling Complete' : 'Cooling Remaining',
                value: isOnTime ? '✓' : fmtR,
                subtitle: 'Keep pressure stable ± 8 % limit',
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.ac_unit),
                label: Text(isOnTime
                    ? 'Complete Cooling'
                    : 'End Cooling Early'),
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
                label: const Text('Cancel Weld'),
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

        // ── generic fallback ───────────────────────────────────────────────
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
                      ? 'Complete — Next: ${widget.phases[_currentPhaseIndex + 1].phase.displayName}'
                      : 'Complete Final Phase',
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
                label: const Text('Cancel Weld'),
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

      // ── Phase complete — auto-handled for heating/buildup ──────────────────
      case WeldWorkflowState.phaseComplete:
        final isLastPhase = _currentPhaseIndex >= widget.phases.length;
        return ElevatedButton.icon(
          icon: Icon(isLastPhase ? Icons.check_circle : Icons.navigate_next),
          label: Text(isLastPhase
              ? 'Finish Weld'
              : 'Start ${widget.phases[_currentPhaseIndex].phase.displayName}'),
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
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified, color: Color(0xFF2E7D32), size: 28),
                      SizedBox(width: 12),
                      Text(
                        'Weld Certified!',
                        style: TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                  if (_gpsLat != null && _gpsLng != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'GPS: ${_gpsLat!.toStringAsFixed(6)}, ${_gpsLng!.toStringAsFixed(6)}',
                      style: const TextStyle(
                          color: Color(0xFF2E7D32), fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Projects'),
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
                  Text('Weld cancelled — record saved',
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
              child: const Text('Back to Projects'),
            ),
          ],
        );
    }
  }

}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// Banner displayed at the top of the session screen during the changeover
/// phase. Shows t3 (plate removal) and t4 (machine closing) timers.
class _ChangeoverBanner extends StatelessWidget {
  const _ChangeoverBanner({
    required this.t3Seconds,
    required this.t4Started,
    required this.t4Seconds,
  });

  final int t3Seconds;
  final bool t4Started;
  final int t4Seconds;

  static String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: t4Started ? const Color(0xFF1565C0) : const Color(0xFFE65100),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            t4Started ? Icons.settings : Icons.remove_circle_outline,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t4Started
                  ? 'Machine closing (t4) — Build-Up pressure'
                  : 'Remove heater plate (t3)',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ),
          Text(
            t4Started ? 't4 ${_fmt(t4Seconds)}' : 't3 ${_fmt(t3Seconds)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small info card for displaying a target parameter with subtitle.
class _TargetCard extends StatelessWidget {
  const _TargetCard({
    required this.label,
    required this.value,
    this.subtitle,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String? subtitle;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? Colors.orange : const Color(0xFF1565C0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (subtitle != null)
            Text(subtitle!,
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
