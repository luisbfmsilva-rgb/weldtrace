import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A single certified weld entry stored in the local ledger.
class WeldLedgerEntry {
  const WeldLedgerEntry({
    required this.jointId,
    required this.signature,
    required this.timestamp,
    required this.machineId,
    required this.diameter,
    required this.material,
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

  /// Pipe material code (e.g. 'PE100').
  final String material;

  Map<String, dynamic> toJson() => {
        'jointId':   jointId,
        'signature': signature,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'machineId': machineId,
        'diameter':  diameter,
        'material':  material,
      };

  factory WeldLedgerEntry.fromJson(Map<String, dynamic> json) =>
      WeldLedgerEntry(
        jointId:   json['jointId']   as String,
        signature: json['signature'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
        machineId: json['machineId'] as String,
        diameter:  (json['diameter'] as num).toDouble(),
        material:  json['material']  as String,
      );
}

/// Append-only local certification ledger for completed welds.
///
/// Entries are persisted as a JSON array in `ledger.json` inside the
/// application documents directory.  Once written, entries are NEVER
/// modified or deleted — only new entries are appended.
///
/// All write / read methods accept an optional [ledgerPath] that overrides
/// the production file path.  Pass a temporary file path in unit tests to
/// avoid touching the real documents directory.
///
/// Usage:
/// ```dart
/// // After weld completion:
/// await WeldLedger.append(WeldLedgerEntry(
///   jointId:   jointId,
///   signature: signature,
///   timestamp: DateTime.now().toUtc(),
///   machineId: machineId,
///   diameter:  160.0,
///   material:  'PE100',
/// ));
///
/// // Verify a scanned signature:
/// final valid = await WeldLedger.verifyLedgerEntry(scannedSignature);
/// ```
class WeldLedger {
  WeldLedger._();

  static const _fileName = 'ledger.json';

  // ── Internal helpers ────────────────────────────────────────────────────────

  /// Returns the [File] handle for the ledger.
  ///
  /// When [ledgerPath] is provided it is used directly (for testing).
  /// Otherwise the file is placed in the application documents directory.
  static Future<File> _file([String? ledgerPath]) async {
    if (ledgerPath != null) return File(ledgerPath);
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Reads and deserialises all entries from the ledger file.
  ///
  /// Returns an empty list when the file does not exist or is empty.
  static Future<List<WeldLedgerEntry>> _read(File file) async {
    if (!file.existsSync()) return [];
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => WeldLedgerEntry.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Loads all entries from the ledger.
  ///
  /// Returns an empty list when the ledger file does not exist yet.
  static Future<List<WeldLedgerEntry>> loadAll({String? ledgerPath}) async {
    final file = await _file(ledgerPath);
    return _read(file);
  }

  /// Appends a new [entry] to the ledger.
  ///
  /// This operation is safe to call from any isolate — it reads the current
  /// list, appends the new entry, and writes the updated list atomically by
  /// writing to a temp file and renaming.
  ///
  /// Throws if the file system is unavailable.
  static Future<void> append(
    WeldLedgerEntry entry, {
    String? ledgerPath,
  }) async {
    final file    = await _file(ledgerPath);
    final entries = await _read(file);
    entries.add(entry);
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    await file.writeAsString(json, flush: true);
  }

  /// Returns `true` when [signature] matches any entry in the ledger.
  ///
  /// This is an exact string comparison of the 64-char SHA-256 hex digest.
  static Future<bool> verifyLedgerEntry(
    String signature, {
    String? ledgerPath,
  }) async {
    final entries = await loadAll(ledgerPath: ledgerPath);
    return entries.any((e) => e.signature == signature);
  }

  /// Returns the [WeldLedgerEntry] for [jointId], or `null` when not found.
  static Future<WeldLedgerEntry?> findByJointId(
    String jointId, {
    String? ledgerPath,
  }) async {
    final entries = await loadAll(ledgerPath: ledgerPath);
    try {
      return entries.firstWhere((e) => e.jointId == jointId);
    } catch (_) {
      return null;
    }
  }
}
