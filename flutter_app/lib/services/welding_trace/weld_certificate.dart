import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'weld_registry.dart';

// ── CertSyncStatus ─────────────────────────────────────────────────────────────

/// String constants for the [WeldCertificate.syncStatus] field.
///
/// | Value     | Meaning                                          |
/// |-----------|--------------------------------------------------|
/// | `pending` | Certificate generated; not yet uploaded to cloud.|
/// | `synced`  | Successfully uploaded and acknowledged.          |
/// | `offline` | Upload not attempted (sync disabled / no network)|
abstract final class CertSyncStatus {
  /// Certificate generated locally; upload has not been attempted.
  static const String pending = 'pending';

  /// Certificate successfully uploaded and acknowledged by the remote API.
  static const String synced  = 'synced';

  /// Sync is disabled or no network is available; upload was skipped.
  static const String offline = 'offline';
}

// ── WeldCertificate ───────────────────────────────────────────────────────────

/// A portable, versioned weld certificate.
///
/// A [WeldCertificate] captures every field needed to independently prove
/// that a weld was performed correctly and has not been tampered with:
///
/// - **Schema** — [schemaType] / [schemaVersion] identify the certificate
///   format for long-term verification tools.
/// - **Version** — [version] carries the short format identifier
///   (`"WeldTrace-CERT-1"`).
/// - Identity: [jointId] (UUID v7), [signature] (SHA-256 hex)
/// - Pipe metadata: [diameter], [material], [sdr]
/// - Equipment: [machineId]
/// - Timing: [timestamp] (UTC)
/// - Quality: [traceQuality]
/// - Process parameters (optional): [fusionPressure], [heatingTime],
///   [coolingTime], [beadHeight]
/// - PDF integrity: [pdfHash] (SHA-256 of the PDF bytes, optional)
/// - Provenance (optional): [software], [softwareVersion]
/// - Sync status (optional, transient): [syncStatus] — not serialised to JSON
///
/// ## JSON key ordering
///
/// [toJson] always emits keys in this canonical order:
///
/// ```
/// schema, version,
/// jointId, signature, timestamp, machineId, diameter, material, sdr,
/// traceQuality, fusionPressure, heatingTime, coolingTime, beadHeight,
/// pdfHash, software, softwareVersion
/// ```
///
/// The `schema` object is always the first key so that any reader can
/// quickly determine the certificate format before processing other fields.
/// Null optional values are included as JSON `null` to keep the schema
/// stable across versions.
///
/// ## Usage
///
/// ```dart
/// final cert = WeldCertificate.generateCertificate(
///   jointId:         jointId,
///   signature:       signature,
///   timestamp:       completedAt,
///   machineId:       machineId,
///   diameter:        160.0,
///   material:        'PE100',
///   sdr:             '11',
///   traceQuality:    'OK',
///   pdfHash:         WeldCertificate.computePdfHash(pdfBytes),
///   software:        'WeldTrace',
///   softwareVersion: '1.0.0',
/// );
///
/// // Export to disk
/// final file = await WeldCertificate.exportCertificate(jointId);
///
/// // Round-trip
/// final restored = WeldCertificate.fromJson(
///     jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
/// ```
class WeldCertificate {
  const WeldCertificate({
    required this.jointId,
    required this.signature,
    required this.timestamp,
    required this.machineId,
    required this.diameter,
    required this.material,
    required this.sdr,
    required this.traceQuality,
    this.schemaType    = _defaultSchemaType,
    this.schemaVersion = _defaultSchemaVersion,
    this.version       = _defaultVersion,
    this.fusionPressure,
    this.heatingTime,
    this.coolingTime,
    this.beadHeight,
    this.pdfHash,
    this.software,
    this.softwareVersion,
    this.syncStatus,
  });

  // ── Schema constants ──────────────────────────────────────────────────────────

  /// Default value for [schemaType].
  static const String _defaultSchemaType    = 'WeldTraceCertificate';

  /// Default value for [schemaVersion].
  static const String _defaultSchemaVersion = '1.0';

  /// Default value for [version].
  static const String _defaultVersion       = 'WeldTrace-CERT-1';

  // ── Schema / versioning fields ────────────────────────────────────────────────

  /// Schema type identifier.  Always `"WeldTraceCertificate"` for v1
  /// certificates.
  final String schemaType;

  /// Schema version.  Always `"1.0"` for v1 certificates.
  final String schemaVersion;

  /// Short certificate format identifier: `"WeldTrace-CERT-1"`.
  ///
  /// Increment when the certificate format changes in a breaking way.
  final String version;

  // ── Required weld fields ──────────────────────────────────────────────────────

  /// Globally-unique joint identifier (UUID v7).
  final String jointId;

  /// SHA-256 weld signature (64-char hex).
  final String signature;

  /// UTC timestamp of weld completion.
  final DateTime timestamp;

  /// Machine identifier.
  final String machineId;

  /// Pipe outer diameter [mm].
  final double diameter;

  /// Pipe material code (e.g. 'PE100', 'PP').
  final String material;

  /// SDR rating (e.g. '11', 'SDR17.6').
  final String sdr;

  /// Trace quality assessment ('OK' or 'LOW_SAMPLE_COUNT').
  final String traceQuality;

  // ── Optional process parameters ───────────────────────────────────────────────

  /// Fusion / butt-fusion pressure [bar].
  final double? fusionPressure;

  /// Heating phase duration [s].
  final double? heatingTime;

  /// Cooling phase duration [s].
  final double? coolingTime;

  /// Bead height measurement [mm].
  final double? beadHeight;

  /// SHA-256 hex digest of the associated PDF report bytes.
  ///
  /// Null when no PDF has been generated or the hash is not yet available.
  final String? pdfHash;

  // ── Optional provenance ───────────────────────────────────────────────────────

  /// Name of the software that generated this certificate (e.g. `"WeldTrace"`).
  final String? software;

  /// Version string of [software] (e.g. `"1.0.0"`).
  final String? softwareVersion;

  // ── Sync status ───────────────────────────────────────────────────────────────

  /// Local synchronisation status for this certificate.
  ///
  /// One of [CertSyncStatus.pending], [CertSyncStatus.synced], or
  /// [CertSyncStatus.offline].
  ///
  /// This field is **transient** — it is NOT included in [toJson] and is
  /// NOT restored by [fromJson].  It tracks runtime upload state only.
  final String? syncStatus;

  // ── Serialisation ────────────────────────────────────────────────────────────

  /// Returns a [Map] with keys in the canonical order specified by the
  /// WeldTrace-CERT-1 schema.
  ///
  /// Key order:
  ///   schema → version → jointId → signature → timestamp → machineId →
  ///   diameter → material → sdr → traceQuality → fusionPressure →
  ///   heatingTime → coolingTime → beadHeight → pdfHash →
  ///   software → softwareVersion
  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': <String, dynamic>{
          'type':    schemaType,
          'version': schemaVersion,
        },
        'version':         version,
        'jointId':         jointId,
        'signature':       signature,
        'timestamp':       timestamp.toUtc().toIso8601String(),
        'machineId':       machineId,
        'diameter':        diameter,
        'material':        material,
        'sdr':             sdr,
        'traceQuality':    traceQuality,
        'fusionPressure':  fusionPressure,
        'heatingTime':     heatingTime,
        'coolingTime':     coolingTime,
        'beadHeight':      beadHeight,
        'pdfHash':         pdfHash,
        'software':        software,
        'softwareVersion': softwareVersion,
      };

  /// Reconstructs a [WeldCertificate] from a [json] map previously produced
  /// by [toJson].
  ///
  /// Missing schema / version / provenance fields fall back to their default
  /// values for backwards compatibility with pre-v1 certificates.
  factory WeldCertificate.fromJson(Map<String, dynamic> json) {
    // ── Schema block (backwards-compatible) ────────────────────────────────────
    final schema        = json['schema'] as Map<String, dynamic>?;
    final schemaType    = schema?['type']    as String? ?? _defaultSchemaType;
    final schemaVersion = schema?['version'] as String? ?? _defaultSchemaVersion;

    return WeldCertificate(
      schemaType:      schemaType,
      schemaVersion:   schemaVersion,
      version:         json['version']       as String?  ?? _defaultVersion,
      jointId:         json['jointId']       as String,
      signature:       json['signature']     as String,
      timestamp:       DateTime.parse(json['timestamp'] as String).toUtc(),
      machineId:       json['machineId']     as String,
      diameter:        (json['diameter']     as num).toDouble(),
      material:        json['material']      as String,
      sdr:             json['sdr']           as String,
      traceQuality:    json['traceQuality']  as String,
      fusionPressure:
          json['fusionPressure'] != null
              ? (json['fusionPressure'] as num).toDouble()
              : null,
      heatingTime:
          json['heatingTime'] != null
              ? (json['heatingTime'] as num).toDouble()
              : null,
      coolingTime:
          json['coolingTime'] != null
              ? (json['coolingTime'] as num).toDouble()
              : null,
      beadHeight:
          json['beadHeight'] != null
              ? (json['beadHeight'] as num).toDouble()
              : null,
      pdfHash:         json['pdfHash']         as String?,
      software:        json['software']        as String?,
      softwareVersion: json['softwareVersion'] as String?,
    );
  }

  // ── Factory ──────────────────────────────────────────────────────────────────

  /// Creates a [WeldCertificate] from the supplied fields.
  ///
  /// Schema, version and provenance use their defaults when not specified.
  static WeldCertificate generateCertificate({
    required String   jointId,
    required String   signature,
    required DateTime timestamp,
    required String   machineId,
    required double   diameter,
    required String   material,
    required String   sdr,
    required String   traceQuality,
    String  schemaType      = _defaultSchemaType,
    String  schemaVersion   = _defaultSchemaVersion,
    String  version         = _defaultVersion,
    double? fusionPressure,
    double? heatingTime,
    double? coolingTime,
    double? beadHeight,
    String? pdfHash,
    String? software,
    String? softwareVersion,
    String? syncStatus,
  }) =>
      WeldCertificate(
        schemaType:      schemaType,
        schemaVersion:   schemaVersion,
        version:         version,
        jointId:         jointId,
        signature:       signature,
        timestamp:       timestamp,
        machineId:       machineId,
        diameter:        diameter,
        material:        material,
        sdr:             sdr,
        traceQuality:    traceQuality,
        fusionPressure:  fusionPressure,
        heatingTime:     heatingTime,
        coolingTime:     coolingTime,
        beadHeight:      beadHeight,
        pdfHash:         pdfHash,
        software:        software,
        softwareVersion: softwareVersion,
        syncStatus:      syncStatus,
      );

  // ── PDF hash utility ─────────────────────────────────────────────────────────

  /// Computes the SHA-256 hex digest of [pdfBytes].
  ///
  /// Call this immediately after [WeldReportGenerator.generate()] and
  /// pass the result as [pdfHash] to [generateCertificate].
  static String computePdfHash(Uint8List pdfBytes) =>
      sha256.convert(pdfBytes).toString();

  // ── Export ───────────────────────────────────────────────────────────────────

  /// Loads the registry entry for [jointId], generates a certificate, and
  /// saves it as `{jointId}.certificate.json` in the application documents
  /// directory.
  ///
  /// Pass [registryPath] and/or [outputDir] to override the default
  /// production paths.  Provide [software] and [softwareVersion] to embed
  /// provenance metadata.
  ///
  /// Throws [StateError] when [jointId] is not found in the registry.
  static Future<File> exportCertificate(
    String jointId, {
    String? registryPath,
    String? outputDir,
    String? software,
    String? softwareVersion,
  }) async {
    final entry = await WeldRegistry.findByJointId(
      jointId,
      registryPath: registryPath,
    );
    if (entry == null) {
      throw StateError(
          'WeldCertificate.exportCertificate: jointId "$jointId" not found '
          'in registry');
    }

    final cert = generateCertificate(
      jointId:         entry.jointId,
      signature:       entry.signature,
      timestamp:       entry.timestamp,
      machineId:       entry.machineId,
      diameter:        entry.diameter,
      material:        entry.material,
      sdr:             entry.sdr,
      traceQuality:    'OK',
      software:        software,
      softwareVersion: softwareVersion,
    );

    final String dir;
    if (outputDir != null) {
      dir = outputDir;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      dir = appDir.path;
    }

    const encoder = JsonEncoder.withIndent('  ');
    final filename = '$jointId.certificate.json';
    final file     = File('$dir/$filename');
    await file.writeAsString(encoder.convert(cert.toJson()), flush: true);
    return file;
  }

  @override
  String toString() => 'WeldCertificate(v=$version, jointId=$jointId, '
      'material=$material ${diameter}mm SDR $sdr, quality=$traceQuality)';
}
