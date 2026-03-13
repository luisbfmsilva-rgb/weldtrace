import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weldtrace/services/standards/dvs_2207.dart';
import 'package:weldtrace/services/standards/iso_21307.dart';
import 'package:weldtrace/services/standards/astm_f2620.dart';
import 'package:weldtrace/services/welding/welding_table_generator.dart';
import 'package:weldtrace/services/welding/pipe_spec.dart';

/// Shared test pipe: OD 160 mm, SDR 11, wall ≈ 14.5 mm.
const _od     = 160.0;
const _sdrStr = '11';
const _sdr    = 11.0;

/// Machine with a known cylinder area (1 000 mm² piston).
const _cylinderAreaMm2 = 1000.0;
const _dragBar         = 0.2;

void main() {
  // ── DVS 2207-1 ──────────────────────────────────────────────────────────────

  group('DVS 2207-1 fallback', () {
    test('companion has required pressure fields', () {
      final companion = Dvs2207.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE100',
      );

      // Wall thickness must be computed and stored
      expect(companion.wallThicknessMm.present, isTrue);
      expect(companion.wallThicknessMm.value, closeTo(_od / _sdr, 0.01));

      // Fusion pressure must be present and positive
      expect(companion.fusionPressureBar.present, isTrue);
      expect(companion.fusionPressureBar.value, greaterThan(0));

      // Tolerance band must be ordered correctly
      final nom = companion.fusionPressureBar.value!;
      expect(companion.fusionPressureMinBar.value!, lessThan(nom));
      expect(companion.fusionPressureMaxBar.value!, greaterThan(nom));
    });

    test('PE100 fusion pressure > PE80 baseline (material correction)', () {
      final pe80 = Dvs2207.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );
      final pe100 = Dvs2207.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE100',
      );

      expect(
        pe100.fusionPressureBar.value!,
        greaterThan(pe80.fusionPressureBar.value!),
      );
    });

    test('PP fusion pressure < PE80 baseline (material correction)', () {
      final pe80 = Dvs2207.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );
      final pp = Dvs2207.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PP',
      );

      expect(
        pp.fusionPressureBar.value!,
        lessThan(pe80.fusionPressureBar.value!),
      );
    });

    test('heat soak time scales with diameter', () {
      final small = Dvs2207.generateFallback(
        pipeDiameterMm: 63,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );
      final large = Dvs2207.generateFallback(
        pipeDiameterMm: 315,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );

      expect(
        large.heatingTimeS.value!,
        greaterThan(small.heatingTimeS.value!),
      );
    });

    test('cooling time scales with wall thickness', () {
      final thinWall = Dvs2207.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      '26', // thinner wall
        pipeMaterial:   'PE80',
      );
      final thickWall = Dvs2207.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      '7.4', // thicker wall
        pipeMaterial:   'PE80',
      );

      expect(
        thickWall.coolingTimeS.value!,
        greaterThan(thinWall.coolingTimeS.value!),
      );
    });

    test('full pipeline — phases exist and machine pressure ≥ 0', () {
      final companion = Dvs2207.generateFallback(
        pipeDiameterMm:           _od,
        sdrRating:                _sdrStr,
        pipeMaterial:             'PE100',
        hydraulicCylinderAreaMm2: _cylinderAreaMm2,
        dragPressureBar:          _dragBar,
      );

      final record = WeldingTableGenerator.companionToRecord(
        companion:  companion,
        id:         'test-dvs-pe100-160-11',
        standardId: 'DVS_2207',
      );

      final pipeSpec    = PipeSpec(
        outerDiameterMm: _od,
        sdrRatio:        _sdr,
        material:        'PE100',
      );
      final machineSpec = MachineSpec(
        hydraulicCylinderAreaMm2: _cylinderAreaMm2,
        dragPressureBar:          _dragBar,
      );

      final table = WeldingTableGenerator.generate(
        record:      record,
        pipeSpec:    pipeSpec,
        machineSpec: machineSpec,
        weldType:    'butt_fusion',
      );

      // Must have all 6 butt-fusion phases
      expect(table.phases.length, equals(6));

      // No phase pressure may be negative
      for (final phase in table.phases) {
        if (phase.nominalPressureBar != null) {
          expect(
            phase.nominalPressureBar!,
            greaterThanOrEqualTo(0),
            reason: 'Phase ${phase.phase} has negative nominal pressure',
          );
        }
        if (phase.minPressureBar != null) {
          expect(
            phase.minPressureBar!,
            greaterThanOrEqualTo(0),
            reason: 'Phase ${phase.phase} has negative min pressure',
          );
        }
      }

      // Row pressures must be non-negative when machine data present
      expect(table.row.isMachinePressure, isTrue);
      if (table.row.fusionPressureBar != null) {
        expect(table.row.fusionPressureBar!, greaterThanOrEqualTo(0));
      }
    });
  });

  // ── ISO 21307 ───────────────────────────────────────────────────────────────

  group('ISO 21307 fallback', () {
    test('low-pressure companion has fusion pressure present', () {
      final companion = Iso21307.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
        mode:           Iso21307Mode.lowPressure,
      );

      expect(companion.fusionPressureBar.present, isTrue);
      expect(companion.fusionPressureBar.value!, greaterThan(0));
    });

    test('high-pressure fusion > low-pressure fusion', () {
      final low = Iso21307.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
        mode:           Iso21307Mode.lowPressure,
      );
      final high = Iso21307.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
        mode:           Iso21307Mode.highPressure,
      );

      expect(
        high.fusionPressureBar.value!,
        greaterThan(low.fusionPressureBar.value!),
      );
    });

    test('full pipeline (high-pressure) — phases exist and pressures ≥ 0', () {
      final companion = Iso21307.generateFallback(
        pipeDiameterMm:           _od,
        sdrRating:                _sdrStr,
        pipeMaterial:             'PE80',
        mode:                     Iso21307Mode.highPressure,
        hydraulicCylinderAreaMm2: _cylinderAreaMm2,
        dragPressureBar:          _dragBar,
      );

      final record = WeldingTableGenerator.companionToRecord(
        companion:  companion,
        id:         'test-iso-pe80-160-11',
        standardId: 'ISO_21307',
      );

      final table = WeldingTableGenerator.generate(
        record:      record,
        pipeSpec:    PipeSpec(
          outerDiameterMm: _od,
          sdrRatio:        _sdr,
          material:        'PE80',
        ),
        machineSpec: MachineSpec(
          hydraulicCylinderAreaMm2: _cylinderAreaMm2,
          dragPressureBar:          _dragBar,
        ),
        weldType: 'butt_fusion',
      );

      expect(table.phases.length, equals(6));
      expect(table.row.isMachinePressure, isTrue);

      for (final phase in table.phases) {
        if (phase.nominalPressureBar != null) {
          expect(phase.nominalPressureBar!, greaterThanOrEqualTo(0));
        }
      }
    });
  });

  // ── ASTM F2620 ──────────────────────────────────────────────────────────────

  group('ASTM F2620 fallback', () {
    test('companion has higher base pressure than DVS 2207 for same pipe', () {
      final dvs = Dvs2207.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );
      final astm = AstmF2620.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );

      expect(
        astm.fusionPressureBar.value!,
        greaterThan(dvs.fusionPressureBar.value!),
      );
    });

    test('full pipeline — phases exist and pressures ≥ 0', () {
      final companion = AstmF2620.generateFallback(
        pipeDiameterMm:           _od,
        sdrRating:                _sdrStr,
        pipeMaterial:             'HDPE',
        hydraulicCylinderAreaMm2: _cylinderAreaMm2,
        dragPressureBar:          _dragBar,
      );

      final record = WeldingTableGenerator.companionToRecord(
        companion:  companion,
        id:         'test-astm-hdpe-160-11',
        standardId: 'ASTM_F2620',
      );

      final table = WeldingTableGenerator.generate(
        record:      record,
        pipeSpec:    PipeSpec(
          outerDiameterMm: _od,
          sdrRatio:        _sdr,
          material:        'HDPE',
        ),
        machineSpec: MachineSpec(
          hydraulicCylinderAreaMm2: _cylinderAreaMm2,
          dragPressureBar:          _dragBar,
        ),
        weldType: 'butt_fusion',
      );

      expect(table.phases.length, equals(6));
      expect(table.row.isMachinePressure, isTrue);

      for (final phase in table.phases) {
        if (phase.nominalPressureBar != null) {
          expect(phase.nominalPressureBar!, greaterThanOrEqualTo(0));
        }
      }
    });
  });

  // ── generateFallbackForStandard dispatcher ──────────────────────────────────

  group('generateFallbackForStandard dispatcher', () {
    test('routes DVS_2207 to Dvs2207 engine', () {
      final dvsDirect = Dvs2207.generateFallback(
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );
      final dvsDispatch = WeldingTableGenerator.generateFallbackForStandard(
        standardId:     'DVS_2207',
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );

      // Both paths should agree on the fusion pressure
      expect(
        dvsDispatch.fusionPressureBar.value,
        closeTo(dvsDirect.fusionPressureBar.value!, 0.001),
      );
    });

    test('routes ASTM_F2620 to AstmF2620 engine', () {
      final companion = WeldingTableGenerator.generateFallbackForStandard(
        standardId:     'ASTM_F2620',
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );
      expect(companion.fusionPressureBar.present, isTrue);
      expect(companion.fusionPressureBar.value!, greaterThan(0));
    });

    test('routes unknown ID to DVS 2207 (conservative fallback)', () {
      final unknown = WeldingTableGenerator.generateFallbackForStandard(
        standardId:     'CUSTOM_STANDARD',
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );
      final dvs = WeldingTableGenerator.generateFallbackForStandard(
        standardId:     'DVS_2207',
        pipeDiameterMm: _od,
        sdrRating:      _sdrStr,
        pipeMaterial:   'PE80',
      );

      expect(
        unknown.fusionPressureBar.value!,
        closeTo(dvs.fusionPressureBar.value!, 0.001),
      );
    });
  });

  // ── No negative gauge pressure edge case ───────────────────────────────────

  group('gauge pressure edge cases', () {
    test('gauge pressure is never negative even with large drag', () {
      final companion = Dvs2207.generateFallback(
        pipeDiameterMm:           _od,
        sdrRating:                _sdrStr,
        pipeMaterial:             'PE80',
        hydraulicCylinderAreaMm2: 50000.0, // very large cylinder → low machine P
        dragPressureBar:          100.0,   // exaggerated drag
      );

      final record = WeldingTableGenerator.companionToRecord(
        companion:  companion,
        id:         'test-dvs-edge',
        standardId: 'DVS_2207',
      );

      final table = WeldingTableGenerator.generate(
        record:      record,
        pipeSpec:    PipeSpec(
          outerDiameterMm: _od,
          sdrRatio:        _sdr,
          material:        'PE80',
        ),
        machineSpec: MachineSpec(
          hydraulicCylinderAreaMm2: 50000.0,
          dragPressureBar:          100.0,
        ),
        weldType: 'butt_fusion',
      );

      for (final phase in table.phases) {
        if (phase.nominalPressureBar != null) {
          expect(
            phase.nominalPressureBar!,
            greaterThanOrEqualTo(0),
            reason: 'Large-drag edge case produced negative pressure',
          );
        }
      }
    });
  });

  // ── Contact area model (beadContactFactor = 0.65) ──────────────────────────

  group('contact area model', () {
    /// All tests in this group use debugCalculation() — pure Dart, no Drift.

    test('contact area uses beadContactFactor 0.65', () {
      const od  = 160.0;
      const sdr = 11.0;
      final e          = od / sdr;
      final beadWidth  = e * 0.9;
      final expected   = math.pi * od * 0.65 * beadWidth;

      final dbg = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           od,
        wallThicknessMm:          e,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: 1000,
      );

      expect(dbg['contactArea']!, closeTo(expected, 0.5));
    });

    test('contact area is smaller than full-circumference assumption', () {
      const od  = 160.0;
      const e   = 160.0 / 11.0;
      final beadWidth       = e * 0.9;
      final fullCircArea    = math.pi * od * beadWidth;
      final reducedCircArea =
          WeldingTableGenerator.debugCalculation(
            pipeDiameterMm:           od,
            wallThicknessMm:          e,
            interfacialPressureBar:   0.15,
            hydraulicCylinderAreaMm2: 1000,
          )['contactArea']!;

      expect(reducedCircArea, lessThan(fullCircArea));
    });

    test('contact area scales with pipe diameter for large pipes', () {
      final smallPipe = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           160,
        wallThicknessMm:          160 / 11.0,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: 1000,
      )['contactArea']!;

      final largePipe = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           315,
        wallThicknessMm:          315 / 11.0,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: 1000,
      )['contactArea']!;

      expect(largePipe, greaterThan(smallPipe));
    });

    test('contact area is clamped to minimum 100 mm² for micro pipes', () {
      // Pipe too small to weld in practice — clamp must floor at 100 mm².
      final dbg = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           5,
        wallThicknessMm:          0.1,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: 1000,
      );
      expect(dbg['contactArea']!, greaterThanOrEqualTo(100.0));
    });
  });

  // ── Machine pressure scaling with cylinder area ────────────────────────────

  group('machine pressure scaling', () {
    test('machine pressure increases when cylinder area decreases', () {
      const od  = 160.0;
      const e   = 160.0 / 11.0;

      final smallCylinder = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           od,
        wallThicknessMm:          e,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: 500,   // smaller cylinder
      )['machinePressure']!;

      final largeCylinder = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           od,
        wallThicknessMm:          e,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: 5000,  // larger cylinder
      )['machinePressure']!;

      expect(smallCylinder, greaterThan(largeCylinder));
    });

    test('machine pressure is proportional to interfacial pressure', () {
      const od  = 160.0;
      const e   = 160.0 / 11.0;
      const cyl = 1000.0;

      final lowP = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           od,
        wallThicknessMm:          e,
        interfacialPressureBar:   0.10,
        hydraulicCylinderAreaMm2: cyl,
      )['machinePressure']!;

      final highP = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           od,
        wallThicknessMm:          e,
        interfacialPressureBar:   0.25,
        hydraulicCylinderAreaMm2: cyl,
      )['machinePressure']!;

      expect(highP, greaterThan(lowP));
      // Linearity check — ratio should be ≈ 2.5×
      expect(highP / lowP, closeTo(2.5, 0.05));
    });
  });

  // ── Drag pressure compensation ─────────────────────────────────────────────

  group('drag pressure compensation', () {
    test('gauge pressure = machine pressure minus drag', () {
      const od  = 160.0;
      const e   = 160.0 / 11.0;
      const cyl = 1000.0;

      final noDrag = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           od,
        wallThicknessMm:          e,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: cyl,
        dragPressureBar:          0.0,
      )['machinePressure']!;

      final withDrag = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           od,
        wallThicknessMm:          e,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: cyl,
        dragPressureBar:          0.5,
      )['machinePressure']!;

      expect(withDrag, lessThan(noDrag));
    });

    test('gauge pressure is clamped to zero when drag exceeds machine pressure', () {
      final dbg = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           160,
        wallThicknessMm:          160 / 11.0,
        interfacialPressureBar:   0.001,   // tiny interfacial → tiny force
        hydraulicCylinderAreaMm2: 100000,  // enormous cylinder → tiny machine P
        dragPressureBar:          999,     // absurd drag
      );
      expect(dbg['machinePressure']!, equals(0.0));
    });
  });

  // ── Large diameter pipes (315+ mm) ─────────────────────────────────────────

  group('large diameter pipes (315+ mm)', () {
    test('DVS companion generates correct wall thickness for OD=315 SDR=11', () {
      final companion = Dvs2207.generateFallback(
        pipeDiameterMm: 315,
        sdrRating:      '11',
        pipeMaterial:   'PE100',
      );
      // e = 315/11 ≈ 28.64 mm
      expect(companion.wallThicknessMm.value!, closeTo(315 / 11, 0.01));
    });

    test('large pipe produces higher fusion force than small pipe', () {
      final small = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           160,
        wallThicknessMm:          160 / 11.0,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: 1000,
      )['fusionForce']!;

      final large = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           315,
        wallThicknessMm:          315 / 11.0,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: 1000,
      )['fusionForce']!;

      expect(large, greaterThan(small));
    });

    test('OD=630 SDR=17.6 (thick-wall transmission) — all companion fields present', () {
      final companion = Dvs2207.generateFallback(
        pipeDiameterMm:           630,
        sdrRating:                '17.6',
        pipeMaterial:             'PE100',
        hydraulicCylinderAreaMm2: 5000,
        dragPressureBar:          0.3,
      );
      expect(companion.fusionPressureBar.present, isTrue);
      expect(companion.heatingTimeS.present,      isTrue);
      expect(companion.coolingTimeS.present,      isTrue);
      expect(companion.wallThicknessMm.present,   isTrue);

      // e = 630/17.6 ≈ 35.8 mm
      expect(
        companion.wallThicknessMm.value!,
        closeTo(630 / 17.6, 0.1),
      );
    });

    test('debugCalculation for OD=630 returns all five keys', () {
      final dbg = WeldingTableGenerator.debugCalculation(
        pipeDiameterMm:           630,
        wallThicknessMm:          630 / 17.6,
        interfacialPressureBar:   0.15,
        hydraulicCylinderAreaMm2: 5000,
        dragPressureBar:          0.3,
      );
      expect(dbg.containsKey('wallThickness'),   isTrue);
      expect(dbg.containsKey('beadWidth'),       isTrue);
      expect(dbg.containsKey('contactArea'),     isTrue);
      expect(dbg.containsKey('fusionForce'),     isTrue);
      expect(dbg.containsKey('machinePressure'), isTrue);

      // All values must be non-negative
      for (final v in dbg.values) {
        expect(v, greaterThanOrEqualTo(0));
      }
    });
  });
}
