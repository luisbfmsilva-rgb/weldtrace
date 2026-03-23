import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';
import '../../services/sensor/sensor_service.dart';

// ── Calibration math helpers ──────────────────────────────────────────────────

class _CalPoint {
  _CalPoint({required this.raw, required this.reference});
  final double raw;
  final double reference;
}

class _RegressionResult {
  const _RegressionResult({
    required this.slope,
    required this.offset,
    required this.rSquared,
    required this.rmse,
  });

  final double slope;
  final double offset;
  final double rSquared;
  final double rmse;

  /// Single-point offset-only (slope = 1).
  factory _RegressionResult.singlePoint(double raw, double reference) {
    final offset = reference - raw;
    return _RegressionResult(slope: 1.0, offset: offset, rSquared: 1.0, rmse: 0.0);
  }

  /// Ordinary least-squares linear regression (≥ 2 points).
  factory _RegressionResult.ols(List<_CalPoint> pts) {
    final n = pts.length;
    final xBar = pts.map((p) => p.raw).reduce((a, b) => a + b) / n;
    final yBar = pts.map((p) => p.reference).reduce((a, b) => a + b) / n;

    double sxy = 0, sxx = 0;
    for (final p in pts) {
      sxy += (p.raw - xBar) * (p.reference - yBar);
      sxx += (p.raw - xBar) * (p.raw - xBar);
    }

    final slope  = sxx == 0 ? 1.0 : sxy / sxx;
    final offset = yBar - slope * xBar;

    double ssTot = 0, ssRes = 0;
    for (final p in pts) {
      final yhat = slope * p.raw + offset;
      ssRes += (p.reference - yhat) * (p.reference - yhat);
      ssTot += (p.reference - yBar) * (p.reference - yBar);
    }

    final r2   = ssTot == 0 ? 1.0 : 1.0 - ssRes / ssTot;
    final rmse = n > 0 ? math.sqrt(ssRes / n) : 0.0;

    return _RegressionResult(slope: slope, offset: offset, rSquared: r2, rmse: rmse);
  }

  static _RegressionResult? compute(List<_CalPoint> pts) {
    if (pts.isEmpty) return null;
    if (pts.length == 1) return _RegressionResult.singlePoint(pts[0].raw, pts[0].reference);
    return _RegressionResult.ols(pts);
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Live readings from sensor
  double? _livePressure;
  double? _liveTemperature;
  double? _liveRawPressure;
  double? _liveRawTemperature;
  SensorConnectionState _sensorState = SensorConnectionState.disconnected;

  // Calibration points for each sensor
  final List<_CalPoint> _pressurePoints    = [];
  final List<_CalPoint> _temperaturePoints = [];

  // Reference value text controllers
  final _pressureRefCtrl    = TextEditingController();
  final _temperatureRefCtrl = TextEditingController();

  // Metadata for saving
  final _refDeviceCtrl  = TextEditingController(text: 'External reference');
  final _operatorCtrl   = TextEditingController();
  String? _selectedMachineId;

  // Saving state
  bool _isSavingPressure    = false;
  bool _isSavingTemperature = false;
  String? _saveError;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _listenToSensor();
  }

  void _listenToSensor() {
    final sensor = ref.read(sensorServiceProvider);
    _sensorState = sensor.state;
    _subs.add(sensor.connectionStateStream.listen((s) {
      if (mounted) setState(() => _sensorState = s);
    }));
    _subs.add(sensor.readingStream.listen((r) {
      if (mounted) {
        setState(() {
          _livePressure        = r.pressureBar;
          _liveTemperature     = r.temperatureCelsius;
          _liveRawPressure     = r.rawPressureBar;
          _liveRawTemperature  = r.rawTemperatureCelsius;
        });
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    _tabController.dispose();
    _pressureRefCtrl.dispose();
    _temperatureRefCtrl.dispose();
    _refDeviceCtrl.dispose();
    _operatorCtrl.dispose();
    super.dispose();
  }

  // ── Add calibration point ───────────────────────────────────────────────────

  void _addPressurePoint() {
    final ref = double.tryParse(_pressureRefCtrl.text.replaceAll(',', '.'));
    final raw = _liveRawPressure ?? _livePressure;
    if (ref == null || raw == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _pressurePoints.add(_CalPoint(raw: raw, reference: ref));
      _pressureRefCtrl.clear();
    });
  }

  void _addTemperaturePoint() {
    final ref =
        double.tryParse(_temperatureRefCtrl.text.replaceAll(',', '.'));
    final raw = _liveRawTemperature ?? _liveTemperature;
    if (ref == null || raw == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _temperaturePoints.add(_CalPoint(raw: raw, reference: ref));
      _temperatureRefCtrl.clear();
    });
  }

  // ── Zero-point helpers ──────────────────────────────────────────────────────

  void _addPressureZero() {
    final raw = _liveRawPressure ?? _livePressure;
    if (raw == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _pressurePoints.add(_CalPoint(raw: raw, reference: 0.0));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Zero point added (raw = ${raw.toStringAsFixed(3)} bar → 0.000 bar)'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Save calibration ────────────────────────────────────────────────────────

  Future<void> _savePressureCalibration(_RegressionResult result) async {
    if (_selectedMachineId == null) {
      setState(() => _saveError = 'Select a machine first');
      return;
    }
    setState(() { _isSavingPressure = true; _saveError = null; });
    try {
      final repo = ref.read(sensorCalibrationRepositoryProvider);
      await repo.save(
        machineId:      _selectedMachineId!,
        sensorType:     'pressure',
        slope:          result.slope,
        offset:         result.offset,
        referenceDevice: _refDeviceCtrl.text.trim().isEmpty
            ? 'External manometer'
            : _refDeviceCtrl.text.trim(),
        calibratedBy:   _operatorCtrl.text.trim(),
        notes: 'Points: ${_pressurePoints.length}  '
               'R²=${result.rSquared.toStringAsFixed(4)}  '
               'RMSE=${result.rmse.toStringAsFixed(4)}',
      );
      // Apply immediately to sensor service
      final cal = ref.read(sensorServiceProvider).currentCalibration;
      ref.read(sensorServiceProvider).applyCalibration(
        pressureSlope:     result.slope,
        pressureOffset:    result.offset,
        temperatureSlope:  cal.temperatureSlope,
        temperatureOffset: cal.temperatureOffset,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Pressure calibration saved and applied'),
          ]),
          backgroundColor: Color(0xFF2E7D32),
        ));
        setState(() => _pressurePoints.clear());
      }
    } catch (e) {
      if (mounted) setState(() => _saveError = e.toString());
    } finally {
      if (mounted) setState(() => _isSavingPressure = false);
    }
  }

  Future<void> _saveTemperatureCalibration(_RegressionResult result) async {
    if (_selectedMachineId == null) {
      setState(() => _saveError = 'Select a machine first');
      return;
    }
    setState(() { _isSavingTemperature = true; _saveError = null; });
    try {
      final repo = ref.read(sensorCalibrationRepositoryProvider);
      await repo.save(
        machineId:      _selectedMachineId!,
        sensorType:     'temperature',
        slope:          result.slope,
        offset:         result.offset,
        referenceDevice: _refDeviceCtrl.text.trim().isEmpty
            ? 'External thermometer'
            : _refDeviceCtrl.text.trim(),
        calibratedBy:   _operatorCtrl.text.trim(),
        notes: 'Points: ${_temperaturePoints.length}  '
               'R²=${result.rSquared.toStringAsFixed(4)}  '
               'RMSE=${result.rmse.toStringAsFixed(4)}',
      );
      final cal = ref.read(sensorServiceProvider).currentCalibration;
      ref.read(sensorServiceProvider).applyCalibration(
        pressureSlope:     cal.pressureSlope,
        pressureOffset:    cal.pressureOffset,
        temperatureSlope:  result.slope,
        temperatureOffset: result.offset,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Temperature calibration saved and applied'),
          ]),
          backgroundColor: Color(0xFF2E7D32),
        ));
        setState(() => _temperaturePoints.clear());
      }
    } catch (e) {
      if (mounted) setState(() => _saveError = e.toString());
    } finally {
      if (mounted) setState(() => _isSavingTemperature = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db    = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor Calibration'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.compress), text: 'Pressure'),
            Tab(icon: Icon(Icons.thermostat), text: 'Temperature'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Sensor status strip ──────────────────────────────────────────
          _SensorStatusStrip(state: _sensorState),

          // ── Machine selector + metadata ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                StreamBuilder<List<MachineRecord>>(
                  stream: db.machinesDao.watchAll(),
                  builder: (ctx, snap) {
                    final machines = snap.data ?? [];
                    return DropdownButtonFormField<String>(
                      value: _selectedMachineId,
                      decoration: const InputDecoration(
                        labelText: 'Machine being calibrated',
                        prefixIcon: Icon(Icons.settings),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'standalone',
                          child: Text('Standalone sensor (no machine)'),
                        ),
                        ...machines.map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(
                                '${m.manufacturer} ${m.model} · ${m.serialNumber}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedMachineId = v),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _refDeviceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Reference instrument',
                          hintText: 'e.g. Wika CPG1500',
                          isDense: true,
                          prefixIcon: Icon(Icons.device_hub, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _operatorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Calibrated by',
                          hintText: 'Operator name',
                          isDense: true,
                          prefixIcon: Icon(Icons.person, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_saveError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_saveError!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ),

          // ── Tabs ─────────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CalibrationTab(
                  sensorType:       'pressure',
                  unit:             'bar',
                  liveRaw:          _liveRawPressure,
                  liveCal:          _livePressure,
                  points:           _pressurePoints,
                  refController:    _pressureRefCtrl,
                  isSensorConnected: _sensorState == SensorConnectionState.connected,
                  onAddPoint:       _addPressurePoint,
                  onAddZero:        _addPressureZero,
                  onRemovePoint:    (i) => setState(() => _pressurePoints.removeAt(i)),
                  onSave:           _savePressureCalibration,
                  isSaving:         _isSavingPressure,
                  hintText:         'Read on manometer [bar]',
                  zeroLabel:        'Mark atmospheric (0 bar)',
                ),
                _CalibrationTab(
                  sensorType:       'temperature',
                  unit:             '°C',
                  liveRaw:          _liveRawTemperature,
                  liveCal:          _liveTemperature,
                  points:           _temperaturePoints,
                  refController:    _temperatureRefCtrl,
                  isSensorConnected: _sensorState == SensorConnectionState.connected,
                  onAddPoint:       _addTemperaturePoint,
                  onAddZero:        null,
                  onRemovePoint:    (i) =>
                      setState(() => _temperaturePoints.removeAt(i)),
                  onSave:           _saveTemperatureCalibration,
                  isSaving:         _isSavingTemperature,
                  hintText:         'Read on thermometer [°C]',
                  zeroLabel:        '',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Calibration tab ───────────────────────────────────────────────────────────

class _CalibrationTab extends StatelessWidget {
  const _CalibrationTab({
    required this.sensorType,
    required this.unit,
    required this.liveRaw,
    required this.liveCal,
    required this.points,
    required this.refController,
    required this.isSensorConnected,
    required this.onAddPoint,
    required this.onAddZero,
    required this.onRemovePoint,
    required this.onSave,
    required this.isSaving,
    required this.hintText,
    required this.zeroLabel,
  });

  final String sensorType;
  final String unit;
  final double? liveRaw;
  final double? liveCal;
  final List<_CalPoint> points;
  final TextEditingController refController;
  final bool isSensorConnected;
  final VoidCallback onAddPoint;
  final VoidCallback? onAddZero;
  final ValueChanged<int> onRemovePoint;
  final Future<void> Function(_RegressionResult) onSave;
  final bool isSaving;
  final String hintText;
  final String zeroLabel;

  static const _pressureColor    = Color(0xFF1565C0);
  static const _temperatureColor = Color(0xFFB71C1C);

  @override
  Widget build(BuildContext context) {
    final color  = sensorType == 'pressure' ? _pressureColor : _temperatureColor;
    final result = _RegressionResult.compute(points);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // ── Live reading card ──────────────────────────────────────────
          _LiveReadingCard(
            color:    color,
            raw:      liveRaw,
            cal:      liveCal,
            unit:     unit,
            connected: isSensorConnected,
          ),
          const SizedBox(height: 16),

          // ── Add point section ──────────────────────────────────────────
          _SectionHeader(title: 'Adicionar ponto de calibração', color: color),
          const SizedBox(height: 8),

          if (!isSensorConnected)
            _InfoBanner(
              message: 'Connect the sensor to add calibration points.',
              color: Colors.orange,
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: refController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^-?\d{0,5}(\.\d{0,3})?')),
                    ],
                    decoration: InputDecoration(
                      labelText: hintText,
                      suffixText: unit,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Point'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: onAddPoint,
                ),
              ],
            ),
            if (onAddZero != null && zeroLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.exposure_zero),
                label: Text(zeroLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  minimumSize: const Size(0, 44),
                ),
                onPressed: onAddZero,
              ),
            ],
          ],

          const SizedBox(height: 16),

          // ── Calibration points table ───────────────────────────────────
          _SectionHeader(title: 'Pontos coletados (${points.length})', color: color),
          const SizedBox(height: 4),

          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No points yet. Add at least 1 to compute calibration.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  // Header row
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const SizedBox(width: 28),
                        _ColHeader('Point #'),
                        _ColHeader('Sensor ($unit)'),
                        _ColHeader('Reference ($unit)'),
                        _ColHeader('Error ($unit)'),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...points.asMap().entries.map((e) {
                    final idx = e.key;
                    final pt  = e.value;
                    final predicted = result != null
                        ? pt.raw * result.slope + result.offset
                        : null;
                    final error = predicted != null
                        ? pt.reference - predicted
                        : null;
                    return _PointRow(
                      index:     idx + 1,
                      raw:       pt.raw,
                      reference: pt.reference,
                      error:     error,
                      unit:      unit,
                      onDelete:  () => onRemovePoint(idx),
                    );
                  }),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // ── Regression result ──────────────────────────────────────────
          if (result != null) ...[
            _SectionHeader(title: 'Resultado da calibração', color: color),
            const SizedBox(height: 8),
            _RegressionCard(result: result, color: color, unit: unit),
            const SizedBox(height: 16),

            // ── Save button ────────────────────────────────────────────
            ElevatedButton.icon(
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(isSaving
                  ? 'Saving…'
                  : 'Apply & Save Calibration'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _qualityColor(result),
                minimumSize: const Size(double.infinity, 52),
              ),
              onPressed: isSaving ? null : () => onSave(result),
            ),

            if (result.rSquared < 0.99 && points.length >= 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'R² < 0.99 — consider adding more points or checking '
                  'sensor/reference agreement.',
                  style: TextStyle(
                      color: Colors.orange.shade800, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Color _qualityColor(_RegressionResult r) {
    if (r.rSquared >= 0.999) return const Color(0xFF2E7D32);
    if (r.rSquared >= 0.99)  return const Color(0xFF1565C0);
    return Colors.orange.shade700;
  }
}

// ── Regression result card ────────────────────────────────────────────────────

class _RegressionCard extends StatelessWidget {
  const _RegressionCard({
    required this.result,
    required this.color,
    required this.unit,
  });

  final _RegressionResult result;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final r2pct = (result.rSquared * 100).toStringAsFixed(3);
    final qualityLabel = result.rSquared >= 0.999
        ? 'Excellent'
        : result.rSquared >= 0.99
            ? 'Good'
            : 'Poor — add more points';
    final qualityColor = result.rSquared >= 0.999
        ? const Color(0xFF2E7D32)
        : result.rSquared >= 0.99
            ? const Color(0xFF1565C0)
            : Colors.orange.shade700;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Formula
          Text(
            'corrected = raw × ${result.slope.toStringAsFixed(6)}'
            ' + (${result.offset >= 0 ? '+' : ''}${result.offset.toStringAsFixed(6)})',
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          // Stats row
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _StatChip(label: 'Slope', value: result.slope.toStringAsFixed(6)),
              _StatChip(label: 'Offset', value: '${result.offset.toStringAsFixed(4)} $unit'),
              _StatChip(label: 'R²', value: '$r2pct %'),
              _StatChip(
                  label: 'RMSE', value: '${result.rmse.toStringAsFixed(4)} $unit'),
              _StatChip(
                label: 'Quality',
                value: qualityLabel,
                valueColor: qualityColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _LiveReadingCard extends StatelessWidget {
  const _LiveReadingCard({
    required this.color,
    required this.raw,
    required this.cal,
    required this.unit,
    required this.connected,
  });

  final Color color;
  final double? raw;
  final double? cal;
  final String unit;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final rawStr = raw != null ? '${raw!.toStringAsFixed(4)} $unit' : '— $unit';
    final calStr = cal != null ? '${cal!.toStringAsFixed(4)} $unit' : '— $unit';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.sensors : Icons.sensors_off,
            color: connected ? color : Colors.grey,
            size: 36,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Live reading',
                    style: TextStyle(
                        fontSize: 11,
                        color: color.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(calStr,
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Raw (uncal.)',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade500)),
              const SizedBox(height: 2),
              Text(rawStr,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SensorStatusStrip extends StatelessWidget {
  const _SensorStatusStrip({required this.state});
  final SensorConnectionState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      SensorConnectionState.connected    => ('Sensor connected', const Color(0xFF2E7D32)),
      SensorConnectionState.scanning     => ('Scanning…', Colors.orange),
      SensorConnectionState.connecting   => ('Connecting…', Colors.orange),
      SensorConnectionState.error        => ('Sensor error', Colors.red),
      SensorConnectionState.disconnected => ('Sensor not connected — readings will not update', Colors.grey),
    };
    return Container(
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Icon(Icons.bluetooth, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.color});
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.4)),
          const SizedBox(height: 4),
          Divider(height: 1, color: color.withValues(alpha: 0.25)),
        ],
      );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message, required this.color});
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(fontSize: 12, color: color))),
        ]),
      );
}

class _PointRow extends StatelessWidget {
  const _PointRow({
    required this.index,
    required this.raw,
    required this.reference,
    required this.error,
    required this.unit,
    required this.onDelete,
  });

  final int index;
  final double raw;
  final double reference;
  final double? error;
  final String unit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final errorColor = error == null
        ? Colors.transparent
        : error!.abs() < 0.01
            ? const Color(0xFF2E7D32)
            : error!.abs() < 0.05
                ? Colors.orange
                : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: Colors.red,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onDelete,
          ),
          _ColVal('$index', bold: true),
          _ColVal(raw.toStringAsFixed(4)),
          _ColVal(reference.toStringAsFixed(4)),
          _ColVal(
            error != null
                ? '${error! >= 0 ? '+' : ''}${error!.toStringAsFixed(4)}'
                : '—',
            color: errorColor,
          ),
        ],
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey),
            textAlign: TextAlign.center),
      );
}

class _ColVal extends StatelessWidget {
  const _ColVal(this.text, {this.bold = false, this.color});
  final String text;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                fontFamily: 'monospace',
                color: color),
            textAlign: TextAlign.center),
      );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: valueColor)),
        ],
      );
}
