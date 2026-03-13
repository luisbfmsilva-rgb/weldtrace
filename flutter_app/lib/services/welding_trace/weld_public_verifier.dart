import 'dart:convert';

import 'weld_certificate.dart';
import 'weld_registry.dart';

/// Thrown by [WeldPublicVerifier.decodeQrPayload] when the QR JSON string
/// is not a valid WeldTrace verification payload.
class WeldPublicVerifierException implements Exception {
  const WeldPublicVerifierException(this.message);

  final String message;

  @override
  String toString() => 'WeldPublicVerifierException: $message';
}

/// Decoded fields extracted from a WeldTrace QR payload.
///
/// Returned by [WeldPublicVerifier.decodeQrPayload].
class QrPayloadResult {
  const QrPayloadResult({
    required this.jointId,
    required this.signature,
  });

  /// Globally-unique joint identifier (UUID v7).
  final String jointId;

  /// SHA-256 weld signature (64-char hex).
  final String signature;

  @override
  String toString() =>
      'QrPayloadResult(jointId: $jointId, signature: $signature)';
}

/// Public verification utilities for WeldTrace weld joints.
///
/// Four independent entry points are provided:
///
/// 1. **[verifyJoint]** — in-memory check against a pre-loaded
///    [List<WeldRegistryEntry>].  Fast; no I/O.
///
/// 2. **[decodeQrPayload]** — parses and validates a QR code JSON string,
///    returning the extracted [QrPayloadResult].  Throws
///    [WeldPublicVerifierException] when the payload is invalid.
///
/// 3. **[findRegistryEntry]** — looks up a joint ID in
///    `registry_export.json` on disk.  Delegates to [WeldRegistry].
///
/// 4. **[verifyCertificate]** — validates a [WeldCertificate] by
///    checking the registry entry, signature format, and optional PDF hash
///    format.
///
/// Typical end-to-end scanner flow:
/// ```dart
/// // 1. Scan QR code
/// final result = WeldPublicVerifier.decodeQrPayload(rawJson);
///
/// // 2. Load registry
/// final entries = await WeldRegistry.exportRegistry();
///
/// // 3. Verify
/// final valid = WeldPublicVerifier.verifyJoint(
///   jointId:   result.jointId,
///   signature: result.signature,
///   registry:  entries,
/// );
/// ```
class WeldPublicVerifier {
  WeldPublicVerifier._();

  // ── verifyJoint ─────────────────────────────────────────────────────────────

  /// Returns `true` when [registry] contains an entry whose [jointId] and
  /// [signature] both match the provided values.
  ///
  /// Both fields must match simultaneously — a [jointId] found under a
  /// different [signature] returns `false`.
  ///
  /// This is a pure in-memory operation with no I/O.
  static bool verifyJoint({
    required String jointId,
    required String signature,
    required List<WeldRegistryEntry> registry,
  }) =>
      registry.any(
        (e) => e.jointId == jointId && e.signature == signature,
      );

  // ── decodeQrPayload ─────────────────────────────────────────────────────────

  /// Parses and validates a WeldTrace QR payload JSON string.
  ///
  /// Expected structure:
  /// ```json
  /// {
  ///   "app":    "WeldTrace",
  ///   "joint":  "<UUID-v7>",
  ///   "sig":    "<64-char SHA-256 hex>",
  ///   "v":      1,
  ///   "verify": "registry"
  /// }
  /// ```
  ///
  /// Returns a [QrPayloadResult] with the extracted [jointId] and
  /// [signature] when all validation rules pass.
  ///
  /// Throws [WeldPublicVerifierException] when:
  /// - [json] is not valid JSON.
  /// - The decoded value is not a JSON object.
  /// - `app != "WeldTrace"`.
  /// - `v != 1`.
  /// - `joint` or `sig` fields are absent or non-string.
  static QrPayloadResult decodeQrPayload(String json) {
    dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw const WeldPublicVerifierException('Payload is not valid JSON');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const WeldPublicVerifierException(
          'Payload must be a JSON object');
    }

    if (decoded['app'] != 'WeldTrace') {
      throw WeldPublicVerifierException(
          'Unknown app identifier: ${decoded['app']}');
    }

    if (decoded['v'] != 1) {
      throw WeldPublicVerifierException(
          'Unsupported payload version: ${decoded['v']}');
    }

    final jointId   = decoded['joint'];
    final signature = decoded['sig'];

    if (jointId is! String || jointId.isEmpty) {
      throw const WeldPublicVerifierException(
          'Missing or empty "joint" field');
    }
    if (signature is! String || signature.isEmpty) {
      throw const WeldPublicVerifierException(
          'Missing or empty "sig" field');
    }

    return QrPayloadResult(jointId: jointId, signature: signature);
  }

  // ── findRegistryEntry ───────────────────────────────────────────────────────

  /// Looks up [jointId] in `registry_export.json` and returns the matching
  /// [WeldRegistryEntry], or `null` when not found.
  ///
  /// Pass [registryPath] to override the default production file location
  /// (useful in tests and CLI scripts that supply an explicit path).
  static Future<WeldRegistryEntry?> findRegistryEntry({
    required String jointId,
    String? registryPath,
  }) =>
      WeldRegistry.findByJointId(jointId, registryPath: registryPath);

  // ── verifyCertificate ────────────────────────────────────────────────────────

  /// Validates a [WeldCertificate] through three independent checks:
  ///
  /// 1. **Registry entry check** — confirms the registry contains an entry
  ///    matching both [WeldCertificate.jointId] and
  ///    [WeldCertificate.signature].  Supply a pre-loaded [registry] list for
  ///    an in-memory check (no I/O), or pass [registryPath] to read from disk.
  ///    When both are `null` the default production registry file is used.
  ///
  /// 2. **Signature format check** — verifies that
  ///    [WeldCertificate.signature] is exactly 64 lowercase hex characters
  ///    (a valid SHA-256 digest).
  ///
  /// 3. **PDF hash format check** — when [WeldCertificate.pdfHash] is
  ///    non-null, verifies that it is also exactly 64 lowercase hex
  ///    characters.
  ///
  /// Returns `true` only when all applicable checks pass.
  ///
  /// ```dart
  /// final ok = await WeldPublicVerifier.verifyCertificate(
  ///   cert,
  ///   registry: await WeldRegistry.exportRegistry(),
  /// );
  /// ```
  static Future<bool> verifyCertificate(
    WeldCertificate cert, {
    List<WeldRegistryEntry>? registry,
    String? registryPath,
  }) async {
    // ── 1. Registry entry check ──────────────────────────────────────────────
    final bool registryOk;
    if (registry != null) {
      registryOk = verifyJoint(
        jointId:   cert.jointId,
        signature: cert.signature,
        registry:  registry,
      );
    } else {
      registryOk = await WeldRegistry.verifyFromRegistry(
        jointId:      cert.jointId,
        signature:    cert.signature,
        registryPath: registryPath,
      );
    }
    if (!registryOk) return false;

    // ── 2. Signature format check (64 hex chars) ─────────────────────────────
    final sigPattern = RegExp(r'^[0-9a-fA-F]{64}$');
    if (!sigPattern.hasMatch(cert.signature)) return false;

    // ── 3. PDF hash format check (64 hex chars, when present) ────────────────
    if (cert.pdfHash != null && !sigPattern.hasMatch(cert.pdfHash!)) {
      return false;
    }

    return true;
  }
}
