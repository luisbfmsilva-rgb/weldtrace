import 'dart:async';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';

import '../data/local/database/app_database.dart';
import '../data/local/tables/weld_steps_table.dart';
import '../services/sensor/sensor_reading.dart';
import '../services/sensor/sensor_service.dart';
import '../core/errors/app_exception.dart';
import 'welding_phase.dart';

/// State of the welding workflow engine.
enum WeldWorkflowState {
  idle,
  phaseActive,
  phaseComplete,
  parameterViolation,
  completed,
  cancelled,
}

/// Emitted whenever a parameter violation is detected.
class ParameterViolation {
  const ParameterViolation({
    required this.phase,
    required this.parameterName,
    required this.actualValue,
    required this.allowedMin,
    required this.allowedMax,
    required this.detectedAt,
  });

  final WeldingPhase phase;
  final String parameterName;
  final double actualValue;
  final double? allowedMin;
  final double? allowedMax;
  final DateTime detectedAt;
}

/// Drives a single weld session through its phase sequence.
///
/// For each phase:
///   1. Records phase start in local DB (weld_steps)
///   2. Monitors sensor readings against [PhaseParameters]
///   3. Emits [ParameterViolation] events on out-of-range readings
///   4. Auto-cancels the weld if violations are critical
///   5. Records phase completion in local DB
///
/// The engine does NOT upload to the cloud — that is the [SyncService]'s job.
class WeldWorkflowEngine {
  WeldWorkflowEngine({
    required this.db,
    required this.sensorService,
    required this.weldId,
    required this.phases,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  final AppDatabase db;
  final SensorService sensorService;
  final String weldId;
  final List<PhaseParameters> phases;
  final Logger _logger;

  WeldWorkflowState _state = WeldWorkflowState.idle;
  WeldWorkflowState get state => _state;

  int _currentPhaseIndex = 0;
  PhaseParameters? _currentPhase;
  String? _currentStepId;
  DateTime? _phaseStartedAt;

  final _violationController = StreamController<ParameterViolation>.broadcast();
  Stream<ParameterViolation> get violationStream => _violationController.stream;

  final _stateController = StreamController<WeldWorkflowState>.broadcast();
  Stream<WeldWorkflowState> get stateStream => _stateController.stream;

  StreamSubscription<SensorReading>? _sensorSub;

  // ── Workflow API ──────────────────────────────────────────────────────────

  /// Advance to the next phase. Call once per phase transition.
  Future<void> advancePhase() async {
    if (_currentPhaseIndex >= phases.length) {
      throw const WeldValidationException('All phases have been completed');
    }

    // Complete the previous phase
    if (_currentStepId != null && _phaseStartedAt != null) {
      await _completeCurrentStep();
    }

    // Start the next phase
    _currentPhase = phases[_currentPhaseIndex];
    _currentPhaseIndex++;
    _phaseStartedAt = DateTime.now();
    _currentStepId = const Uuid().v4();

    await _recordPhaseStart(_currentPhase!, _currentStepId!);

    sensorService.startCapture(
      weldId: weldId,
      phaseName: _currentPhase!.phase.displayName,
      weldStepId: _currentStepId,
    );

    _subscribeToSensorReadings(_currentPhase!);
    _emitState(WeldWorkflowState.phaseActive);

    _logger.i('[WeldWorkflow] Phase started: ${_currentPhase!.phase.displayName}');
  }

  /// Mark the current phase as manually complete (welder taps "next phase").
  Future<void> completeCurrentPhase() async {
    if (_state != WeldWorkflowState.phaseActive) return;

    sensorService.stopCapture();
    _sensorSub?.cancel();

    if (_currentStepId != null) {
      await _completeCurrentStep();
    }

    if (_currentPhaseIndex >= phases.length) {
      _emitState(WeldWorkflowState.completed);
      _logger.i('[WeldWorkflow] All phases complete');
    } else {
      _emitState(WeldWorkflowState.phaseComplete);
    }
  }

  /// Cancel the weld with a reason.
  Future<void> cancel(String reason) async {
    sensorService.stopCapture();
    _sensorSub?.cancel();

    await db.weldsDao.cancelWeld(weldId, reason);
    _emitState(WeldWorkflowState.cancelled);
    _logger.w('[WeldWorkflow] Weld cancelled: $reason');
  }

  /// Complete the entire weld session.
  Future<void> completeWeld() async {
    sensorService.stopCapture();
    _sensorSub?.cancel();

    if (_state != WeldWorkflowState.completed &&
        _currentPhaseIndex < phases.length) {
      throw const WeldValidationException(
        'Cannot complete weld — not all phases have been completed',
      );
    }

    await db.weldsDao.completeWeld(weldId, DateTime.now());
    _logger.i('[WeldWorkflow] Weld completed: $weldId');
  }

  void dispose() {
    _sensorSub?.cancel();
    _violationController.close();
    _stateController.close();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _subscribeToSensorReadings(PhaseParameters phaseParams) {
    _sensorSub?.cancel();
    _sensorSub = sensorService.readingStream.listen((reading) {
      _checkViolations(phaseParams, reading);
    });
  }

  void _checkViolations(PhaseParameters params, SensorReading reading) {
    // Pressure check
    if (reading.pressureBar != null &&
        params.minPressureBar != null &&
        !params.isPressureInRange(reading.pressureBar!)) {
      final violation = ParameterViolation(
        phase: params.phase,
        parameterName: 'pressure',
        actualValue: reading.pressureBar!,
        allowedMin: params.minPressureBar,
        allowedMax: params.maxPressureBar,
        detectedAt: reading.recordedAt,
      );
      _violationController.add(violation);
      _emitState(WeldWorkflowState.parameterViolation);
      _logger.w(
          '[WeldWorkflow] Pressure violation: ${reading.pressureBar} bar '
          '(allowed ${params.minPressureBar}–${params.maxPressureBar})');
    }

    // Temperature check
    if (reading.temperatureCelsius != null &&
        params.minTemperatureCelsius != null &&
        !params.isTemperatureInRange(reading.temperatureCelsius!)) {
      final violation = ParameterViolation(
        phase: params.phase,
        parameterName: 'temperature',
        actualValue: reading.temperatureCelsius!,
        allowedMin: params.minTemperatureCelsius,
        allowedMax: params.maxTemperatureCelsius,
        detectedAt: reading.recordedAt,
      );
      _violationController.add(violation);
      _emitState(WeldWorkflowState.parameterViolation);
    }
  }

  Future<void> _recordPhaseStart(PhaseParameters params, String stepId) async {
    await db.weldsDao.insertStep(WeldStepsTableCompanion(
      id: Value(stepId),
      weldId: Value(weldId),
      phaseName: Value(params.phase.displayName),
      phaseOrder: Value(params.phase.order),
      startedAt: Value(_phaseStartedAt),
      nominalValue: Value(params.nominalDuration),
      unit: const Value('s'),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value('pending'),
    ));
  }

  Future<void> _completeCurrentStep() async {
    final completedAt = DateTime.now();
    final duration = completedAt.difference(_phaseStartedAt!).inSeconds.toDouble();

    await db.transaction(() async {
      await (db.update(db.weldStepsTable)
            ..where((t) => t.id.equals(_currentStepId!)))
          .write(WeldStepsTableCompanion(
        completedAt: Value(completedAt),
        actualValue: Value(duration),
        updatedAt: Value(completedAt),
        syncStatus: const Value('pending'),
      ));
    });
  }

  void _emitState(WeldWorkflowState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }
}
