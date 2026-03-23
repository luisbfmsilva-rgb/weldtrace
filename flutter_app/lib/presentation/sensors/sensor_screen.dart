import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../di/providers.dart';
import '../../services/sensor/sensor_service.dart';

/// Main sensor management screen.
///
/// Shows:
///   • BLE connection status (with device name)
///   • Live calibrated pressure + temperature readings (5 Hz update)
///   • Rolling 60-second mini-chart
///   • Current calibration coefficients
///   • Buttons: Connect / Disconnect / Calibrate
class SensorScreen extends ConsumerStatefulWidget {
  const SensorScreen({super.key});

  @override
  ConsumerState<SensorScreen> createState() => _SensorScreenState();
}

class _SensorScreenState extends ConsumerState<SensorScreen> {
  SensorConnectionState _state = SensorConnectionState.disconnected;
  double? _pressure;
  double? _temperature;
  String? _error;

  // Rolling 60-point history for the mini-chart
  final Queue<_Reading> _pressureHistory    = Queue();
  final Queue<_Reading> _temperatureHistory = Queue();
  static const _historyMax = 60;

  // Discovered BLE devices during scan (for diagnostics)
  List<ScanResult> _scanDevices = [];

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    final sensor = ref.read(sensorServiceProvider);
    _state = sensor.state;
    _subs.add(sensor.connectionStateStream.listen((s) {
      if (mounted) {
        setState(() {
          _state = s;
          if (s == SensorConnectionState.error) _error = 'Connection lost';
          // Clear scan list once connected or on error
          if (s == SensorConnectionState.connected) _scanDevices = [];
        });
      }
    }));
    _subs.add(sensor.readingStream.listen((r) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _pressure    = r.pressureBar;
        _temperature = r.temperatureCelsius;
        if (r.pressureBar != null) {
          _pressureHistory.add(_Reading(now, r.pressureBar!));
          if (_pressureHistory.length > _historyMax) _pressureHistory.removeFirst();
        }
        if (r.temperatureCelsius != null) {
          _temperatureHistory.add(_Reading(now, r.temperatureCelsius!));
          if (_temperatureHistory.length > _historyMax) _temperatureHistory.removeFirst();
        }
      });
    }));
    // Diagnostic: show all BLE devices found during scan
    _subs.add(sensor.scanResultsStream.listen((results) {
      if (mounted) setState(() => _scanDevices = results);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() { _error = null; });
    try {
      await ref.read(sensorServiceProvider).connect();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _disconnect() async {
    await ref.read(sensorServiceProvider).disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final sensor     = ref.read(sensorServiceProvider);
    final cal        = sensor.currentCalibration;
    final isConnected = _state == SensorConnectionState.connected;
    final isWorking   = _state == SensorConnectionState.scanning ||
                        _state == SensorConnectionState.connecting;
    final deviceName = sensor.connectedDeviceName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Sensor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Calibrate sensors',
            onPressed: () => context
                .push('/sensors/calibrate')
                .then((_) { if (mounted) setState(() {}); }),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Connection status ──────────────────────────────────────────
            _ConnectionCard(
              state:      _state,
              deviceName: deviceName,
            ),
            const SizedBox(height: 16),

            // ── Live readings ──────────────────────────────────────────────
            if (isConnected) ...[
              Row(
                children: [
                  Expanded(
                    child: _LiveValueCard(
                      label: 'Pressure',
                      value: _pressure != null
                          ? '${_pressure!.toStringAsFixed(3)}'
                          : '—',
                      unit: 'bar',
                      color: theme.colorScheme.primary,
                      icon: Icons.compress,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LiveValueCard(
                      label: 'Temperature',
                      value: _temperature != null
                          ? '${_temperature!.toStringAsFixed(2)}'
                          : '—',
                      unit: '°C',
                      color: theme.colorScheme.error,
                      icon: Icons.thermostat,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Mini rolling chart
              if (_pressureHistory.isNotEmpty || _temperatureHistory.isNotEmpty)
                _MiniChart(
                  pressureHistory:    _pressureHistory.toList(),
                  temperatureHistory: _temperatureHistory.toList(),
                  pressureColor:      theme.colorScheme.primary,
                  temperatureColor:   theme.colorScheme.error,
                ),
              const SizedBox(height: 16),
            ],

            // ── Error banner ───────────────────────────────────────────────
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber,
                      color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            color: theme.colorScheme.onErrorContainer)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── Connect / Disconnect ───────────────────────────────────────
            if (!isConnected)
              ElevatedButton.icon(
                icon: isWorking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.bluetooth_searching),
                label: Text(isWorking ? 'Connecting…' : 'Connect to Sensor'),
                onPressed: isWorking ? null : _connect,
              )
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.bluetooth_disabled),
                label: const Text('Disconnect'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
                onPressed: _disconnect,
              ),

            const SizedBox(height: 16),

            // ── Calibration card ───────────────────────────────────────────
            _CalibrationSummaryCard(
              pressureSlope:     cal.pressureSlope,
              pressureOffset:    cal.pressureOffset,
              temperatureSlope:  cal.temperatureSlope,
              temperatureOffset: cal.temperatureOffset,
              onCalibrate: () => context
                .push('/sensors/calibrate')
                .then((_) { if (mounted) setState(() {}); }),
            ),

            const SizedBox(height: 16),

            // ── BLE Diagnostic panel (visible during scan) ────────────────
            if (_state == SensorConnectionState.scanning &&
                _scanDevices.isNotEmpty) ...[
              const SizedBox(height: 16),
              _BleScanDiagnosticPanel(devices: _scanDevices),
            ],

            const SizedBox(height: 16),

            // ── Instructions ───────────────────────────────────────────────
            Text(
              'Power on the ESP32 / WeldTrace sensor and ensure it is within '
              '5 m. The app connects by device name (starts with "WELDTRACE") '
              'or by matching the service UUID.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Connection card ───────────────────────────────────────────────────────────

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.state, this.deviceName});
  final SensorConnectionState state;
  final String? deviceName;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      SensorConnectionState.connected =>
        ('Connected', const Color(0xFF2E7D32), Icons.bluetooth_connected),
      SensorConnectionState.scanning =>
        ('Scanning…', Colors.orange, Icons.bluetooth_searching),
      SensorConnectionState.connecting =>
        ('Connecting…', Colors.orange, Icons.bluetooth_searching),
      SensorConnectionState.error =>
        ('Connection Error', Theme.of(context).colorScheme.error,
            Icons.bluetooth_disabled),
      SensorConnectionState.disconnected =>
        ('Not Connected', Colors.grey, Icons.bluetooth_disabled),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sensor Status',
                  style: TextStyle(
                      fontSize: 11,
                      color: color.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600)),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 18)),
              if (deviceName != null)
                Text(deviceName!,
                    style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Live value card ───────────────────────────────────────────────────────────

class _LiveValueCard extends StatelessWidget {
  const _LiveValueCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: color.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: color.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: color),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                        fontSize: 14,
                        color: color.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── Mini rolling chart ────────────────────────────────────────────────────────

class _Reading {
  _Reading(this.time, this.value);
  final DateTime time;
  final double value;
}

class _MiniChart extends StatelessWidget {
  const _MiniChart({
    required this.pressureHistory,
    required this.temperatureHistory,
    required this.pressureColor,
    required this.temperatureColor,
  });

  final List<_Reading> pressureHistory;
  final List<_Reading> temperatureHistory;
  final Color pressureColor;
  final Color temperatureColor;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 12, height: 3,
                    color: pressureColor),
                const SizedBox(width: 4),
                Text('Pressure (bar)',
                    style: TextStyle(fontSize: 10, color: pressureColor,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                Container(width: 12, height: 3,
                    color: temperatureColor),
                const SizedBox(width: 4),
                Text('Temp (°C)',
                    style: TextStyle(fontSize: 10, color: temperatureColor,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                child: CustomPaint(
                  painter: _ChartPainter(
                    pressurePoints:    pressureHistory,
                    temperaturePoints: temperatureHistory,
                    pressureColor:     pressureColor,
                    temperatureColor:  temperatureColor,
                  ),
                  size: Size.infinite,
                ),
              ),
              const SizedBox(height: 4),
              Text('Last ${_MiniChart._seconds} s',
                  style: TextStyle(
                      fontSize: 9, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );

  static const _seconds = 60;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.pressurePoints,
    required this.temperaturePoints,
    required this.pressureColor,
    required this.temperatureColor,
  });

  final List<_Reading> pressurePoints;
  final List<_Reading> temperaturePoints;
  final Color pressureColor;
  final Color temperatureColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (pressurePoints.isEmpty && temperaturePoints.isEmpty) return;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawSeries(canvas, size, pressurePoints, pressureColor);
    _drawSeries(canvas, size, temperaturePoints, temperatureColor);
  }

  void _drawSeries(Canvas canvas, Size size, List<_Reading> pts, Color color) {
    if (pts.length < 2) return;
    final minV = pts.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    final maxV = pts.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs();
    final span  = range < 0.001 ? 1.0 : range * 1.2;
    final mid   = (minV + maxV) / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final now  = DateTime.now();

    double xOf(_Reading r) =>
        size.width * (1 - now.difference(r.time).inSeconds / 60.0).clamp(0, 1);
    double yOf(_Reading r) =>
        size.height * (1 - (r.value - (mid - span / 2)) / span).clamp(0, 1);

    path.moveTo(xOf(pts.first), yOf(pts.first));
    for (final r in pts.skip(1)) {
      path.lineTo(xOf(r), yOf(r));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

// ── Calibration summary card ──────────────────────────────────────────────────

class _CalibrationSummaryCard extends StatelessWidget {
  const _CalibrationSummaryCard({
    required this.pressureSlope,
    required this.pressureOffset,
    required this.temperatureSlope,
    required this.temperatureOffset,
    required this.onCalibrate,
  });

  final double pressureSlope;
  final double pressureOffset;
  final double temperatureSlope;
  final double temperatureOffset;
  final VoidCallback onCalibrate;

  bool get _isDefault =>
      pressureSlope == 1.0 && pressureOffset == 0.0 &&
      temperatureSlope == 1.0 && temperatureOffset == 0.0;

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final color  = _isDefault ? Colors.orange : const Color(0xFF2E7D32);
    final status = _isDefault ? 'Default (uncalibrated)' : 'Custom calibration active';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 16, color: color),
              const SizedBox(width: 6),
              Text('Calibration',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(status,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CalRow(
            icon: Icons.compress,
            label: 'Pressure',
            formula:
                'P_cal = P_raw × ${pressureSlope.toStringAsFixed(6)} + ${pressureOffset.toStringAsFixed(4)}',
          ),
          const SizedBox(height: 4),
          _CalRow(
            icon: Icons.thermostat,
            label: 'Temperature',
            formula:
                'T_cal = T_raw × ${temperatureSlope.toStringAsFixed(6)} + ${temperatureOffset.toStringAsFixed(4)}',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Calibrate Sensors'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              side: BorderSide(color: theme.colorScheme.primary),
              minimumSize: const Size(double.infinity, 44),
            ),
            onPressed: onCalibrate,
          ),
        ],
      ),
    );
  }
}

class _CalRow extends StatelessWidget {
  const _CalRow({required this.icon, required this.label, required this.formula});
  final IconData icon;
  final String label;
  final String formula;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.grey)),
                Text(formula,
                    style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      );
}

// ── BLE scan diagnostic panel ─────────────────────────────────────────────────

/// Shows all BLE devices visible during scan so the user can verify
/// the ESP32's advertised name and service UUIDs.
class _BleScanDiagnosticPanel extends StatelessWidget {
  const _BleScanDiagnosticPanel({required this.devices});
  final List<ScanResult> devices;

  static const _targetPrefix = WeldTraceSensorUUIDs.deviceNamePrefix;
  static const _targetService = WeldTraceSensorUUIDs.serviceUuid;

  bool _isMatch(ScanResult r) {
    final nameMatch = r.device.platformName
        .toUpperCase()
        .startsWith(_targetPrefix.toUpperCase());
    final serviceMatch = r.advertisementData.serviceUuids.any(
      (u) => u.toString().toLowerCase() == _targetService.toLowerCase(),
    );
    return nameMatch || serviceMatch;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [
              Icon(Icons.bluetooth_searching,
                  size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(
                'Dispositivos BLE visíveis (${devices.length})',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.blue.shade800),
              ),
            ]),
          ),
          const Divider(height: 1),
          ...devices.map((r) {
            final matched = _isMatch(r);
            final name = r.device.platformName.isEmpty
                ? '(sem nome)'
                : r.device.platformName;
            final uuids = r.advertisementData.serviceUuids;
            return Container(
              color: matched
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.transparent,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    matched
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: matched
                        ? const Color(0xFF2E7D32)
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: matched
                                ? const Color(0xFF2E7D32)
                                : Colors.black87,
                          ),
                        ),
                        Text(
                          r.device.remoteId.toString(),
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontFamily: 'monospace'),
                        ),
                        if (uuids.isNotEmpty)
                          Text(
                            'Service: ${uuids.map((u) => u.toString()).join(', ')}',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                                fontFamily: 'monospace'),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${r.rssi} dBm',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Text(
              'O app conecta automaticamente ao dispositivo com nome '
              'iniciando em "$_targetPrefix" (maiúsc./minúsc. ignoradas) '
              'ou com service UUID $_targetService.',
              style:
                  TextStyle(fontSize: 10, color: Colors.blue.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
