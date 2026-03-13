import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:weldtrace/services/welding_trace/weld_certificate.dart';
import 'package:weldtrace/services/welding_trace/weld_registry.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

String _fakeSig([String char = 'a']) => List.filled(64, char).join();
String _fakeHash([String char = 'b']) => List.filled(64, char).join();

Directory _tmpDir() =>
    Directory.systemTemp.createTempSync('weld_certificate_test_');

WeldCertificate _cert({
  String  jointId      = 'joint-001',
  String? signature,
  String  machineId    = 'M-01',
  double  diameter     = 160.0,
  String  material     = 'PE100',
  String  sdr          = '11',
  String  traceQuality = 'OK',
  double? fusionPressure,
  double? heatingTime,
  double? coolingTime,
  double? beadHeight,
  String? pdfHash,
}) =>
    WeldCertificate(
      jointId:       jointId,
      signature:     signature ?? _fakeSig(),
      timestamp:     DateTime.utc(2025, 6, 15, 8, 30),
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

WeldRegistryEntry _registryEntry({
  String jointId   = 'joint-001',
  String? signature,
  String sdr       = '11',
}) =>
    WeldRegistryEntry(
      jointId:   jointId,
      signature: signature ?? _fakeSig(),
      timestamp: DateTime.utc(2025, 6, 15, 8, 30),
      machineId: 'M-01',
      diameter:  160.0,
      material:  'PE100',
      sdr:       sdr,
    );

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // ── certificate_roundtrip ───────────────────────────────────────────────────

  group('certificate_roundtrip', () {
    test('toJson / fromJson preserves all required fields', () {
      final cert    = _cert();
      final decoded = WeldCertificate.fromJson(cert.toJson());

      expect(decoded.jointId,      equals(cert.jointId));
      expect(decoded.signature,    equals(cert.signature));
      expect(decoded.machineId,    equals(cert.machineId));
      expect(decoded.diameter,     closeTo(cert.diameter, 0.001));
      expect(decoded.material,     equals(cert.material));
      expect(decoded.sdr,          equals(cert.sdr));
      expect(decoded.traceQuality, equals(cert.traceQuality));
      expect(
        decoded.timestamp.millisecondsSinceEpoch,
        equals(cert.timestamp.millisecondsSinceEpoch),
      );
    });

    test('toJson / fromJson preserves optional fields', () {
      final cert = _cert(
        fusionPressure: 1.5,
        heatingTime:    150.0,
        coolingTime:    180.0,
        beadHeight:     3.2,
        pdfHash:        _fakeHash(),
      );
      final decoded = WeldCertificate.fromJson(cert.toJson());

      expect(decoded.fusionPressure, closeTo(1.5,   0.001));
      expect(decoded.heatingTime,    closeTo(150.0, 0.001));
      expect(decoded.coolingTime,    closeTo(180.0, 0.001));
      expect(decoded.beadHeight,     closeTo(3.2,   0.001));
      expect(decoded.pdfHash,        equals(_fakeHash()));
    });

    test('null optional fields round-trip as null', () {
      final cert    = _cert(); // no optional fields
      final decoded = WeldCertificate.fromJson(cert.toJson());

      expect(decoded.fusionPressure, isNull);
      expect(decoded.heatingTime,    isNull);
      expect(decoded.coolingTime,    isNull);
      expect(decoded.beadHeight,     isNull);
      expect(decoded.pdfHash,        isNull);
    });

    test('timestamp is serialised as UTC ISO-8601 ending in Z', () {
      final json = _cert().toJson();
      expect(json['timestamp'], endsWith('Z'));
    });

    test('toJson emits keys in canonical order', () {
      final json = _cert().toJson();
      final keys  = json.keys.toList();
      const expected = [
        'jointId', 'signature', 'timestamp', 'machineId',
        'diameter', 'material', 'sdr', 'traceQuality',
        'fusionPressure', 'heatingTime', 'coolingTime', 'beadHeight', 'pdfHash',
      ];
      expect(keys, equals(expected),
          reason: 'JSON key order must match the canonical schema');
    });

    test('serialised JSON is valid and parseable', () {
      final raw = jsonEncode(_cert().toJson());
      expect(() => jsonDecode(raw), returnsNormally);
    });

    test('generateCertificate factory produces identical result to constructor',
        () {
      final via_ctor = _cert(pdfHash: _fakeHash('c'));
      final via_factory = WeldCertificate.generateCertificate(
        jointId:       via_ctor.jointId,
        signature:     via_ctor.signature,
        timestamp:     via_ctor.timestamp,
        machineId:     via_ctor.machineId,
        diameter:      via_ctor.diameter,
        material:      via_ctor.material,
        sdr:           via_ctor.sdr,
        traceQuality:  via_ctor.traceQuality,
        pdfHash:       via_ctor.pdfHash,
      );

      expect(via_factory.toJson(), equals(via_ctor.toJson()));
    });

    test('round-trip is deterministic (two calls produce same JSON)', () {
      final cert = _cert(pdfHash: _fakeHash());
      expect(jsonEncode(cert.toJson()), equals(jsonEncode(cert.toJson())));
    });

    test('exportCertificate writes {jointId}.certificate.json', () async {
      final dir  = _tmpDir();
      final reg  = p.join(dir.path, 'registry_export.json');
      final out  = dir.path;

      await WeldRegistry.append(_registryEntry(), registryPath: reg);
      final file = await WeldCertificate.exportCertificate(
        'joint-001',
        registryPath: reg,
        outputDir:    out,
      );

      expect(file.existsSync(), isTrue);
      expect(p.basename(file.path), equals('joint-001.certificate.json'));
      dir.deleteSync(recursive: true);
    });

    test('exportCertificate file contains valid JSON', () async {
      final dir = _tmpDir();
      final reg = p.join(dir.path, 'registry_export.json');
      final out = dir.path;

      await WeldRegistry.append(_registryEntry(), registryPath: reg);
      final file = await WeldCertificate.exportCertificate(
        'joint-001',
        registryPath: reg,
        outputDir:    out,
      );

      final raw  = file.readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['jointId'], equals('joint-001'));
      dir.deleteSync(recursive: true);
    });

    test('exportCertificate throws StateError for unknown jointId', () async {
      final dir = _tmpDir();
      final reg = p.join(dir.path, 'registry_export.json');
      final out = dir.path;

      expect(
        () => WeldCertificate.exportCertificate(
          'not-in-registry',
          registryPath: reg,
          outputDir:    out,
        ),
        throwsA(isA<StateError>()),
      );
      dir.deleteSync(recursive: true);
    });
  });

  // ── certificate_hash_validation ─────────────────────────────────────────────

  group('certificate_hash_validation', () {
    test('computePdfHash returns 64-character lowercase hex string', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash  = WeldCertificate.computePdfHash(bytes);
      expect(hash.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue,
          reason: 'Hash must be lowercase hex');
    });

    test('computePdfHash is deterministic for same input', () {
      final bytes = Uint8List.fromList(List.generate(100, (i) => i % 256));
      expect(
        WeldCertificate.computePdfHash(bytes),
        equals(WeldCertificate.computePdfHash(bytes)),
      );
    });

    test('computePdfHash differs for different input', () {
      final a = WeldCertificate.computePdfHash(Uint8List.fromList([1, 2, 3]));
      final b = WeldCertificate.computePdfHash(Uint8List.fromList([3, 2, 1]));
      expect(a, isNot(equals(b)));
    });

    test('computePdfHash of empty bytes returns valid 64-char hex', () {
      final hash = WeldCertificate.computePdfHash(Uint8List(0));
      expect(hash.length, equals(64));
    });

    test('certificate with known PDF hash round-trips correctly', () {
      final pdfBytes = Uint8List.fromList([10, 20, 30]);
      final pdfHash  = WeldCertificate.computePdfHash(pdfBytes);
      final cert     = _cert(pdfHash: pdfHash);
      final decoded  = WeldCertificate.fromJson(cert.toJson());
      expect(decoded.pdfHash, equals(pdfHash));
    });

    test('pdfHash embedded in toJson is exactly 64 chars', () {
      final pdfBytes = Uint8List.fromList([42, 43, 44]);
      final pdfHash  = WeldCertificate.computePdfHash(pdfBytes);
      final json     = _cert(pdfHash: pdfHash).toJson();
      expect((json['pdfHash'] as String).length, equals(64));
    });
  });

  // ── certificate_registry_validation ─────────────────────────────────────────

  group('certificate_registry_validation', () {
    test('certificate with matching registry entry passes round-trip', () async {
      final dir = _tmpDir();
      final reg = p.join(dir.path, 'registry_export.json');

      final sig = _fakeSig('d');
      await WeldRegistry.append(
          _registryEntry(jointId: 'rv-001', signature: sig),
          registryPath: reg);

      // Generate cert from registry
      final entry = await WeldRegistry.findByJointId('rv-001',
          registryPath: reg);
      expect(entry, isNotNull);

      final cert = WeldCertificate.generateCertificate(
        jointId:      entry!.jointId,
        signature:    entry.signature,
        timestamp:    entry.timestamp,
        machineId:    entry.machineId,
        diameter:     entry.diameter,
        material:     entry.material,
        sdr:          entry.sdr,
        traceQuality: 'OK',
      );

      expect(cert.jointId,   equals('rv-001'));
      expect(cert.signature, equals(sig));
      dir.deleteSync(recursive: true);
    });

    test('certificate toJson includes all required fields for registry check',
        () {
      final cert = _cert();
      final json = cert.toJson();
      for (final key in ['jointId', 'signature', 'timestamp', 'machineId',
                         'diameter', 'material', 'sdr', 'traceQuality']) {
        expect(json.containsKey(key), isTrue, reason: 'Missing key: $key');
      }
    });

    test('multiple certificates for different joints are independent', () {
      final certs = List.generate(
        5,
        (i) => _cert(jointId: 'j-$i', signature: _fakeSig('$i')),
      );
      final ids = certs.map((c) => c.jointId).toSet();
      expect(ids.length, equals(5), reason: 'All joint IDs must be unique');
    });

    test('LOW_SAMPLE_COUNT quality is preserved through round-trip', () {
      final cert    = _cert(traceQuality: 'LOW_SAMPLE_COUNT');
      final decoded = WeldCertificate.fromJson(cert.toJson());
      expect(decoded.traceQuality, equals('LOW_SAMPLE_COUNT'));
    });

    test('certificate with pdfHash and all process params round-trips', () {
      final cert = WeldCertificate.generateCertificate(
        jointId:       'full-cert',
        signature:     _fakeSig('f'),
        timestamp:     DateTime.utc(2025, 1, 15, 9, 0),
        machineId:     'MACH-XL',
        diameter:      315.0,
        material:      'PP',
        sdr:           'SDR17.6',
        traceQuality:  'OK',
        fusionPressure: 2.1,
        heatingTime:   210.0,
        coolingTime:   300.0,
        beadHeight:    4.5,
        pdfHash:       _fakeHash('a'),
      );

      final decoded = WeldCertificate.fromJson(cert.toJson());
      expect(decoded.diameter,      closeTo(315.0, 0.001));
      expect(decoded.material,      equals('PP'));
      expect(decoded.sdr,           equals('SDR17.6'));
      expect(decoded.fusionPressure, closeTo(2.1,  0.001));
      expect(decoded.heatingTime,   closeTo(210.0, 0.001));
      expect(decoded.pdfHash,       equals(_fakeHash('a')));
    });
  });
}
