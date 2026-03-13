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
///   • the full pressure × time curve (serialised as JSON)
///   • the ISO-8601 timestamp of the weld
///
/// This fingerprint is stored alongside the weld record and included in the
/// PDF report.  Any tampering with a single curve sample will produce a
/// completely different hash, making falsification detectable.
class WeldTraceSignature {
  WeldTraceSignature._();

  /// Generates and returns the SHA-256 hex digest for a weld.
  ///
  /// [machineId]     — unique identifier of the fusion machine
  /// [pipeDiameter]  — pipe outer diameter [mm]
  /// [material]      — pipe material code (e.g. 'PE100', 'PP')
  /// [sdr]           — SDR rating string (e.g. '11', 'SDR17.6')
  /// [curve]         — pressure × time samples recorded during the weld
  /// [timestamp]     — weld completion timestamp (usually [DateTime.now()])
  ///
  /// Returns a 64-character lowercase hex string.
  ///
  /// Passing an empty [curve] is handled gracefully — the digest will still
  /// be deterministic for the same inputs.
  static String generate({
    required String machineId,
    required double pipeDiameter,
    required String material,
    required String sdr,
    required List<WeldTracePoint> curve,
    required DateTime timestamp,
  }) {
    // 1. Serialise curve to a stable JSON representation.
    final curveJson = jsonEncode(
      curve.map((p) => p.toJson()).toList(),
    );

    // 2. Concatenate all fields into a single payload string.
    //    The order and delimiters are fixed — any change alters the hash.
    final payload = [
      machineId,
      pipeDiameter.toStringAsFixed(4),
      material,
      sdr,
      curveJson,
      timestamp.toIso8601String(),
    ].join('|');

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
  }) {
    final expected = generate(
      machineId:     machineId,
      pipeDiameter:  pipeDiameter,
      material:      material,
      sdr:           sdr,
      curve:         curve,
      timestamp:     timestamp,
    );
    return expected == signature;
  }
}
