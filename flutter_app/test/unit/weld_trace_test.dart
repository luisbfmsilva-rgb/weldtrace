import 'package:flutter_test/flutter_test.dart';

import 'package:weldtrace/services/welding_trace/weld_trace_recorder.dart';
import 'package:weldtrace/services/welding_trace/weld_trace_signature.dart';
import 'package:weldtrace/services/welding_trace/weld_report_generator.dart';

void main() {
  // ── WeldTraceRecorder ───────────────────────────────────────────────────────

  group('WeldTraceRecorder', () {
    test('starts with empty curve', () {
      final recorder = WeldTraceRecorder();
      expect(recorder.points, isEmpty);
      expect(recorder.isStarted, isFalse);
    });

    test('record() is a no-op before start()', () {
      final recorder = WeldTraceRecorder();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      expect(recorder.points, isEmpty);
    });

    test('points accumulate after start()', () {
      final recorder = WeldTraceRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      recorder.record(pressureBar: 0.14, phase: 'Fusion Pressure');
      expect(recorder.points.length, equals(2));
    });

    test('timeSeconds increases monotonically', () {
      final recorder = WeldTraceRecorder();
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

    test('export() works on empty curve (< 10 samples)', () {
      final recorder = WeldTraceRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      recorder.record(pressureBar: 0.14, phase: 'Fusion Pressure');
      final curve = recorder.export();
      expect(curve.length, equals(2));
    });

    test('export() on unstarted recorder returns empty list', () {
      final recorder = WeldTraceRecorder();
      expect(recorder.export(), isEmpty);
    });

    test('start() clears previous recording', () {
      final recorder = WeldTraceRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.15, phase: 'Fusion Pressure');
      recorder.record(pressureBar: 0.20, phase: 'Cooling');
      expect(recorder.points.length, equals(2));

      // Second start clears everything
      recorder.start();
      expect(recorder.points, isEmpty);
    });

    test('maxPressureBar returns correct maximum', () {
      final recorder = WeldTraceRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.10, phase: 'Heating');
      recorder.record(pressureBar: 0.25, phase: 'Fusion Pressure');
      recorder.record(pressureBar: 0.18, phase: 'Cooling');
      expect(recorder.maxPressureBar, closeTo(0.25, 1e-6));
    });

    test('averagePressureBar returns correct mean', () {
      final recorder = WeldTraceRecorder();
      recorder.start();
      recorder.record(pressureBar: 0.10, phase: 'Heating');
      recorder.record(pressureBar: 0.20, phase: 'Fusion Pressure');
      // avg = (0.10 + 0.20) / 2 = 0.15
      expect(recorder.averagePressureBar, closeTo(0.15, 1e-6));
    });

    test('maxPressureBar returns 0 on empty curve', () {
      final recorder = WeldTraceRecorder();
      expect(recorder.maxPressureBar, equals(0));
    });

    test('WeldTracePoint serialisation round-trip', () {
      const point = WeldTracePoint(
        timeSeconds: 12.5,
        pressureBar: 0.175,
        phase:       'Fusion Pressure',
      );
      final json       = point.toJson();
      final deserialsed = WeldTracePoint.fromJson(json);
      expect(deserialsed.timeSeconds, closeTo(12.5,  1e-9));
      expect(deserialsed.pressureBar, closeTo(0.175, 1e-9));
      expect(deserialsed.phase, equals('Fusion Pressure'));
    });
  });

  // ── WeldTraceSignature ──────────────────────────────────────────────────────

  group('WeldTraceSignature', () {
    /// Shared fixed timestamp so determinism tests are stable.
    final ts = DateTime.utc(2025, 6, 15, 8, 30, 0);

    List<WeldTracePoint> _sampleCurve() => [
          const WeldTracePoint(timeSeconds: 0,   pressureBar: 0.15, phase: 'Heating-up'),
          const WeldTracePoint(timeSeconds: 30,  pressureBar: 0.02, phase: 'Heat Soak'),
          const WeldTracePoint(timeSeconds: 100, pressureBar: 0.15, phase: 'Fusion Pressure'),
          const WeldTracePoint(timeSeconds: 130, pressureBar: 0.15, phase: 'Cooling'),
        ];

    test('returns a 64-character hex string (SHA-256)', () {
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

    test('is deterministic — same inputs produce same hash', () {
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

    test('different machine ID → different hash', () {
      final sig1 = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        _sampleCurve(),
        timestamp:    ts,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId:    'MACHINE-002',  // changed
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        _sampleCurve(),
        timestamp:    ts,
      );
      expect(sig1, isNot(equals(sig2)));
    });

    test('different curve → different hash', () {
      final curve1 = _sampleCurve();
      final curve2 = [
        ...curve1,
        // tampered: one additional sample at higher pressure
        const WeldTracePoint(timeSeconds: 200, pressureBar: 0.99, phase: 'Cooling'),
      ];
      final sig1 = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        curve1,
        timestamp:    ts,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        curve2,
        timestamp:    ts,
      );
      expect(sig1, isNot(equals(sig2)));
    });

    test('different timestamp → different hash', () {
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
        timestamp:    ts.add(const Duration(seconds: 1)),
      );
      expect(sig1, isNot(equals(sig2)));
    });

    test('empty curve produces valid (deterministic) hash', () {
      final sig1 = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        [],
        timestamp:    ts,
      );
      final sig2 = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        [],
        timestamp:    ts,
      );
      expect(sig1.length, equals(64));
      expect(sig1, equals(sig2));
    });

    test('verify() returns true for matching inputs', () {
      final curve = _sampleCurve();
      final sig   = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        curve,
        timestamp:    ts,
      );
      expect(
        WeldTraceSignature.verify(
          signature:    sig,
          machineId:    'MACHINE-001',
          pipeDiameter: 160,
          material:     'PE100',
          sdr:          '11',
          curve:        curve,
          timestamp:    ts,
        ),
        isTrue,
      );
    });

    test('verify() returns false when signature is tampered', () {
      final curve = _sampleCurve();
      final sig   = WeldTraceSignature.generate(
        machineId:    'MACHINE-001',
        pipeDiameter: 160,
        material:     'PE100',
        sdr:          '11',
        curve:        curve,
        timestamp:    ts,
      );
      final tampered = '${sig.substring(0, 63)}0'; // flip last char
      expect(
        WeldTraceSignature.verify(
          signature:    tampered,
          machineId:    'MACHINE-001',
          pipeDiameter: 160,
          material:     'PE100',
          sdr:          '11',
          curve:        curve,
          timestamp:    ts,
        ),
        isFalse,
      );
    });
  });

  // ── WeldReportGenerator ─────────────────────────────────────────────────────

  group('WeldReportGenerator', () {
    const _fakeSig =
        'a3f1b2c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2';

    List<WeldTracePoint> _curve() => List.generate(
          30,
          (i) => WeldTracePoint(
            timeSeconds: i.toDouble(),
            pressureBar: 0.10 + (i % 5) * 0.02,
            phase:       'Fusion Pressure',
          ),
        );

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

    test('generate() output starts with PDF magic bytes (%PDF)', () async {
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
      // PDF files always start with the ASCII sequence "%PDF"
      final header = String.fromCharCodes(bytes.sublist(0, 4));
      expect(header, equals('%PDF'));
    });

    test('generate() handles empty curve gracefully (no throws)', () async {
      expect(
        () async => WeldReportGenerator.generate(
          projectName:   'Empty Curve Test',
          machineName:   'Machine X',
          diameter:      110,
          material:      'PP',
          sdr:           '7.4',
          curve:         [],
          weldSignature: _fakeSig,
          timestamp:     DateTime.utc(2025, 1, 1),
        ),
        returnsNormally,
      );
    });

    test('generate() with single sample does not throw', () async {
      final bytes = await WeldReportGenerator.generate(
        projectName:   'Single Sample',
        machineName:   'Machine X',
        diameter:      110,
        material:      'PE80',
        sdr:           '17.6',
        curve:         [
          const WeldTracePoint(
              timeSeconds: 0, pressureBar: 0.15, phase: 'Fusion Pressure'),
        ],
        weldSignature: _fakeSig,
        timestamp:     DateTime.utc(2025, 3, 1),
      );
      expect(bytes, isNotEmpty);
    });

    test('generate() produces a larger report for a longer curve', () async {
      final shortCurve = List.generate(
        5,
        (i) => WeldTracePoint(
          timeSeconds: i.toDouble(),
          pressureBar: 0.15,
          phase:       'Fusion Pressure',
        ),
      );
      final longCurve = List.generate(
        200,
        (i) => WeldTracePoint(
          timeSeconds: i.toDouble(),
          pressureBar: 0.10 + (i % 10) * 0.01,
          phase:       'Fusion Pressure',
        ),
      );

      final shortBytes = await WeldReportGenerator.generate(
        projectName:   'Short',
        machineName:   'Machine',
        diameter:      160,
        material:      'PE100',
        sdr:           '11',
        curve:         shortCurve,
        weldSignature: _fakeSig,
        timestamp:     DateTime.utc(2025, 6, 15),
      );
      final longBytes = await WeldReportGenerator.generate(
        projectName:   'Long',
        machineName:   'Machine',
        diameter:      160,
        material:      'PE100',
        sdr:           '11',
        curve:         longCurve,
        weldSignature: _fakeSig,
        timestamp:     DateTime.utc(2025, 6, 15),
      );

      // Both must be valid PDFs
      expect(String.fromCharCodes(shortBytes.sublist(0, 4)), equals('%PDF'));
      expect(String.fromCharCodes(longBytes.sublist(0, 4)), equals('%PDF'));
    });
  });
}
