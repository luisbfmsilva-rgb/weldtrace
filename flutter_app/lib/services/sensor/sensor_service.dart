import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

import '../../core/errors/app_exception.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/sensor_calibration_repository.dart';
import 'sensor_reading.dart';
import '../../data/local/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// BLE UUIDs for the WeldTrace pressure + temperature sensor kit.
/// These match the custom GATT characteristics on the hardware dongle.
class WeldTraceSensorUUIDs {
  static const serviceUuid = '12345678-1234-5678-1234-56789abcdef0';
  static const pressureCharUuid = '12345678-1234-5678-1234-56789abcdef1';
  static const temperatureCharUuid = '12345678-1234-5678-1234-56789abcdef2';
  static const deviceNamePrefix = 'WELDTRACE';
}

/// Connection state of the BLE sensor kit.
enum SensorConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// Manages BLE connection to the WeldTrace sensor kit and streams
/// calibrated [SensorReading] values into the local database.
///
/// Architecture:
///   • Live readings are broadcast at ~5 Hz for real-time UI updates
///     (available even outside a weld session — used by calibration screen).
///   • DB writes happen at 1 Hz only while a weld session is active.
///   • Calibration (slope + offset) is applied to every reading before
///     broadcast and before DB write.
class SensorService {
  SensorService({
    required this.db,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  final AppDatabase db;
  final Logger _logger;

  BluetoothDevice? _connectedDevice;
  String? _connectedDeviceName;
  StreamSubscription? _pressureSub;
  StreamSubscription? _temperatureSub;
  StreamSubscription? _connectionStateSub;
  Timer? _liveTimer;    // 5 Hz — UI broadcast (always on when connected)
  Timer? _samplingTimer; // 1 Hz — DB write  (only during weld capture)

  // ── Broadcast streams ───────────────────────────────────────────────────────
  final _readingController = StreamController<SensorReading>.broadcast();
  Stream<SensorReading> get readingStream => _readingController.stream;

  final _stateController =
      StreamController<SensorConnectionState>.broadcast();
  Stream<SensorConnectionState> get connectionStateStream =>
      _stateController.stream;

  SensorConnectionState _state = SensorConnectionState.disconnected;
  SensorConnectionState get state => _state;

  /// Platform name of the currently connected device (null if disconnected).
  String? get connectedDeviceName => _connectedDeviceName;

  // ── Weld capture context ────────────────────────────────────────────────────
  String? _activeWeldId;
  String? _activePhaseName;
  String? _activeWeldStepId;

  // ── Calibration coefficients ────────────────────────────────────────────────
  // corrected = raw * slope + offset
  double _pressureOffset = 0.0;
  double _pressureSlope = 1.0;
  double _temperatureOffset = 0.0;
  double _temperatureSlope = 1.0;

  // ── Latest raw readings from BLE notifications ──────────────────────────────
  double? _latestRawPressure;
  double? _latestRawTemperature;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Scan for and connect to the first WeldTrace sensor device found.
  Future<void> connect() async {
    if (_state == SensorConnectionState.connected) return;

    _emitState(SensorConnectionState.scanning);
    _logger.i('[SensorService] Starting BLE scan');

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: AppConstants.bleScanTimeoutSeconds),
        withNames: [WeldTraceSensorUUIDs.deviceNamePrefix],
      );

      final found = await FlutterBluePlus.scanResults
          .firstWhere(
            (results) => results.any(
              (r) => r.device.platformName
                  .startsWith(WeldTraceSensorUUIDs.deviceNamePrefix),
            ),
          )
          .timeout(
            const Duration(seconds: AppConstants.bleScanTimeoutSeconds),
            onTimeout: () =>
                throw const SensorException('Sensor not found in scan window'),
          );

      await FlutterBluePlus.stopScan();

      final device = found
          .firstWhere((r) => r.device.platformName
              .startsWith(WeldTraceSensorUUIDs.deviceNamePrefix))
          .device;

      await _connectToDevice(device);
    } catch (e) {
      _logger.e('[SensorService] Connection failed', error: e);
      _emitState(SensorConnectionState.error);
      rethrow;
    }
  }

  /// Disconnect and clean up all subscriptions and timers.
  Future<void> disconnect() async {
    _liveTimer?.cancel();
    _samplingTimer?.cancel();
    _pressureSub?.cancel();
    _temperatureSub?.cancel();
    _connectionStateSub?.cancel();
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    _connectedDeviceName = null;
    _latestRawPressure = null;
    _latestRawTemperature = null;
    _emitState(SensorConnectionState.disconnected);
    _logger.i('[SensorService] Disconnected');
  }

  /// Begin capturing readings for a weld session.
  void startCapture({
    required String weldId,
    required String phaseName,
    String? weldStepId,
  }) {
    _activeWeldId = weldId;
    _activePhaseName = phaseName;
    _activeWeldStepId = weldStepId;
    _startSamplingTimer();
    _logger
        .i('[SensorService] Capture started for weld $weldId phase $phaseName');
  }

  /// Stop capturing — keeps BLE connection alive and live stream running.
  void stopCapture() {
    _samplingTimer?.cancel();
    _activeWeldId = null;
    _activePhaseName = null;
    _activeWeldStepId = null;
    _logger.i('[SensorService] Capture stopped');
  }

  /// Apply calibration correction coefficients.
  /// Call before a weld session or after loading from the calibration DB.
  ///
  /// corrected = raw × slope + offset
  void applyCalibration({
    double pressureOffset = 0.0,
    double pressureSlope = 1.0,
    double temperatureOffset = 0.0,
    double temperatureSlope = 1.0,
  }) {
    _pressureOffset = pressureOffset;
    _pressureSlope = pressureSlope;
    _temperatureOffset = temperatureOffset;
    _temperatureSlope = temperatureSlope;
    _logger.d('[SensorService] Calibration applied: '
        'P slope=$pressureSlope offset=$pressureOffset | '
        'T slope=$temperatureSlope offset=$temperatureOffset');
  }

  /// Load the latest saved calibration for [machineId] from the SQLite DB
  /// and apply it automatically.
  Future<void> loadAndApplyCalibration(
    String machineId,
    SensorCalibrationRepository repo,
  ) async {
    try {
      final cals = await repo.loadForMachine(machineId);
      applyCalibration(
        pressureSlope:      cals.pressure?.slopeValue  ?? 1.0,
        pressureOffset:     cals.pressure?.offsetValue ?? 0.0,
        temperatureSlope:   cals.temperature?.slopeValue  ?? 1.0,
        temperatureOffset:  cals.temperature?.offsetValue ?? 0.0,
      );
      _logger.i('[SensorService] Calibration loaded for machine $machineId');
    } catch (e) {
      _logger.w('[SensorService] Failed to load calibration: $e — using defaults');
    }
  }

  /// Current calibration values (for display in the UI).
  ({
    double pressureSlope, double pressureOffset,
    double temperatureSlope, double temperatureOffset,
  }) get currentCalibration => (
    pressureSlope:    _pressureSlope,
    pressureOffset:   _pressureOffset,
    temperatureSlope: _temperatureSlope,
    temperatureOffset: _temperatureOffset,
  );

  void dispose() {
    _liveTimer?.cancel();
    _samplingTimer?.cancel();
    _pressureSub?.cancel();
    _temperatureSub?.cancel();
    _connectionStateSub?.cancel();
    _readingController.close();
    _stateController.close();
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _emitState(SensorConnectionState.connecting);
    _logger.i('[SensorService] Connecting to ${device.platformName}');

    await device.connect(timeout: const Duration(seconds: 10));
    _connectedDevice = device;
    _connectedDeviceName = device.platformName;

    // Monitor unexpected disconnections
    _connectionStateSub = device.connectionState.listen((cs) {
      if (cs == BluetoothConnectionState.disconnected) {
        _logger.w('[SensorService] Device disconnected unexpectedly');
        _liveTimer?.cancel();
        _samplingTimer?.cancel();
        _connectedDevice = null;
        _connectedDeviceName = null;
        _emitState(SensorConnectionState.error);
      }
    });

    final services = await device.discoverServices();
    final svcList = services.where(
      (s) => s.uuid.toString() == WeldTraceSensorUUIDs.serviceUuid,
    );

    if (svcList.isEmpty) {
      throw const SensorException(
        'WeldTrace service UUID not found on device — wrong device or firmware',
      );
    }

    for (final char in svcList.first.characteristics) {
      if (char.uuid.toString() == WeldTraceSensorUUIDs.pressureCharUuid) {
        await char.setNotifyValue(true);
        _pressureSub = char.lastValueStream.listen((bytes) {
          if (bytes.length >= 4) {
            _latestRawPressure = ByteData.sublistView(
              Uint8List.fromList(bytes),
            ).getFloat32(0, Endian.little);
          }
        });
      }
      if (char.uuid.toString() == WeldTraceSensorUUIDs.temperatureCharUuid) {
        await char.setNotifyValue(true);
        _temperatureSub = char.lastValueStream.listen((bytes) {
          if (bytes.length >= 4) {
            _latestRawTemperature = ByteData.sublistView(
              Uint8List.fromList(bytes),
            ).getFloat32(0, Endian.little);
          }
        });
      }
    }

    _emitState(SensorConnectionState.connected);
    _logger.i('[SensorService] Connected to ${device.platformName}');

    // Start the live broadcast timer — always on when connected
    _startLiveTimer();
  }

  /// 5 Hz timer: broadcasts calibrated readings to the UI.
  /// Runs continuously while connected (used by both session screen
  /// and calibration screen). No DB write here.
  void _startLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final reading = _buildCalibratedReading(
        phaseName: _activePhaseName ?? 'live',
      );
      if (!_readingController.isClosed) _readingController.add(reading);
    });
  }

  /// 1 Hz timer: writes calibrated readings to SQLite.
  /// Only active during a weld capture session.
  void _startSamplingTimer() {
    _samplingTimer?.cancel();
    _samplingTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.sensorSamplingIntervalMs),
      (_) => _sample(),
    );
  }

  Future<void> _sample() async {
    if (_activeWeldId == null) return;

    final reading = _buildCalibratedReading(
      phaseName: _activePhaseName ?? 'unknown',
    );

    await db.sensorLogsDao.insert(SensorLogsTableCompanion(
      id: Value(const Uuid().v4()),
      weldId: Value(_activeWeldId!),
      weldStepId: Value(reading.weldStepId),
      recordedAt: Value(reading.recordedAt),
      pressureBar: Value(reading.pressureBar),
      temperatureCelsius: Value(reading.temperatureCelsius),
      phaseName: Value(reading.phaseName),
      createdAt: Value(DateTime.now()),
      syncStatus: const Value('pending'),
    ));
  }

  SensorReading _buildCalibratedReading({required String phaseName}) {
    final rawP = _latestRawPressure;
    final rawT = _latestRawTemperature;
    return SensorReading(
      recordedAt: DateTime.now().toUtc(),
      phaseName: phaseName,
      pressureBar: rawP != null ? rawP * _pressureSlope + _pressureOffset : null,
      temperatureCelsius:
          rawT != null ? rawT * _temperatureSlope + _temperatureOffset : null,
      weldStepId: _activeWeldStepId,
      rawPressureBar: rawP,
      rawTemperatureCelsius: rawT,
    );
  }

  void _emitState(SensorConnectionState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }
}
