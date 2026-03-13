// ignore_for_file: avoid_print

/// WeldTrace — Registry Export CLI
///
/// Reads `registry_export.json` from the specified path (or the current
/// directory by default) and prints the contents as pretty-printed JSON to
/// stdout.
///
/// Usage:
///   dart run scripts/export_registry.dart
///   dart run scripts/export_registry.dart /path/to/registry_export.json
///   dart run scripts/export_registry.dart /path/to/registry_export.json --out /path/to/output.json
///
/// Exit codes:
///   0 — Success.
///   1 — File not found, parse error, or unexpected I/O error.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  // ── Parse arguments ─────────────────────────────────────────────────────────
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final outFlagIdx = args.indexOf('--out');
  final outPath    = outFlagIdx != -1 && outFlagIdx + 1 < args.length
      ? args[outFlagIdx + 1]
      : null;

  final inputPath = positional.isNotEmpty
      ? positional.first
      : 'registry_export.json';

  // ── Read input ───────────────────────────────────────────────────────────────
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
    stderr.writeln('Registry file is empty — no entries to export.');
    stdout.writeln('[]');
    return;
  }

  // ── Parse and validate ───────────────────────────────────────────────────────
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

  // ── Pretty-print output ──────────────────────────────────────────────────────
  const encoder = JsonEncoder.withIndent('  ');
  final pretty  = encoder.convert(entries);

  if (outPath != null) {
    // Write to output file
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
    // Write to stdout
    stdout.writeln(pretty);
    stderr.writeln(
      'Exported ${entries.length} registry '
      '${entries.length == 1 ? 'entry' : 'entries'} from "$inputPath"',
    );
  }
}
