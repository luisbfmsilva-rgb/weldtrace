import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';

import '../data/local/database/app_database.dart';
import '../data/local/tables/weld_steps_table.dart';
import '../services/sensor/sensor_reading.dart';
import '../services/sensor/sensor_service.dart';
import '../services/welding_trace/weld_trace_recorder.dart';
import '../services/welding_trace/weld_trace_signature.dart';
import '../services/welding_trace/weld_report_generator.dart';
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
///   4. Records each sensor reading into [WeldTraceRecorder]
///   5. Records phase completion in local DB
///
/// On [completeWeld]:
///   1. Exports the pressure × time curve from [WeldTraceRecorder]
///   2. Computes a SHA-256 joint signature via [WeldTraceSignature]
///   3. Generates a PDF report via [WeldReportGenerator]
///   4. Persists curve JSON, signature, and PDF to the weld DB row
///
/// The engine does NOT upload to the cloud — that is the [SyncService]'s job.
class WeldWorkflowEngine {
  WeldWorkflowEngine({
    required this.db,
    required this.sensorService,
    required this.weldId,
    required this.phases,
    Logger? logger,
    // ── Traceability metadata (optional — default to empty strings) ──────────
    this.machineId    = '',
    this.pipeDiameter = 0.0,
    this.pipeMaterial = '',
    this.pipeSdr      = '',
    this.projectName  = '',
    this.machineName  = '',
    WeldTraceRecorder? traceRecorder,
  })  : _logger   = logger ?? Logger(),
        _recorder = traceRecorder ?? WeldTraceRecorder();

  final AppDatabase db;
  final SensorService sensorService;
  final String weldId;
  final List<PhaseParameters> phases;
  final Logger _logger;

  // ── Traceability ──────────────────────────────────────────────────────────
  final String machineId;
  final double pipeDiameter;
  final String pipeMaterial;
  final String pipeSdr;
  final String projectName;
  final String machineName;
  final WeldTraceRecorder _recorder;

  /// Read-only view of the live recording curve.
  List<WeldTracePoint> get traceCurve => _recorder.points;

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

    // Start the trace recorder on the very first phase.
    if (_currentPhaseIndex == 1) {
      _recorder.start();
      _logger.d('[WeldWorkflow] Trace recorder started');
    }

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
  ///
  /// In order:
  ///   1. Exports the pressure × time curve from the trace recorder
  ///   2. Generates a SHA-256 joint signature
  ///   3. Generates a PDF report (failure is logged, not rethrown)
  ///   4. Saves trace data to the DB row
  ///   5. Marks the weld row as completed (IMMUTABLE after this)
  Future<void> completeWeld() async {
    sensorService.stopCapture();
    _sensorSub?.cancel();

    if (_state != WeldWorkflowState.completed &&
        _currentPhaseIndex < phases.length) {
      throw const WeldValidationException(
        'Cannot complete weld — not all phases have been completed',
      );
    }

    final completedAt = DateTime.now();

    // ── 1. Export trace curve ────────────────────────────────────────────────
    final curve = _recorder.export();

    // ── 2. Generate joint signature ──────────────────────────────────────────
    final signature = WeldTraceSignature.generate(
      machineId:    machineId,
      pipeDiameter: pipeDiameter,
      material:     pipeMaterial,
      sdr:          pipeSdr,
      curve:        curve,
      timestamp:    completedAt,
    );

    // ── 3. Serialise curve to JSON ───────────────────────────────────────────
    final curveJson = jsonEncode(curve.map((p) => p.toJson()).toList());

    // ── 4. Generate PDF report (non-fatal on failure) ────────────────────────
    Uint8List? pdfBytes;
    try {
      pdfBytes = await WeldReportGenerator.generate(
        projectName:   projectName,
        machineName:   machineName,
        diameter:      pipeDiameter,
        material:      pipeMaterial,
        sdr:           pipeSdr,
        curve:         curve,
        weldSignature: signature,
        timestamp:     completedAt,
      );
      _logger.i('[WeldWorkflow] PDF report generated (${pdfBytes.length} bytes)');
    } catch (e) {
      _logger.w('[WeldWorkflow] PDF generation failed (non-fatal): $e');
    }

    // ── 5. Persist trace data before marking completed ───────────────────────
    await db.weldsDao.saveTraceData(
      id:        weldId,
      signature: signature,
      curveJson: curveJson,
      pdfBytes:  pdfBytes,
    );

    // ── 6. Mark weld IMMUTABLE ───────────────────────────────────────────────
    await db.weldsDao.completeWeld(weldId, completedAt);
    _logger.i('[WeldWorkflow] Weld completed: $weldId | signature: $signature');
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
    // Record into the trace curve (regardless of violation status).
    // Guard inside recorder handles the case where start() was not yet called.
    if (reading.pressureBar != null) {
      _recorder.record(
        pressureBar: reading.pressureBar!,
        phase:       params.phase.displayName,
      );
    }

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
