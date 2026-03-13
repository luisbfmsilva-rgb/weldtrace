import 'dart:convert';

import 'weld_trace_recorder.dart';
import 'weld_trace_signature.dart';

/// Provides weld verification utilities: signature recomputation and QR
/// payload generation.
///
/// The QR code embedded in every PDF report encodes a [buildVerificationPayload]
/// JSON object.  A field inspector can scan the code, recompute the signature,
/// and compare it to [WeldVerifier.verifySignature] to confirm authenticity.
class WeldVerifier {
  WeldVerifier._();

  // ── Signature verification ─────────────────────────────────────────────────

  /// Recomputes the SHA-256 signature from the raw weld inputs and compares
  /// it to [signature].
  ///
  /// Returns `true` only when every field and every curve sample match exactly.
  ///
  /// Parameters mirror [WeldTraceSignature.generate] exactly so that the same
  /// deterministic payload is produced.
  static bool verifySignature({
    required String signature,
    required String machineId,
    required double diameter,
    required String material,
    required String sdr,
    required List<WeldTracePoint> curve,
    required DateTime timestamp,
    double fusionPressureBar = 0.0,
    double heatingTimeSec    = 0.0,
    double coolingTimeSec    = 0.0,
    double beadHeightMm      = 0.0,
  }) {
    return WeldTraceSignature.verify(
      signature:         signature,
      machineId:         machineId,
      pipeDiameter:      diameter,
      material:          material,
      sdr:               sdr,
      curve:             curve,
      timestamp:         timestamp,
      fusionPressureBar: fusionPressureBar,
      heatingTimeSec:    heatingTimeSec,
      coolingTimeSec:    coolingTimeSec,
      beadHeightMm:      beadHeightMm,
    );
  }

  // ── QR verification payload ────────────────────────────────────────────────

  /// Builds the JSON string that is encoded into the QR code on every PDF.
  ///
  /// Structure:
  /// ```json
  /// {
  ///   "app":       "WeldTrace",
  ///   "version":   1,
  ///   "signature": "<64-char SHA-256 hex>",
  ///   "machine":   "<machineId>",
  ///   "diameter":  160.0,
  ///   "material":  "PE100",
  ///   "sdr":       "11",
  ///   "timestamp": "2025-06-15T08:30:00.000Z"
  /// }
  /// ```
  ///
  /// The payload is designed to be compact enough for a QR code at error
  /// correction level M (≈ 260 byte capacity).
  static String buildVerificationPayload({
    required String signature,
    required String machineId,
    required double diameter,
    required String material,
    required String sdr,
    required DateTime timestamp,
  }) {
    return jsonEncode({
      'app':       'WeldTrace',
      'version':   1,
      'signature': signature,
      'machine':   machineId,
      'diameter':  diameter,
      'material':  material,
      'sdr':       sdr,
      'timestamp': timestamp.toUtc().toIso8601String(),
    });
  }

  /// Parses and validates a QR payload JSON string.
  ///
  /// Returns a [Map] with all fields when the payload is a valid WeldTrace
  /// verification object (has `app == 'WeldTrace'` and `version == 1`).
  /// Returns `null` when the string is invalid JSON or is not a WeldTrace
  /// payload.
  static Map<String, dynamic>? parsePayload(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['app'] != 'WeldTrace') return null;
      if (decoded['version'] != 1) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}
