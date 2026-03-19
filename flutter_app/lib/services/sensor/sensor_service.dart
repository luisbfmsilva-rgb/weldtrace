import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

import '../../core/errors/app_exception.dart';
import '../../core/constants/app_constants.dart';
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
/// calibrated [SensorReading] values at 1 Hz into the local database.
///
/// Architecture note:
///   Readings are written to local SQLite immediately. The Sync Service
///   uploads them in batches (up to 200) after each phase completes.
class SensorService {
  SensorService({
    required this.db,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  final AppDatabase db;
  final Logger _logger;

  BluetoothDevice? _connectedDevice;
  StreamSubscription? _pressureSub;
  StreamSubscription? _temperatureSub;
  Timer? _samplingTimer;

  // Live readings streamed to the UI
  final _readingController = StreamController<SensorReading>.broadcast();
  Stream<SensorReading> get readingStream => _readingController.stream;

  final _stateController =
      StreamController<SensorConnectionState>.broadcast();
  Stream<SensorConnectionState> get connectionStateStream =>
      _stateController.stream;

  SensorConnectionState _state = SensorConnectionState.disconnected;
  SensorConnectionState get state => _state;

  // Current weld context (set when welding session starts)
  String? _activeWeldId;
  String? _activePhaseName;
  String? _activeWeldStepId;

  // Calibration values (loaded from DB before session)
  double _pressureOffset = 0.0;
  double _pressureSlope = 1.0;
  double _temperatureOffset = 0.0;
  double _temperatureSlope = 1.0;

  // In-memory latest readings (populated from BLE notifications)
  double? _latestPressure;
  double? _latestTemperature;

  // ── Public API ─────────────────────────────────────────────────────────────

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
            onTimeout: () => throw const SensorException('Sensor not found in scan window'),
          );

      await FlutterBluePlus.stopScan();

      final device = found
          .firstWhere((r) =>
              r.device.platformName.startsWith(WeldTraceSensorUUIDs.deviceNamePrefix))
          .device;

      await _connectToDevice(device);
    } catch (e) {
      _logger.e('[SensorService] Connection failed', error: e);
      _emitState(SensorConnectionState.error);
      rethrow;
    }
  }

  /// Disconnect and clean up.
  Future<void> disconnect() async {
    _samplingTimer?.cancel();
    _pressureSub?.cancel();
    _temperatureSub?.cancel();
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
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
    _logger.i('[SensorService] Capture started for weld $weldId phase $phaseName');
  }

  /// Stop capturing — keeps connection alive.
  void stopCapture() {
    _samplingTimer?.cancel();
    _activeWeldId = null;
    _activePhaseName = null;
    _activeWeldStepId = null;
    _logger.i('[SensorService] Capture stopped');
  }

  /// Update calibration values before a session.
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
  }

  void dispose() {
    _samplingTimer?.cancel();
    _pressureSub?.cancel();
    _temperatureSub?.cancel();
    _readingController.close();
    _stateController.close();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _emitState(SensorConnectionState.connecting);
    _logger.i('[SensorService] Connecting to ${device.platformName}');

    await device.connect(timeout: const Duration(seconds: 10));
    _connectedDevice = device;

    final services = await device.discoverServices();
    final svc = services.where(
      (s) => s.uuid.toString() == WeldTraceSensorUUIDs.serviceUuid,
    );

    if (svc.isEmpty) {
      throw const SensorException(
        'WeldTrace service UUID not found on device — wrong device or firmware',
      );
    }

    for (final char in svc.first.characteristics) {
      if (char.uuid.toString() == WeldTraceSensorUUIDs.pressureCharUuid) {
        await char.setNotifyValue(true);
        _pressureSub = char.lastValueStream.listen((bytes) {
          if (bytes.length >= 4) {
            final rawBar = ByteData.sublistView(
              Uint8List.fromList(bytes).buffer.asUint8List(),
            ).getFloat32(0, Endian.little);
            _latestPressure = rawBar;
          }
        });
      }
      if (char.uuid.toString() == WeldTraceSensorUUIDs.temperatureCharUuid) {
        await char.setNotifyValue(true);
        _temperatureSub = char.lastValueStream.listen((bytes) {
          if (bytes.length >= 4) {
            final rawC = ByteData.sublistView(
              Uint8List.fromList(bytes).buffer.asUint8List(),
            ).getFloat32(0, Endian.little);
            _latestTemperature = rawC;
          }
        });
      }
    }

    _emitState(SensorConnectionState.connected);
    _logger.i('[SensorService] Connected and subscribed to ${device.platformName}');
  }

  void _startSamplingTimer() {
    _samplingTimer?.cancel();
    _samplingTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.sensorSamplingIntervalMs),
      (_) => _sample(),
    );
  }

  Future<void> _sample() async {
    if (_activeWeldId == null) return;

    final rawReading = SensorReading(
      recordedAt: DateTime.now().toUtc(),
      phaseName: _activePhaseName ?? 'unknown',
      pressureBar: _latestPressure,
      temperatureCelsius: _latestTemperature,
      weldStepId: _activeWeldStepId,
    );

    final calibrated = rawReading.calibrated(
      pressureOffset: _pressureOffset,
      pressureSlope: _pressureSlope,
      temperatureOffset: _temperatureOffset,
      temperatureSlope: _temperatureSlope,
    );

    // Broadcast to UI
    if (!_readingController.isClosed) {
      _readingController.add(calibrated);
    }

    // Write to local SQLite
    await db.sensorLogsDao.insert(SensorLogsTableCompanion(
      id: Value(const Uuid().v4()),
      weldId: Value(_activeWeldId!),
      weldStepId: Value(calibrated.weldStepId),
      recordedAt: Value(calibrated.recordedAt),
      pressureBar: Value(calibrated.pressureBar),
      temperatureCelsius: Value(calibrated.temperatureCelsius),
      phaseName: Value(calibrated.phaseName),
      createdAt: Value(DateTime.now()),
      syncStatus: const Value('pending'),
    ));
  }

  void _emitState(SensorConnectionState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }
}
