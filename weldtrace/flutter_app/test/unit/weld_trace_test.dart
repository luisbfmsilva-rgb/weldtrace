import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:weldtrace/services/welding_trace/weld_trace_recorder.dart';
import 'package:weldtrace/services/welding_trace/weld_trace_signature.dart';
import 'package:weldtrace/services/welding_trace/weld_report_generator.dart';
import 'package:weldtrace/services/welding_trace/weld_verifier.dart';
import 'package:weldtrace/services/welding_trace/curve_compression.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Creates a recorder with the rate-limit disabled so tests can inject many
/// samples in a tight loop without waiting for wall-clock delays.
WeldTraceRecorder _fastRecorder() => WeldTraceRecorder(minSampleIntervalMs: 0);

void main() {
  // ── WeldTraceRecorder ───────────────────────────────────────────────────────

  group('WeldTraceRecorder', () {
    // ── Basic lifecycle ───────────────────────────────────────────────────────

    test('starts with empty curve and isStarted == false', () {
      final recorder = WeldTraceRecorder();
      expect(recorder.points, isEmpty);
      expect(recorder.isStarted, isFalse);
    });

    test('record() is a no-op before start()', () {
      final recorder = WeldTraceRecorder();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      expect(recorder.points, isEmpty);
    });

    test('isStarted becomes true after start()', () {
      final recorder = WeldTraceRecorder();
      recorder.start();
      expect(recorder.isStarted, isTrue);
    });

    test('points accumulate after start()', () {
      final recorder = _fastRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      recorder.record(pressureBar: 0.14, phase: 'Fusion Pressure');
      expect(recorder.points.length, equals(2));
    });

    test('timeSeconds is monotonically non-decreasing', () {
      final recorder = _fastRecorder();
      recorder.start();
      for (int i = 0; i < 5; i++) {
        recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      }
      for (int i = 1; i < recorder.points.length; i++) {
        expect(
          recorder.points[i].timeSeconds,
          greaterThanOrEqualTo(recorder.points[i - 1].timeSeconds),
        );
      }
    });

    test('negative pressures are clamped to zero', () {
      final recorder = WeldTraceRecorder();
      recorder.start();
      recorder.record(pressureBar: -5.0, phase: 'Changeover');
      expect(recorder.points.first.pressureBar, equals(0.0));
    });

    test('export() returns an unmodifiable copy', () {
      final recorder = WeldTraceRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      final exported = recorder.export();
      expect(() => (exported as dynamic).add(null), throwsUnsupportedError);
    });

    test('export() reflects only accepted samples', () {
      final recorder = _fastRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      recorder.record(pressureBar: 0.14, phase: 'Fusion Pressure');
      expect(recorder.export().length, equals(2));
    });

    test('export() on unstarted recorder returns empty list', () {
      final recorder = WeldTraceRecorder();
      expect(recorder.export(), isEmpty);
    });

    test('start() clears previous recording and resets sample timer', () {
      final recorder = _fastRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      recorder.record(pressureBar: 0.20, phase: 'Cooling');
      expect(recorder.points.length, equals(2));

      recorder.start(); // second start — must reset
      expect(recorder.points, isEmpty);

      // Should accept a fresh sample immediately after reset
      recorder.record(pressureBar: 0.10, phase: 'Heating');
      expect(recorder.points.length, equals(1));
    });

    // ── Rate-limiting guard ───────────────────────────────────────────────────

    test('sampling guard: only first of two rapid calls is stored', () {
      // Default recorder enforces ≥ 1 000 ms between samples.
      final recorder = WeldTraceRecorder(); // minSampleIntervalMs: 1000
      recorder.start();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      recorder.record(pressureBar: 0.20, phase: 'Fusion Pressure'); // too fast
      expect(recorder.points.length, equals(1),
          reason:
              'Second call within 1 s should be silently discarded by rate-limit guard');
    });

    test('sampling guard: bypass with minSampleIntervalMs == 0 accepts all samples', () {
      final recorder = _fastRecorder();
      recorder.start();
      for (int i = 0; i < 10; i++) {
        recorder.record(pressureBar: 0.10, phase: 'Fusion Pressure');
      }
      expect(recorder.points.length, equals(10));
    });

    // ── Max-size guard ────────────────────────────────────────────────────────

    test('max curve size: stops at ${WeldTraceRecorder.maxPoints} samples', () {
      const extra = 50;
      final recorder = _fastRecorder();
      recorder.start();
      for (int i = 0; i < WeldTraceRecorder.maxPoints + extra; i++) {
        recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      }
      expect(recorder.points.length, equals(WeldTraceRecorder.maxPoints),
          reason:
              'Samples beyond maxPoints must be silently discarded');
    });

    // ── Large curve export ────────────────────────────────────────────────────

    test('large curve export: ${WeldTraceRecorder.maxPoints} points survive export()', () {
      final recorder = _fastRecorder();
      recorder.start();
      for (int i = 0; i < WeldTraceRecorder.maxPoints; i++) {
        recorder.record(
          pressureBar: 0.10 + (i % 20) * 0.005,
          phase:       'Fusion Pressure',
        );
      }
      final curve = recorder.export();
      expect(curve.length, equals(WeldTraceRecorder.maxPoints));
    });

    // ── Derived statistics ────────────────────────────────────────────────────

    test('maxPressureBar returns correct maximum', () {
      final recorder = _fastRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.10, phase: 'Heating');
      recorder.record(pressureBar: 0.25, phase: 'Fusion Pressure');
      recorder.record(pressureBar: 0.18, phase: 'Cooling');
      expect(recorder.maxPressureBar, closeTo(0.25, 1e-6));
    });

    test('averagePressureBar returns correct mean', () {
      final recorder = _fastRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.10, phase: 'Heating');
      recorder.record(pressureBar: 0.20, phase: 'Fusion Pressure');
      // avg = (0.10 + 0.20) / 2 = 0.15
      expect(recorder.averagePressureBar, closeTo(0.15, 1e-6));
    });

    test('maxPressureBar returns 0 on empty curve', () {
      expect(WeldTraceRecorder().maxPressureBar, equals(0));
    });

    test('averagePressureBar returns 0 on empty curve', () {
      expect(WeldTraceRecorder().averagePressureBar, equals(0));
    });

    test('recordedDurationSeconds returns 0 for < 2 samples', () {
      final recorder = WeldTraceRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      expect(recorder.recordedDurationSeconds, equals(0));
    });

    // ── WeldTracePoint serialisation ──────────────────────────────────────────

    test('WeldTracePoint toJson / fromJson round-trip', () {
      const point = WeldTracePoint(
        timeSeconds: 12.5,
        pressureBar: 0.175,
        phase:       'Fusion Pressure',
      );
      final json        = point.toJson();
      final deserialised = WeldTracePoint.fromJson(json);
      expect(deserialised.timeSeconds, closeTo(12.5,  1e-9));
      expect(deserialised.pressureBar, closeTo(0.175, 1e-9));
      expect(deserialised.phase, equals('Fusion Pressure'));
    });
  });

  // ── WeldTraceSignature ──────────────────────────────────────────────────────

  group('WeldTraceSignature', () {
    final ts = DateTime.utc(2025, 6, 15, 8, 30, 0);

    List<WeldTracePoint> _sampleCurve() => [
          const WeldTracePoint(timeSeconds: 0,   pressureBar: 0.15, phase: 'Heating-up'),
          const WeldTracePoint(timeSeconds: 30,  pressureBar: 0.02, phase: 'Heat Soak'),
          const WeldTracePoint(timeSeconds: 100, pressureBar: 0.15, phase: 'Fusion Pressure'),
          const WeldTracePoint(timeSeconds: 130, pressureBar: 0.15, phase: 'Cooling'),
        ];

    // ── Format ────────────────────────────────────────────────────────────────

    test('returns a 64-character lowercase hex string (SHA-256)', () {
      final sig = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        _sampleCurve(),
        timestamp:    ts,
      );
      expect(sig.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(sig), isTrue);
    });

    // ── Determinism ───────────────────────────────────────────────────────────

    test('is deterministic — same inputs produce the same hash', () {
      final sig1 = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        _sampleCurve(),
        timestamp:    ts,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        _sampleCurve(),
        timestamp:    ts,
      );
      expect(sig1, equals(sig2));
    });

    test('deterministic regardless of curve insertion order', () {
      final ordered = _sampleCurve();
      // Reverse the list to simulate out-of-order BLE delivery.
      final reversed = ordered.reversed.toList();

      final sig1 = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        ordered,
        timestamp:    ts,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        reversed,
        timestamp:    ts,
      );
      expect(sig1, equals(sig2),
          reason: 'Sorting by timeSeconds must make the hash order-independent');
    });

    // ── Sensitivity ───────────────────────────────────────────────────────────

    test('different machine ID → different hash', () {
      final sig1 = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160, material: 'PE100', sdr: '11',
        curve:        _sampleCurve(), timestamp: ts,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId:    'MACHINE-002',
        pipeDiameter: 160, material: 'PE100', sdr: '11',
        curve:        _sampleCurve(), timestamp: ts,
      );
      expect(sig1, isNot(equals(sig2)));
    });

    test('different curve content → different hash', () {
      final curve1 = _sampleCurve();
      final curve2 = [
        ...curve1,
        const WeldTracePoint(timeSeconds: 200, pressureBar: 0.99, phase: 'Cooling'),
      ];
      final sig1 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11', curve: curve1, timestamp: ts,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11', curve: curve2, timestamp: ts,
      );
      expect(sig1, isNot(equals(sig2)));
    });

    test('different timestamp → different hash', () {
      final sig1 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11', curve: _sampleCurve(), timestamp: ts,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11',
        curve: _sampleCurve(),
        timestamp: ts.add(const Duration(seconds: 1)),
      );
      expect(sig1, isNot(equals(sig2)));
    });

    test('different fusionPressureBar → different hash', () {
      final sig1 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11',
        curve: _sampleCurve(), timestamp: ts,
        fusionPressureBar: 0.15,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11',
        curve: _sampleCurve(), timestamp: ts,
        fusionPressureBar: 0.20, // changed
      );
      expect(sig1, isNot(equals(sig2)));
    });

    test('different heatingTimeSec → different hash', () {
      final sig1 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11',
        curve: _sampleCurve(), timestamp: ts,
        heatingTimeSec: 60,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11',
        curve: _sampleCurve(), timestamp: ts,
        heatingTimeSec: 90, // changed
      );
      expect(sig1, isNot(equals(sig2)));
    });

    test('different coolingTimeSec → different hash', () {
      final sig1 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11',
        curve: _sampleCurve(), timestamp: ts,
        coolingTimeSec: 120,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11',
        curve: _sampleCurve(), timestamp: ts,
        coolingTimeSec: 150, // changed
      );
      expect(sig1, isNot(equals(sig2)));
    });

    test('different beadHeightMm → different hash', () {
      final sig1 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11',
        curve: _sampleCurve(), timestamp: ts,
        beadHeightMm: 5.0,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11',
        curve: _sampleCurve(), timestamp: ts,
        beadHeightMm: 7.5, // changed
      );
      expect(sig1, isNot(equals(sig2)));
    });

    // ── Edge cases ────────────────────────────────────────────────────────────

    test('empty curve produces a valid, deterministic hash', () {
      final sig1 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11', curve: [], timestamp: ts,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11', curve: [], timestamp: ts,
      );
      expect(sig1.length, equals(64));
      expect(sig1, equals(sig2));
    });

    // ── verify() ─────────────────────────────────────────────────────────────

    test('verify() returns true for matching inputs', () {
      final curve = _sampleCurve();
      final sig   = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11', curve: curve, timestamp: ts,
      );
      expect(
        WeldTraceSignature.verify(
          signature: sig,
          machineId: 'MACHINE-001', pipeDiameter: 160,
          material: 'PE100', sdr: '11', curve: curve, timestamp: ts,
        ),
        isTrue,
      );
    });

    test('verify() returns false when signature is tampered', () {
      final curve = _sampleCurve();
      final sig   = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11', curve: curve, timestamp: ts,
      );
      final tampered = '${sig.substring(0, 63)}0'; // flip last hex digit
      expect(
        WeldTraceSignature.verify(
          signature: tampered,
          machineId: 'MACHINE-001', pipeDiameter: 160,
          material: 'PE100', sdr: '11', curve: curve, timestamp: ts,
        ),
        isFalse,
      );
    });

    test('verify() with out-of-order curve still matches ordered hash', () {
      final ordered  = _sampleCurve();
      final reversed = ordered.reversed.toList();
      final sig      = WeldTraceSignature.generate(
        machineId: 'MACHINE-001', pipeDiameter: 160,
        material: 'PE100', sdr: '11', curve: ordered, timestamp: ts,
      );
      // verify() must also sort internally and match
      expect(
        WeldTraceSignature.verify(
          signature: sig,
          machineId: 'MACHINE-001', pipeDiameter: 160,
          material: 'PE100', sdr: '11', curve: reversed, timestamp: ts,
        ),
        isTrue,
        reason: 'verify() must sort the curve before recomputing the hash',
      );
    });
  });

  // ── WeldReportGenerator ─────────────────────────────────────────────────────

  group('WeldReportGenerator', () {
    const _fakeSig =
        'a3f1b2c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2';

    List<WeldTracePoint> _curve([int n = 30]) => List.generate(
          n,
          (i) => WeldTracePoint(
            timeSeconds: i.toDouble(),
            pressureBar: 0.10 + (i % 5) * 0.02,
            phase:       'Fusion Pressure',
          ),
        );

    // ── Basic validity ────────────────────────────────────────────────────────

    test('generate() returns non-empty bytes', () async {
      final bytes = await WeldReportGenerator.generate(
        projectName:   'Test Project',
        machineName:   'Ritmo Delta 160',
        diameter:      160,
        material:      'PE100',
        sdr:           '11',
        curve:         _curve(),
        weldSignature: _fakeSig,
        timestamp:     DateTime.utc(2025, 6, 15),
      );
      expect(bytes, isNotEmpty);
    });

    test('output starts with PDF magic bytes (%PDF)', () async {
      final bytes = await WeldReportGenerator.generate(
        projectName:   'Test Project',
        machineName:   'Ritmo Delta 160',
        diameter:      160,
        material:      'PE100',
        sdr:           '11',
        curve:         _curve(),
        weldSignature: _fakeSig,
        timestamp:     DateTime.utc(2025, 6, 15),
      );
      expect(String.fromCharCodes(bytes.sublist(0, 4)), equals('%PDF'));
    });

    // ── Edge-case curves ──────────────────────────────────────────────────────

    test('handles empty curve gracefully (no throw)', () async {
      await expectLater(
        WeldReportGenerator.generate(
          projectName:   'Empty Curve',
          machineName:   'Machine X',
          diameter:      110,
          material:      'PP',
          sdr:           '7.4',
          curve:         [],
          weldSignature: _fakeSig,
          timestamp:     DateTime.utc(2025, 1, 1),
        ),
        completes,
      );
    });

    test('handles single-sample curve without throw', () async {
      final bytes = await WeldReportGenerator.generate(
        projectName:   'Single Sample',
        machineName:   'Machine X',
        diameter:      110,
        material:      'PE80',
        sdr:           '17.6',
        curve:         [
          const WeldTracePoint(timeSeconds: 0, pressureBar: 0.15,
              phase: 'Fusion Pressure'),
        ],
        weldSignature: _fakeSig,
        timestamp:     DateTime.utc(2025, 3, 1),
      );
      expect(bytes, isNotEmpty);
    });

    // ── QR code ───────────────────────────────────────────────────────────────

    test('QR code section does not prevent PDF generation', () async {
      // The QR code painter draws the weld signature as a QR code.
      // If qr package or painter fails, the PDF must still be generated.
      final bytes = await WeldReportGenerator.generate(
        projectName:   'QR Test',
        machineName:   'Machine Y',
        diameter:      160,
        material:      'PE100',
        sdr:           '11',
        curve:         _curve(),
        weldSignature: _fakeSig,
        timestamp:     DateTime.utc(2025, 6, 15),
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), equals('%PDF'));
    });

    // ── Large curve ───────────────────────────────────────────────────────────

    test('generates valid PDF for maximum-size curve (5 000 samples)', () async {
      final largeCurve = List.generate(
        5000,
        (i) => WeldTracePoint(
          timeSeconds: i.toDouble(),
          pressureBar: 0.10 + (i % 10) * 0.01,
          phase:       i < 1000 ? 'Heating' : 'Fusion Pressure',
        ),
      );
      final bytes = await WeldReportGenerator.generate(
        projectName:   'Large Curve',
        machineName:   'Machine Z',
        diameter:      315,
        material:      'PE100',
        sdr:           '11',
        curve:         largeCurve,
        weldSignature: _fakeSig,
        timestamp:     DateTime.utc(2025, 9, 1),
      );
      expect(String.fromCharCodes(bytes.sublist(0, 4)), equals('%PDF'));
    });

    test('both short and long curves produce valid PDFs', () async {
      final shortBytes = await WeldReportGenerator.generate(
        projectName: 'Short', machineName: 'Machine',
        diameter: 160, material: 'PE100', sdr: '11',
        curve: _curve(5), weldSignature: _fakeSig,
        timestamp: DateTime.utc(2025, 6, 15),
      );
      final longBytes = await WeldReportGenerator.generate(
        projectName: 'Long', machineName: 'Machine',
        diameter: 160, material: 'PE100', sdr: '11',
        curve: _curve(200), weldSignature: _fakeSig,
        timestamp: DateTime.utc(2025, 6, 15),
      );
      expect(String.fromCharCodes(shortBytes.sublist(0, 4)), equals('%PDF'));
      expect(String.fromCharCodes(longBytes.sublist(0, 4)),  equals('%PDF'));
    });

    test('generates valid PDF with all extended metadata fields', () async {
      final bytes = await WeldReportGenerator.generate(
        projectName:       'Pipeline P-01',
        machineName:       'Ritmo Delta 160',
        machineId:         'MACH-001',
        diameter:          160,
        material:          'PE100',
        sdr:               '11',
        curve:             _curve(50),
        weldSignature:     _fakeSig,
        timestamp:         DateTime.utc(2025, 6, 15),
        operatorName:      'J. Silva',
        jointId:           'JNT-042',
        wallThicknessStr:  '14.6 mm',
        standardUsed:      'DVS 2207',
        fusionPressureBar: 0.153,
        heatingTimeSec:    190,
        coolingTimeSec:    180,
        beadHeightMm:      3.2,
      );
      expect(String.fromCharCodes(bytes.sublist(0, 4)), equals('%PDF'));
      expect(bytes.length, greaterThan(1024));
    });

    test('generates valid PDF with compressed curve (round-trip)', () async {
      final originalCurve = _curve(200);
      final json          = jsonEncode(originalCurve.map((p) => p.toJson()).toList());
      final compressed    = CurveCompression.compressCurve(json);
      final decompressed  = CurveCompression.decompressCurve(compressed);
      final restoredCurve = (jsonDecode(decompressed) as List)
          .map((e) => WeldTracePoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      final bytes = await WeldReportGenerator.generate(
        projectName:   'Compressed Curve',
        machineName:   'Machine A',
        diameter:      200,
        material:      'PE100',
        sdr:           '11',
        curve:         restoredCurve,
        weldSignature: _fakeSig,
        timestamp:     DateTime.utc(2025, 8, 1),
      );
      expect(String.fromCharCodes(bytes.sublist(0, 4)), equals('%PDF'));
    });
  });

  // ── WeldVerifier ────────────────────────────────────────────────────────────

  group('WeldVerifier', () {
    final ts      = DateTime.utc(2025, 6, 15, 8, 30);
    const machId  = 'MACH-001';
    const diam    = 160.0;
    const mat     = 'PE100';
    const sdrStr  = '11';

    List<WeldTracePoint> _buildCurve() => [
          const WeldTracePoint(timeSeconds: 0.0, pressureBar: 0.15, phase: 'Heating'),
          const WeldTracePoint(timeSeconds: 1.0, pressureBar: 0.16, phase: 'Heating'),
          const WeldTracePoint(timeSeconds: 2.0, pressureBar: 0.14, phase: 'Cooling'),
        ];

    String _sig([List<WeldTracePoint>? curve]) => WeldTraceSignature.generate(
          machineId:    machId,
          pipeDiameter: diam,
          material:     mat,
          sdr:          sdrStr,
          curve:        curve ?? _buildCurve(),
          timestamp:    ts,
        );

    // ── verifySignature ───────────────────────────────────────────────────────

    test('verifySignature returns true for correct inputs', () {
      final sig = _sig();
      expect(
        WeldVerifier.verifySignature(
          signature: sig,
          machineId: machId,
          diameter:  diam,
          material:  mat,
          sdr:       sdrStr,
          curve:     _buildCurve(),
          timestamp: ts,
        ),
        isTrue,
      );
    });

    test('verifySignature returns false when signature is tampered', () {
      final sig     = _sig();
      final tampered = sig.replaceRange(0, 2, 'xx');
      expect(
        WeldVerifier.verifySignature(
          signature: tampered,
          machineId: machId,
          diameter:  diam,
          material:  mat,
          sdr:       sdrStr,
          curve:     _buildCurve(),
          timestamp: ts,
        ),
        isFalse,
      );
    });

    test('verifySignature returns false when curve is altered', () {
      final sig = _sig();
      final alteredCurve = [
        const WeldTracePoint(timeSeconds: 0.0, pressureBar: 0.99, phase: 'Heating'),
        const WeldTracePoint(timeSeconds: 1.0, pressureBar: 0.16, phase: 'Heating'),
        const WeldTracePoint(timeSeconds: 2.0, pressureBar: 0.14, phase: 'Cooling'),
      ];
      expect(
        WeldVerifier.verifySignature(
          signature: sig,
          machineId: machId,
          diameter:  diam,
          material:  mat,
          sdr:       sdrStr,
          curve:     alteredCurve,
          timestamp: ts,
        ),
        isFalse,
      );
    });

    test('verifySignature returns false when machineId changes', () {
      final sig = _sig();
      expect(
        WeldVerifier.verifySignature(
          signature: sig,
          machineId: 'OTHER-MACHINE',
          diameter:  diam,
          material:  mat,
          sdr:       sdrStr,
          curve:     _buildCurve(),
          timestamp: ts,
        ),
        isFalse,
      );
    });

    // ── buildVerificationPayload (optimised — < 200 chars) ───────────────────

    test('buildVerificationPayload produces valid JSON', () {
      final json = WeldVerifier.buildVerificationPayload(
        jointId:   'joint-001',
        signature: _fakeSig,
      );
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('buildVerificationPayload contains required keys', () {
      final json    = WeldVerifier.buildVerificationPayload(
        jointId:   'joint-001',
        signature: _fakeSig,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['app'],    equals('WeldTrace'));
      expect(decoded['v'],      equals(1));
      expect(decoded['joint'],  equals('joint-001'));
      expect(decoded['sig'],    equals(_fakeSig));
      expect(decoded['verify'], equals('registry'),
          reason: 'QR payload must instruct scanners to cross-check the registry');
    });

    test('buildVerificationPayload stays under 200 characters', () {
      final json = WeldVerifier.buildVerificationPayload(
        jointId:   '018f4e5a-1b2c-7d3e-9a4b-5c6d7e8f9a0b',
        signature: _fakeSig,
      );
      expect(json.length, lessThan(200),
          reason: 'QR payload must fit within QR capacity at ECL-M');
    });

    test('buildVerificationPayload is deterministic for same inputs', () {
      final a = WeldVerifier.buildVerificationPayload(
        jointId: 'jnt-1', signature: _fakeSig);
      final b = WeldVerifier.buildVerificationPayload(
        jointId: 'jnt-1', signature: _fakeSig);
      expect(a, equals(b));
    });

    // ── parsePayload ──────────────────────────────────────────────────────────

    test('parsePayload returns valid map for correct WeldTrace payload', () {
      final json   = WeldVerifier.buildVerificationPayload(
        jointId: 'jnt-42', signature: _fakeSig);
      final parsed = WeldVerifier.parsePayload(json);
      expect(parsed, isNotNull);
      expect(parsed!['app'],   equals('WeldTrace'));
      expect(parsed['joint'],  equals('jnt-42'));
      expect(parsed['sig'],    equals(_fakeSig));
    });

    test('parsePayload returns null for invalid JSON', () {
      expect(WeldVerifier.parsePayload('not-valid-json'), isNull);
    });

    test('parsePayload returns null for non-WeldTrace payload', () {
      final other = jsonEncode({'app': 'SomeOtherApp', 'v': 1});
      expect(WeldVerifier.parsePayload(other), isNull);
    });

    test('parsePayload returns null for wrong version', () {
      final payload = jsonEncode({'app': 'WeldTrace', 'v': 99});
      expect(WeldVerifier.parsePayload(payload), isNull);
    });
  });
}
