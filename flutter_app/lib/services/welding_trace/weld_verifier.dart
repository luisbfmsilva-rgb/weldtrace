import 'dart:convert';

import 'weld_trace_recorder.dart';
import 'weld_trace_signature.dart';

/// Provides weld verification utilities: signature recomputation and
/// optimised QR payload generation.
///
/// The QR code embedded in every PDF report encodes a compact
/// [buildVerificationPayload] JSON object (< 200 characters).  A field
/// inspector can scan the code, extract the joint ID and signature, then
/// call [verifySignature] to confirm authenticity.
class WeldVerifier {
  WeldVerifier._();

  // ── Signature verification ─────────────────────────────────────────────────

  /// Recomputes the SHA-256 signature from the raw weld inputs and compares
  /// it to [signature].
  ///
  /// Returns `true` only when every field and every curve sample match exactly.
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

  /// Builds the optimised QR payload JSON string (< 200 characters).
  ///
  /// Structure:
  /// ```json
  /// {
  ///   "app":   "WeldTrace",
  ///   "joint": "<UUID-v7 joint ID>",
  ///   "sig":   "<64-char SHA-256 hex>",
  ///   "v":     1
  /// }
  /// ```
  ///
  /// Estimated size:
  ///   27 (keys + braces) + 36 (UUID v7) + 64 (SHA-256) + separators ≈ 144 chars.
  ///
  /// This fits comfortably within a QR code at error correction level M
  /// (≈ 260 byte capacity for alphanumeric data).
  static String buildVerificationPayload({
    required String jointId,
    required String signature,
  }) {
    return jsonEncode({
      'app':   'WeldTrace',
      'joint': jointId,
      'sig':   signature,
      'v':     1,
    });
  }

  /// Parses and validates a QR payload JSON string.
  ///
  /// Returns a [Map] with all fields when the payload is a valid WeldTrace
  /// verification object (`app == 'WeldTrace'` and `v == 1`).
  /// Returns `null` for invalid JSON or non-WeldTrace payloads.
  static Map<String, dynamic>? parsePayload(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['app'] != 'WeldTrace') return null;
      if (decoded['v'] != 1) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}
