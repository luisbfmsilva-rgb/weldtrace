import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A single weld entry in the global certification registry.
///
/// The registry is intended for export to a public or institutional
/// repository so that any party can verify a weld's authenticity by
/// matching the [jointId] + [signature] pair.
class WeldRegistryEntry {
  const WeldRegistryEntry({
    required this.jointId,
    required this.signature,
    required this.timestamp,
    required this.machineId,
    required this.diameter,
    required this.material,
    required this.sdr,
  });

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

  Map<String, dynamic> toJson() => {
        'jointId':   jointId,
        'signature': signature,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'machineId': machineId,
        'diameter':  diameter,
        'material':  material,
        'sdr':       sdr,
      };

  factory WeldRegistryEntry.fromJson(Map<String, dynamic> json) =>
      WeldRegistryEntry(
        jointId:   json['jointId']   as String,
        signature: json['signature'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
        machineId: json['machineId'] as String,
        diameter:  (json['diameter'] as num).toDouble(),
        material:  json['material']  as String,
        sdr:       json['sdr']       as String,
      );
}

/// Append-only local registry of completed weld certifications.
///
/// Entries are persisted as a JSON array in `registry_export.json` inside
/// the application documents directory.  Once written, entries are NEVER
/// modified or deleted — only new entries are appended.
///
/// The registry is designed to be exported and uploaded to a public
/// institutional repository (e.g. via [exportRegistry]).  Third parties
/// can then call [verifyFromRegistry] to confirm a joint's authenticity.
///
/// All write / read methods accept an optional [registryPath] that
/// overrides the production file path — pass a temporary path in unit tests.
///
/// Usage:
/// ```dart
/// // After weld completion:
/// await WeldRegistry.append(WeldRegistryEntry(
///   jointId:   jointId,
///   signature: signature,
///   timestamp: DateTime.now().toUtc(),
///   machineId: machineId,
///   diameter:  160.0,
///   material:  'PE100',
///   sdr:       '11',
/// ));
///
/// // Export all entries for upload:
/// final entries = await WeldRegistry.exportRegistry();
///
/// // Verify a scanned weld:
/// final valid = await WeldRegistry.verifyFromRegistry(
///   jointId:   scannedJointId,
///   signature: scannedSignature,
/// );
/// ```
class WeldRegistry {
  WeldRegistry._();

  static const _fileName = 'registry_export.json';

  // ── Internal helpers ────────────────────────────────────────────────────────

  static Future<File> _file([String? registryPath]) async {
    if (registryPath != null) return File(registryPath);
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<WeldRegistryEntry>> _read(File file) async {
    if (!file.existsSync()) return [];
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => WeldRegistryEntry.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Appends a new [entry] to the registry file.
  ///
  /// The operation is append-only — existing entries are never modified.
  /// Throws if the file system is unavailable.
  static Future<void> append(
    WeldRegistryEntry entry, {
    String? registryPath,
  }) async {
    final file    = await _file(registryPath);
    final entries = await _read(file);
    entries.add(entry);
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await file.writeAsString(json, flush: true);
  }

  /// Returns all entries in the registry.
  ///
  /// Intended for bulk export to a public repository.  Returns an empty
  /// list when the file does not exist yet.
  static Future<List<WeldRegistryEntry>> exportRegistry({
    String? registryPath,
  }) async {
    final file = await _file(registryPath);
    return _read(file);
  }

  /// Returns `true` when both [jointId] and [signature] match the same
  /// entry in the registry.
  ///
  /// This exact-match check provides strong tamper detection — both fields
  /// must be correct simultaneously.
  static Future<bool> verifyFromRegistry({
    required String jointId,
    required String signature,
    String? registryPath,
  }) async {
    final entries = await exportRegistry(registryPath: registryPath);
    return entries.any(
      (e) => e.jointId == jointId && e.signature == signature,
    );
  }

  /// Returns the [WeldRegistryEntry] for [jointId], or `null` when not found.
  static Future<WeldRegistryEntry?> findByJointId(
    String jointId, {
    String? registryPath,
  }) async {
    final entries = await exportRegistry(registryPath: registryPath);
    try {
      return entries.firstWhere((e) => e.jointId == jointId);
    } catch (_) {
      return null;
    }
  }
}
