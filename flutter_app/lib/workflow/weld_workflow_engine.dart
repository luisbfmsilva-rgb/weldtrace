import 'dart:async';
import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';

import '../data/local/database/app_database.dart';
import '../services/sensor/sensor_reading.dart';
import '../services/sensor/sensor_service.dart';
import '../services/welding_trace/curve_compression.dart';
import '../services/welding_trace/weld_certificate.dart';
import '../services/welding_trace/weld_ledger.dart';
import '../services/welding_trace/weld_registry.dart';
import '../services/welding_trace/weld_sync_service.dart';
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
///   • Sensor readings are captured and checked against phase limits.
///   • Violations are broadcast on [violationStream].
///   • The pressure × time curve is recorded automatically.
///
/// On [completeWeld]:
///   1. Exports the pressure × time curve
///   2. Generates a SHA-256 joint signature (includes welding parameters)
///   3. Serialises the curve to JSON
///   3b. Gzip-compresses the curve bytes
///   4. Determines trace quality ('OK' / 'LOW_SAMPLE_COUNT') — before PDF
///   5. Generates a professional PDF engineering report (non-fatal on failure)
///   6. Saves trace data to the DB row (compressed + plain JSON + PDF)
///   6b. Appends entry to the local certification ledger (non-fatal)
///   6c. Appends entry to the global certification registry (non-fatal)
///   6d. Attempts SaaS certificate upload via [WeldSyncService] (non-blocking)
///   7. Marks the weld row as completed (IMMUTABLE after this)
class WeldWorkflowEngine {
  WeldWorkflowEngine({
    required this.db,
    required this.sensorService,
    required this.weldId,
    required this.phases,
    Logger? logger,
    // ── Traceability metadata (optional — default to empty strings / zeros) ─
    this.machineId               = '',
    this.pipeDiameter            = 0.0,
    this.pipeMaterial            = '',
    this.pipeSdr                 = '',
    this.projectName             = '',
    this.machineName             = '',
    // ── Extended welding process parameters ──────────────────────────────────
    this.operatorName            = '',
    this.operatorId              = '',
    this.machineModel            = '',
    this.machineSerialNumber     = '',
    this.hydraulicCylinderAreaMm2 = 0.0,
    this.jointId                 = '',
    this.wallThicknessStr        = '',
    this.standardUsed            = '',
    this.fusionPressureBar       = 0.0,
    this.heatingTimeSec          = 0.0,
    this.coolingTimeSec          = 0.0,
    this.beadHeightMm            = 0.0,
    WeldTraceRecorder? traceRecorder,
    WeldSyncService?   syncService,
  })  : _logger      = logger ?? Logger(),
        _recorder    = traceRecorder ?? WeldTraceRecorder(),
        _syncService = syncService  ?? const WeldSyncService();

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

  // ── Extended welding process metadata ─────────────────────────────────────
  final String operatorName;
  final String operatorId;
  final String machineModel;
  final String machineSerialNumber;
  final double hydraulicCylinderAreaMm2;
  final String jointId;
  final String wallThicknessStr;
  final String standardUsed;
  final double fusionPressureBar;
  final double heatingTimeSec;
  final double coolingTimeSec;
  final double beadHeightMm;

  final WeldTraceRecorder _recorder;
  final WeldSyncService   _syncService;

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
  ///
  /// Always generates a partial PDF report for traceability (non-fatal on
  /// PDF failure — record is still cancelled even without a PDF).
  Future<void> cancel(String reason) async {
    sensorService.stopCapture();
    _sensorSub?.cancel();

    final cancelledAt = DateTime.now().toUtc();
    final curve       = _recorder.export();
    final jointId     = const Uuid().v7();

    // ── Partial trace data ────────────────────────────────────────────────
    String? curveJson;
    Uint8List? curveCompressed;
    String? signature;
    try {
      curveJson = jsonEncode(curve.map((p) => p.toJson()).toList());
      curveCompressed = CurveCompression.compressCurve(curveJson);
      signature = WeldTraceSignature.generate(
        machineId:         machineId,
        pipeDiameter:      pipeDiameter,
        material:          pipeMaterial,
        sdr:               pipeSdr,
        curve:             curve,
        timestamp:         cancelledAt,
        fusionPressureBar: fusionPressureBar,
        heatingTimeSec:    heatingTimeSec,
        coolingTimeSec:    coolingTimeSec,
        beadHeightMm:      beadHeightMm,
      );
    } catch (e) {
      _logger.w('[WeldWorkflow] Cancel — partial trace failed (non-fatal): $e');
    }

    // ── Cancellation PDF report ───────────────────────────────────────────
    Uint8List? pdfBytes;
    try {
      pdfBytes = await WeldReportGenerator.generate(
        projectName:             projectName,
        machineName:             machineName,
        machineId:               machineId,
        diameter:                pipeDiameter,
        material:                pipeMaterial,
        sdr:                     pipeSdr,
        curve:                   curve,
        weldSignature:           signature ?? '',
        timestamp:               cancelledAt.toLocal(),
        operatorName:            operatorName,
        operatorId:              operatorId,
        jointId:                 jointId,
        wallThicknessStr:        wallThicknessStr,
        standardUsed:            standardUsed,
        fusionPressureBar:       fusionPressureBar,
        heatingTimeSec:          heatingTimeSec,
        coolingTimeSec:          coolingTimeSec,
        beadHeightMm:            beadHeightMm,
        traceQuality:            curve.length >= 2 ? 'OK' : 'LOW_SAMPLE_COUNT',
        machineModel:            machineModel,
        machineSerialNumber:     machineSerialNumber,
        hydraulicCylinderAreaMm2: hydraulicCylinderAreaMm2,
        completionStatus:        'cancelled',
        cancelReason:            reason,
      );
      _logger.i('[WeldWorkflow] Cancellation PDF generated (${pdfBytes.length} bytes)');
    } catch (e) {
      _logger.w('[WeldWorkflow] Cancellation PDF failed (non-fatal): $e');
    }

    await db.weldsDao.cancelWithReport(
      id:                   weldId,
      reason:               reason,
      pdfBytes:             pdfBytes,
      curveJson:            curveJson,
      traceCurveCompressed: curveCompressed,
      traceSignature:       signature,
      traceQuality:         curve.length >= 2 ? 'OK' : 'LOW_SAMPLE_COUNT',
      jointId:              jointId,
    );

    _emitState(WeldWorkflowState.cancelled);
    _logger.w('[WeldWorkflow] Weld cancelled: $reason');
  }

  /// Complete the entire weld session.
  ///
  /// Completes the weld, generates the PDF certificate, and marks IMMUTABLE.
  ///
  /// [coolingIncomplete] — pass true when the operator ended cooling before
  /// the nominal cooling time elapsed.  The PDF will include a warning banner.
  Future<void> completeWeld({bool coolingIncomplete = false}) async {
    sensorService.stopCapture();
    _sensorSub?.cancel();

    if (_state != WeldWorkflowState.completed &&
        _currentPhaseIndex < phases.length) {
      throw const WeldValidationException(
        'Cannot complete weld — not all phases have been completed',
      );
    }

    final completedAt = DateTime.now().toUtc();

    // ── 0. Generate globally-unique joint ID ──────────────────────────────
    final jointId = const Uuid().v7();
    _logger.d('[WeldWorkflow] Joint ID: $jointId');

    // ── 1. Export trace curve ─────────────────────────────────────────────
    final curve = _recorder.export();

    // ── 2. Generate joint signature ───────────────────────────────────────
    final signature = WeldTraceSignature.generate(
      machineId:         machineId,
      pipeDiameter:      pipeDiameter,
      material:          pipeMaterial,
      sdr:               pipeSdr,
      curve:             curve,
      timestamp:         completedAt,
      fusionPressureBar: fusionPressureBar,
      heatingTimeSec:    heatingTimeSec,
      coolingTimeSec:    coolingTimeSec,
      beadHeightMm:      beadHeightMm,
    );

    // ── 3. Serialise curve to JSON ─────────────────────────────────────────
    final curveJson = jsonEncode(curve.map((p) => p.toJson()).toList());

    // ── 3b. Gzip-compress curve ────────────────────────────────────────────
    final curveCompressed = CurveCompression.compressCurve(curveJson);
    _logger.d(
      '[WeldWorkflow] Curve compressed: ${curveJson.length} chars → '
      '${curveCompressed.length} bytes '
      '(${(curveCompressed.length / curveJson.length * 100).toStringAsFixed(1)}%)',
    );

    // ── 4. Determine trace quality (moved before PDF so it is included) ──────
    final traceQuality = curve.length >= 2 ? 'OK' : 'LOW_SAMPLE_COUNT';
    if (traceQuality == 'LOW_SAMPLE_COUNT') {
      _logger.w('[WeldWorkflow] Low sample count: ${curve.length} samples recorded');
    }

    // ── 5. Generate PDF report (non-fatal on failure) ─────────────────────
    Uint8List? pdfBytes;
    try {
      pdfBytes = await WeldReportGenerator.generate(
        projectName:              projectName,
        machineName:              machineName,
        machineId:                machineId,
        diameter:                 pipeDiameter,
        material:                 pipeMaterial,
        sdr:                      pipeSdr,
        curve:                    curve,
        weldSignature:            signature,
        timestamp:                completedAt.toLocal(),
        operatorName:             operatorName,
        operatorId:               operatorId,
        jointId:                  jointId,
        wallThicknessStr:         wallThicknessStr,
        standardUsed:             standardUsed,
        fusionPressureBar:        fusionPressureBar,
        heatingTimeSec:           heatingTimeSec,
        coolingTimeSec:           coolingTimeSec,
        beadHeightMm:             beadHeightMm,
        traceQuality:             traceQuality,
        machineModel:             machineModel,
        machineSerialNumber:      machineSerialNumber,
        hydraulicCylinderAreaMm2: hydraulicCylinderAreaMm2,
        completionStatus: coolingIncomplete ? 'cooling_incomplete' : 'completed',
      );
      _logger.i('[WeldWorkflow] PDF report generated (${pdfBytes.length} bytes)');
    } catch (e) {
      _logger.w('[WeldWorkflow] PDF generation failed (non-fatal): $e');
    }

    // ── 5b. Persist coolingIncomplete flag ────────────────────────────────
    if (coolingIncomplete) {
      try {
        await db.weldsDao.saveCoolingFlag(
          id: weldId,
          coolingIncomplete: true,
        );
      } catch (e) {
        _logger.w('[WeldWorkflow] saveCoolingFlag failed (non-fatal): $e');
      }
    }

    // ── 6. Persist trace data before marking completed ─────────────────────
    await db.weldsDao.saveTraceData(
      id:                   weldId,
      signature:            signature,
      curveJson:            curveJson,
      traceCurveCompressed: curveCompressed,
      pdfBytes:             pdfBytes,
      traceQuality:         traceQuality,
      jointId:              jointId,
    );

    // ── 6b. Append to local certification ledger ──────────────────────────
    try {
      await WeldLedger.append(WeldLedgerEntry(
        jointId:   jointId,
        signature: signature,
        timestamp: completedAt,
        machineId: machineId,
        diameter:  pipeDiameter,
        material:  pipeMaterial,
      ));
      _logger.d('[WeldWorkflow] Ledger entry appended: $jointId');
    } catch (e) {
      _logger.w('[WeldWorkflow] Ledger append failed (non-fatal): $e');
    }

    // ── 6c. Append to global certification registry ────────────────────────
    try {
      await WeldRegistry.append(WeldRegistryEntry(
        jointId:   jointId,
        signature: signature,
        timestamp: completedAt,
        machineId: machineId,
        diameter:  pipeDiameter,
        material:  pipeMaterial,
        sdr:       pipeSdr,
      ));
      _logger.d('[WeldWorkflow] Registry entry appended: $jointId');
    } catch (e) {
      _logger.w('[WeldWorkflow] Registry append failed (non-fatal): $e');
    }

    // ── 6d. Optional SaaS sync (non-blocking, non-fatal) ──────────────────
    try {
      final cert = WeldCertificate.generateCertificate(
        jointId:        jointId,
        signature:      signature,
        timestamp:      completedAt,
        machineId:      machineId,
        diameter:       pipeDiameter,
        material:       pipeMaterial,
        sdr:            pipeSdr,
        traceQuality:   traceQuality,
        fusionPressure: fusionPressureBar != 0.0 ? fusionPressureBar : null,
        heatingTime:    heatingTimeSec   != 0.0 ? heatingTimeSec   : null,
        coolingTime:    coolingTimeSec   != 0.0 ? coolingTimeSec   : null,
        beadHeight:     beadHeightMm     != 0.0 ? beadHeightMm     : null,
        syncStatus:     CertSyncStatus.pending,
      );
      final syncResult = await _syncService.uploadCertificate(cert);
      if (syncResult.offline) {
        _logger.d('[WeldWorkflow] Sync offline — certificate not uploaded: $jointId');
      } else if (syncResult.success) {
        _logger.i('[WeldWorkflow] Certificate synced to cloud: $jointId');
      } else {
        _logger.w('[WeldWorkflow] Certificate sync failed (non-fatal): '
            '${syncResult.message}');
      }
    } catch (e) {
      _logger.w('[WeldWorkflow] Certificate sync threw (non-fatal): $e');
    }

    // ── 7. Mark weld IMMUTABLE ─────────────────────────────────────────────
    await db.weldsDao.completeWeld(weldId, completedAt);
    _logger.i(
      '[WeldWorkflow] Weld completed: $weldId | joint: $jointId | '
      'signature: $signature',
    );
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
