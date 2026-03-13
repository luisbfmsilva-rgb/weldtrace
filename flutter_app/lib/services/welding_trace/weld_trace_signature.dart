import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'weld_trace_recorder.dart';

/// Generates a cryptographic fingerprint (SHA-256) that uniquely identifies
/// a completed weld.
///
/// The hash covers:
///   • machine ID
///   • pipe outer diameter
///   • material code
///   • SDR rating
///   • the full pressure × time curve (sorted by timeSeconds, serialised as
///     structured JSON to guarantee ordering-independent determinism)
///   • the ISO-8601 timestamp of the weld
///   • welding process parameters (fusion pressure, heating time, cooling
///     time, bead height) when provided
///
/// This fingerprint is stored alongside the weld record and included in the
/// PDF report.  Any tampering with a single curve sample — or with any
/// process parameter — will produce a completely different hash.
class WeldTraceSignature {
  WeldTraceSignature._();

  /// Generates and returns the SHA-256 hex digest for a weld.
  ///
  /// [machineId]          — unique identifier of the fusion machine
  /// [pipeDiameter]       — pipe outer diameter [mm]
  /// [material]           — pipe material code (e.g. 'PE100', 'PP')
  /// [sdr]                — SDR rating string (e.g. '11', 'SDR17.6')
  /// [curve]              — pressure × time samples recorded during the weld;
  ///                        sorted by [WeldTracePoint.timeSeconds] before
  ///                        serialisation to ensure determinism regardless of
  ///                        insertion order
  /// [timestamp]          — weld completion timestamp
  /// [fusionPressureBar]  — nominal fusion pressure [bar] (0 when unknown)
  /// [heatingTimeSec]     — nominal heating time [s]      (0 when unknown)
  /// [coolingTimeSec]     — nominal cooling time [s]      (0 when unknown)
  /// [beadHeightMm]       — bead height measured post-weld [mm] (0 when N/A)
  ///
  /// Returns a 64-character lowercase hex string.
  static String generate({
    required String machineId,
    required double pipeDiameter,
    required String material,
    required String sdr,
    required List<WeldTracePoint> curve,
    required DateTime timestamp,
    double fusionPressureBar = 0.0,
    double heatingTimeSec    = 0.0,
    double coolingTimeSec    = 0.0,
    double beadHeightMm      = 0.0,
  }) {
    // 1. Sort curve by timeSeconds — ensures the same hash regardless of
    //    insertion order or late-arriving BLE packets.
    final sortedCurve = List<WeldTracePoint>.from(curve)
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    // 2. Build a structured JSON payload — all fields are explicitly keyed so
    //    the serialisation is stable and tamper-evident.
    final payload = jsonEncode({
      'machineId':        machineId,
      'diameter':         pipeDiameter,
      'material':         material,
      'sdr':              sdr,
      'timestamp':        timestamp.toIso8601String(),
      // ── Extended welding parameters ───────────────────────────────────────
      'fusionPressureBar': fusionPressureBar,
      'heatingTimeSec':    heatingTimeSec,
      'coolingTimeSec':    coolingTimeSec,
      'beadHeightMm':      beadHeightMm,
      // ── Curve (sorted) ────────────────────────────────────────────────────
      'curve': sortedCurve.map((p) => p.toJson()).toList(),
    });

    // 3. Compute SHA-256 over the UTF-8 encoded payload.
    final digest = sha256.convert(utf8.encode(payload));
    return digest.toString();
  }

  /// Verifies that [signature] matches the hash computed from the supplied
  /// inputs.
  ///
  /// Returns true only when the recomputed hash equals [signature] exactly.
  static bool verify({
    required String signature,
    required String machineId,
    required double pipeDiameter,
    required String material,
    required String sdr,
    required List<WeldTracePoint> curve,
    required DateTime timestamp,
    double fusionPressureBar = 0.0,
    double heatingTimeSec    = 0.0,
    double coolingTimeSec    = 0.0,
    double beadHeightMm      = 0.0,
  }) {
    final expected = generate(
      machineId:          machineId,
      pipeDiameter:       pipeDiameter,
      material:           material,
      sdr:                sdr,
      curve:              curve,
      timestamp:          timestamp,
      fusionPressureBar:  fusionPressureBar,
      heatingTimeSec:     heatingTimeSec,
      coolingTimeSec:     coolingTimeSec,
      beadHeightMm:       beadHeightMm,
    );
    return expected == signature;
  }
}
