// ignore_for_file: avoid_print

/// WeldTrace — Registry Export CLI
///
/// Reads `registry_export.json` (or a specified path) and either pretty-
/// prints the full registry or generates a single portable certificate.
///
/// Usage:
///   dart run scripts/export_registry.dart
///   dart run scripts/export_registry.dart /path/to/registry_export.json
///   dart run scripts/export_registry.dart /path/to/registry_export.json --out /path/to/output.json
///   dart run scripts/export_registry.dart --certificate 018f4e5a-1b2c-7d3e-9a4b-5c6d7e8f9a0b
///   dart run scripts/export_registry.dart /path/to/registry_export.json --certificate <jointId>
///
/// Exit codes:
///   0 — Success.
///   1 — File not found, parse error, I/O error, or joint ID not found.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  // ── Parse arguments ──────────────────────────────────────────────────────────
  final positional      = args.where((a) => !a.startsWith('--')).toList();
  final outFlagIdx      = args.indexOf('--out');
  final certFlagIdx     = args.indexOf('--certificate');

  final outPath         = outFlagIdx != -1 && outFlagIdx + 1 < args.length
      ? args[outFlagIdx + 1]
      : null;
  final certJointId     = certFlagIdx != -1 && certFlagIdx + 1 < args.length
      ? args[certFlagIdx + 1]
      : null;

  final inputPath = positional.isNotEmpty
      ? positional.first
      : 'registry_export.json';

  // ── Read registry file ───────────────────────────────────────────────────────
  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln(
      'Error: registry file not found at "$inputPath"\n'
      'Usage: dart run scripts/export_registry.dart [path/to/registry_export.json]',
    );
    exit(1);
  }

  String raw;
  try {
    raw = await inputFile.readAsString();
  } catch (e) {
    stderr.writeln('Error reading "$inputPath": $e');
    exit(1);
  }

  if (raw.trim().isEmpty) {
    if (certJointId != null) {
      stderr.writeln('Error: registry is empty — cannot generate certificate.');
      exit(1);
    }
    stderr.writeln('Registry file is empty — no entries to export.');
    stdout.writeln('[]');
    return;
  }

  // ── Parse JSON ───────────────────────────────────────────────────────────────
  List<dynamic> entries;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      stderr.writeln('Error: registry file is not a JSON array.');
      exit(1);
    }
    entries = decoded;
  } catch (e) {
    stderr.writeln('Error parsing registry JSON: $e');
    exit(1);
  }

  // ── Branch: --certificate <jointId> ─────────────────────────────────────────
  if (certJointId != null) {
    await _generateCertificate(entries, certJointId, outPath);
    return;
  }

  // ── Branch: plain export ─────────────────────────────────────────────────────
  const encoder = JsonEncoder.withIndent('  ');
  final pretty  = encoder.convert(entries);

  if (outPath != null) {
    try {
      await File(outPath).writeAsString(pretty, flush: true);
      stderr.writeln(
        'Exported ${entries.length} registry '
        '${entries.length == 1 ? 'entry' : 'entries'} → "$outPath"',
      );
    } catch (e) {
      stderr.writeln('Error writing output to "$outPath": $e');
      exit(1);
    }
  } else {
    stdout.writeln(pretty);
    stderr.writeln(
      'Exported ${entries.length} registry '
      '${entries.length == 1 ? 'entry' : 'entries'} from "$inputPath"',
    );
  }
}

// ── Certificate generator (standalone — no Flutter/path_provider) ────────────

Future<void> _generateCertificate(
  List<dynamic> entries,
  String jointId,
  String? outPath,
) async {
  // Find entry by jointId
  Map<String, dynamic>? entry;
  for (final e in entries) {
    if (e is Map && e['jointId'] == jointId) {
      entry = Map<String, dynamic>.from(e);
      break;
    }
  }

  if (entry == null) {
    stderr.writeln('Error: joint ID "$jointId" not found in registry.');
    exit(1);
  }

  // Build certificate map with canonical key ordering
  final cert = <String, dynamic>{
    'schema': <String, dynamic>{
      'type':    'WeldTraceCertificate',
      'version': '1.0',
    },
    'version':         'WeldTrace-CERT-1',
    'jointId':         entry['jointId'],
    'signature':       entry['signature'],
    'timestamp':       entry['timestamp'],
    'machineId':       entry['machineId'],
    'diameter':        entry['diameter'],
    'material':        entry['material'],
    'sdr':             entry['sdr'],
    'traceQuality':    'OK',
    'fusionPressure':  null,
    'heatingTime':     null,
    'coolingTime':     null,
    'beadHeight':      null,
    'pdfHash':         null,
    'software':        'WeldTrace',
    'softwareVersion': '1.0.0',
  };

  const encoder    = JsonEncoder.withIndent('  ');
  final prettyJson = encoder.convert(cert);

  final filename   = '$jointId.certificate.json';
  final outputPath = outPath ?? filename;

  try {
    await File(outputPath).writeAsString(prettyJson, flush: true);
    stderr.writeln('Certificate written → "$outputPath"');
  } catch (e) {
    stderr.writeln('Error writing certificate to "$outputPath": $e');
    exit(1);
  }
}
