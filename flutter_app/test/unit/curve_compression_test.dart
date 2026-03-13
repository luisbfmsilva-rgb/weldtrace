import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:weldtrace/services/welding_trace/curve_compression.dart';
import 'package:weldtrace/services/welding_trace/weld_trace_recorder.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Generates a list of [n] WeldTracePoint objects with predictable values.
List<WeldTracePoint> _generateCurve(int n) => List.generate(
      n,
      (i) => WeldTracePoint(
        timeSeconds: i.toDouble(),
        pressureBar: 0.10 + (i % 10) * 0.01,
        phase:       i < n ~/ 2 ? 'Heating' : 'Fusion Pressure',
      ),
    );

/// Encodes a curve to the same JSON format the DAO uses before compressing.
String _encodeJson(List<WeldTracePoint> curve) =>
    jsonEncode(curve.map((p) => p.toJson()).toList());

void main() {
  // ── CurveCompression ────────────────────────────────────────────────────────

  group('CurveCompression', () {
    // ── Round-trip ────────────────────────────────────────────────────────────

    test('compression → decompression round-trip preserves original JSON', () {
      final curve  = _generateCurve(100);
      final json   = _encodeJson(curve);
      final bytes  = CurveCompression.compressCurve(json);
      final result = CurveCompression.decompressCurve(bytes);
      expect(result, equals(json));
    });

    test('round-trip preserves all WeldTracePoint fields', () {
      final original = _generateCurve(50);
      final json     = _encodeJson(original);
      final bytes    = CurveCompression.compressCurve(json);
      final decoded  = CurveCompression.decompressCurve(bytes);

      final restored = (jsonDecode(decoded) as List)
          .map((e) => WeldTracePoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      expect(restored.length, equals(original.length));
      for (int i = 0; i < original.length; i++) {
        expect(restored[i].timeSeconds, closeTo(original[i].timeSeconds, 1e-9));
        expect(restored[i].pressureBar, closeTo(original[i].pressureBar, 1e-9));
        expect(restored[i].phase, equals(original[i].phase));
      }
    });

    // ── Size reduction ────────────────────────────────────────────────────────

    test('compression reduces size for a typical 100-sample curve', () {
      final json  = _encodeJson(_generateCurve(100));
      final bytes = CurveCompression.compressCurve(json);
      // Compressed must be smaller than the original UTF-8 bytes
      expect(bytes.length, lessThan(json.length));
    });

    test('compression reduces size for a typical 1 000-sample curve', () {
      final json  = _encodeJson(_generateCurve(1000));
      final bytes = CurveCompression.compressCurve(json);
      expect(bytes.length, lessThan(json.length));
    });

    test('compression ratio is > 5 : 1 for a 1 000-sample curve', () {
      final json      = _encodeJson(_generateCurve(1000));
      final bytes     = CurveCompression.compressCurve(json);
      final ratio     = json.length / bytes.length;
      expect(ratio, greaterThan(5.0),
          reason:
              'Expected at least 5× compression for a repetitive pressure curve '
              '(actual ratio: ${ratio.toStringAsFixed(1)}×)');
    });

    // ── Large curve ───────────────────────────────────────────────────────────

    test('round-trip for maximum-size curve (5 000 samples)', () {
      final curve  = _generateCurve(5000);
      final json   = _encodeJson(curve);
      final bytes  = CurveCompression.compressCurve(json);
      final result = CurveCompression.decompressCurve(bytes);
      expect(result, equals(json));
    });

    test('large curve compresses to under 10 % of original JSON length', () {
      final json  = _encodeJson(_generateCurve(5000));
      final bytes = CurveCompression.compressCurve(json);
      final ratio = bytes.length / json.length;
      expect(ratio, lessThan(0.10),
          reason:
              'Expected compressed size < 10 % of JSON for 5 000 samples '
              '(actual: ${(ratio * 100).toStringAsFixed(1)} %)');
    });

    // ── Edge cases ────────────────────────────────────────────────────────────

    test('empty curve compresses and decompresses cleanly', () {
      final json   = _encodeJson([]);
      final bytes  = CurveCompression.compressCurve(json);
      final result = CurveCompression.decompressCurve(bytes);
      expect(result, equals(json));
      expect(jsonDecode(result), equals([]));
    });

    test('single-sample curve survives round-trip', () {
      final curve  = _generateCurve(1);
      final json   = _encodeJson(curve);
      final bytes  = CurveCompression.compressCurve(json);
      final result = CurveCompression.decompressCurve(bytes);
      expect(result, equals(json));
    });

    test('compressCurve returns Uint8List', () {
      final bytes = CurveCompression.compressCurve('[]');
      expect(bytes.runtimeType.toString(), contains('Uint8List'));
    });

    test('identical inputs produce identical compressed bytes', () {
      final json   = _encodeJson(_generateCurve(200));
      final bytesA = CurveCompression.compressCurve(json);
      final bytesB = CurveCompression.compressCurve(json);
      expect(bytesA, equals(bytesB));
    });
  });
}
