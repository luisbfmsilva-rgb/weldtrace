import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/database/app_database.dart';

/// Provides access to sensor calibration records stored in SQLite.
///
/// Convention for [sensorSerial]:
///   'pressure'    → hydraulic pressure transducer calibration
///   'temperature' → PT100 temperature sensor calibration
///
/// One active row per (machineId, sensorSerial).
/// Older rows are kept for audit history.
class SensorCalibrationRepository {
  const SensorCalibrationRepository({required this.db});

  final AppDatabase db;

  // ── Fetch latest calibration ────────────────────────────────────────────────

  Future<SensorCalibrationRecord?> getLatest({
    required String machineId,
    required String sensorType, // 'pressure' | 'temperature'
  }) async {
    final rows = await (db.select(db.sensorCalibrationsTable)
          ..where((t) =>
              t.machineId.equals(machineId) & t.sensorSerial.equals(sensorType))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<SensorCalibrationRecord>> getAll({
    required String machineId,
    required String sensorType,
  }) =>
      (db.select(db.sensorCalibrationsTable)
            ..where((t) =>
                t.machineId.equals(machineId) &
                t.sensorSerial.equals(sensorType))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  // ── Save calibration ────────────────────────────────────────────────────────

  Future<void> save({
    required String machineId,
    required String sensorType, // 'pressure' | 'temperature'
    required double slope,
    required double offset,
    required String referenceDevice,
    required String calibratedBy,
    String certificate = '',
    String? notes,
  }) async {
    final now = DateTime.now();
    final today = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    await db.into(db.sensorCalibrationsTable).insert(
          SensorCalibrationsTableCompanion.insert(
            id: const Uuid().v4(),
            machineId: machineId,
            sensorSerial: sensorType,
            calibrationDate: today,
            referenceDevice: referenceDevice,
            referenceCertificate: certificate,
            offsetValue: Value(offset),
            slopeValue: Value(slope),
            notes: Value(notes),
            calibratedBy: Value(calibratedBy),
            createdAt: Value(now),
            updatedAt: Value(now),
            syncStatus: const Value('pending'),
          ),
        );
  }

  // ── Combined load for SensorService ────────────────────────────────────────

  /// Loads the latest calibration for both sensors of [machineId].
  /// Returns null for any sensor type that has no stored calibration (→ defaults).
  Future<({SensorCalibrationRecord? pressure, SensorCalibrationRecord? temperature})>
      loadForMachine(String machineId) async {
    final p = await getLatest(machineId: machineId, sensorType: 'pressure');
    final t = await getLatest(machineId: machineId, sensorType: 'temperature');
    return (pressure: p, temperature: t);
  }
}
