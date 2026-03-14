import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'weld_registry.dart';

/// A portable, self-contained weld certificate.
///
/// A [WeldCertificate] captures every field needed to independently prove
/// that a weld was performed correctly and has not been tampered with:
///
/// - Identity: [jointId] (UUID v7), [signature] (SHA-256 hex)
/// - Pipe metadata: [diameter], [material], [sdr]
/// - Equipment: [machineId]
/// - Timing: [timestamp] (UTC)
/// - Quality: [traceQuality]
/// - Process parameters (optional): [fusionPressure], [heatingTime],
///   [coolingTime], [beadHeight]
/// - PDF integrity: [pdfHash] (SHA-256 of the PDF bytes, optional)
///
/// ## JSON key ordering
///
/// [toJson] always emits keys in this canonical order so that the
/// serialised certificate is bit-for-bit reproducible across platforms:
///
/// ```
/// jointId, signature, timestamp, machineId, diameter, material, sdr,
/// traceQuality, fusionPressure, heatingTime, coolingTime, beadHeight,
/// pdfHash
/// ```
///
/// Null optional values are included as JSON `null` to keep the schema
/// stable.
///
/// ## Usage
///
/// ```dart
/// // Generate
/// final cert = WeldCertificate.generateCertificate(
///   jointId:      jointId,
///   signature:    signature,
///   timestamp:    completedAt,
///   machineId:    machineId,
///   diameter:     160.0,
///   material:     'PE100',
///   sdr:          '11',
///   traceQuality: 'OK',
///   pdfHash:      WeldCertificate.computePdfHash(pdfBytes),
/// );
///
/// // Export to disk
/// final file = await WeldCertificate.exportCertificate(jointId);
///
/// // Round-trip
/// final restored = WeldCertificate.fromJson(jsonDecode(file.readAsStringSync()));
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
    this.fusionPressure,
    this.heatingTime,
    this.coolingTime,
    this.beadHeight,
    this.pdfHash,
  });

  // ── Required fields ──────────────────────────────────────────────────────────

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

  // ── Optional fields ──────────────────────────────────────────────────────────

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

  // ── Serialisation ────────────────────────────────────────────────────────────

  /// Returns a [Map] with keys in the canonical order specified by the
  /// WeldTrace certificate schema.
  ///
  /// Key order: jointId → signature → timestamp → machineId → diameter →
  /// material → sdr → traceQuality → fusionPressure → heatingTime →
  /// coolingTime → beadHeight → pdfHash
  Map<String, dynamic> toJson() => <String, dynamic>{
        'jointId':       jointId,
        'signature':     signature,
        'timestamp':     timestamp.toUtc().toIso8601String(),
        'machineId':     machineId,
        'diameter':      diameter,
        'material':      material,
        'sdr':           sdr,
        'traceQuality':  traceQuality,
        'fusionPressure': fusionPressure,
        'heatingTime':   heatingTime,
        'coolingTime':   coolingTime,
        'beadHeight':    beadHeight,
        'pdfHash':       pdfHash,
      };

  /// Reconstructs a [WeldCertificate] from a [json] map previously produced
  /// by [toJson].
  factory WeldCertificate.fromJson(Map<String, dynamic> json) =>
      WeldCertificate(
        jointId:       json['jointId']      as String,
        signature:     json['signature']    as String,
        timestamp:     DateTime.parse(json['timestamp'] as String).toUtc(),
        machineId:     json['machineId']    as String,
        diameter:      (json['diameter']    as num).toDouble(),
        material:      json['material']     as String,
        sdr:           json['sdr']          as String,
        traceQuality:  json['traceQuality'] as String,
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
        pdfHash: json['pdfHash'] as String?,
      );

  // ── Factory ──────────────────────────────────────────────────────────────────

  /// Creates a [WeldCertificate] from the supplied fields.
  ///
  /// All required parameters map directly to [WeldCertificate] fields.
  /// Optional process parameters and [pdfHash] default to `null`.
  static WeldCertificate generateCertificate({
    required String   jointId,
    required String   signature,
    required DateTime timestamp,
    required String   machineId,
    required double   diameter,
    required String   material,
    required String   sdr,
    required String   traceQuality,
    double? fusionPressure,
    double? heatingTime,
    double? coolingTime,
    double? beadHeight,
    String? pdfHash,
  }) =>
      WeldCertificate(
        jointId:       jointId,
        signature:     signature,
        timestamp:     timestamp,
        machineId:     machineId,
        diameter:      diameter,
        material:      material,
        sdr:           sdr,
        traceQuality:  traceQuality,
        fusionPressure: fusionPressure,
        heatingTime:   heatingTime,
        coolingTime:   coolingTime,
        beadHeight:    beadHeight,
        pdfHash:       pdfHash,
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
  /// production paths (useful in tests and CLI scripts).
  ///
  /// Throws [StateError] when [jointId] is not found in the registry.
  static Future<File> exportCertificate(
    String jointId, {
    String? registryPath,
    String? outputDir,
  }) async {
    // Load registry entry
    final entry = await WeldRegistry.findByJointId(
      jointId,
      registryPath: registryPath,
    );
    if (entry == null) {
      throw StateError(
          'WeldCertificate.exportCertificate: jointId "$jointId" not found '
          'in registry');
    }

    // Build certificate from registry data
    final cert = generateCertificate(
      jointId:      entry.jointId,
      signature:    entry.signature,
      timestamp:    entry.timestamp,
      machineId:    entry.machineId,
      diameter:     entry.diameter,
      material:     entry.material,
      sdr:          entry.sdr,
      traceQuality: 'OK',
    );

    // Determine output path
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
  String toString() => 'WeldCertificate(jointId: $jointId, '
      'material: $material $diameter mm SDR $sdr, quality: $traceQuality)';
}
