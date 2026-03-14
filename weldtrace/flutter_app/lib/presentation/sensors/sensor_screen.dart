import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../services/sensor/sensor_service.dart';

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

  @override
  void initState() {
    super.initState();
    final sensor = ref.read(sensorServiceProvider);
    sensor.connectionStateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    sensor.readingStream.listen((r) {
      if (mounted) {
        setState(() {
          _pressure = r.pressureBar;
          _temperature = r.temperatureCelsius;
        });
      }
    });
  }

  Future<void> _connect() async {
    setState(() => _error = null);
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
    final theme = Theme.of(context);
    final isConnected = _state == SensorConnectionState.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('BLE Sensor')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status indicator
            _ConnectionStatusCard(state: _state),
            const SizedBox(height: 24),

            // Live readings
            if (isConnected) ...[
              Row(
                children: [
                  Expanded(
                    child: _LiveReading(
                      label: 'Pressure',
                      value: _pressure != null
                          ? '${_pressure!.toStringAsFixed(3)} bar'
                          : '—',
                      unit: 'bar',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _LiveReading(
                      label: 'Temperature',
                      value: _temperature != null
                          ? '${_temperature!.toStringAsFixed(2)} °C'
                          : '—',
                      unit: '°C',
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Error
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style:
                        TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),

            // Connect / Disconnect
            if (!isConnected)
              ElevatedButton.icon(
                icon: const Icon(Icons.bluetooth_searching),
                label: _state == SensorConnectionState.scanning ||
                        _state == SensorConnectionState.connecting
                    ? const Text('Connecting…')
                    : const Text('Connect to Sensor'),
                onPressed: _state == SensorConnectionState.scanning ||
                        _state == SensorConnectionState.connecting
                    ? null
                    : _connect,
              )
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.bluetooth_disabled),
                label: const Text('Disconnect'),
                onPressed: _disconnect,
              ),

            const SizedBox(height: 16),
            Text(
              'The WeldTrace sensor kit connects via Bluetooth to this tablet. '
              'Ensure the sensor is powered on and within 5 metres.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({required this.state});
  final SensorConnectionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = switch (state) {
      SensorConnectionState.connected => ('Connected', const Color(0xFF2E7D32), Icons.bluetooth_connected),
      SensorConnectionState.scanning => ('Scanning…', Colors.orange, Icons.bluetooth_searching),
      SensorConnectionState.connecting => ('Connecting…', Colors.orange, Icons.bluetooth_searching),
      SensorConnectionState.error => ('Connection Error', theme.colorScheme.error, Icons.bluetooth_disabled),
      SensorConnectionState.disconnected => ('Not Connected', theme.colorScheme.outline, Icons.bluetooth_disabled),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sensor Status',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: color.withOpacity(0.7))),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 18)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveReading extends StatelessWidget {
  const _LiveReading({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 24, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
