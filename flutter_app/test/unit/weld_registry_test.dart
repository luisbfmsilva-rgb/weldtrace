import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:weldtrace/services/welding_trace/weld_registry.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Returns a 64-character fake SHA-256 hex string filled with [char].
String _fakeSig([String char = 'a']) => List.filled(64, char).join();

Directory _tmpDir() {
  final dir = Directory.systemTemp.createTempSync('weld_registry_test_');
  return dir;
}

String _registryPath(Directory dir) => p.join(dir.path, 'registry_export.json');

WeldRegistryEntry _entry({
  String  jointId   = 'joint-001',
  String? signature,
  String  machineId = 'M-01',
  double  diameter  = 160.0,
  String  material  = 'PE100',
  String  sdr       = '11',
}) =>
    WeldRegistryEntry(
      jointId:   jointId,
      signature: signature ?? _fakeSig('a'),
      timestamp: DateTime.utc(2025, 3, 1, 10, 0, 0),
      machineId: machineId,
      diameter:  diameter,
      material:  material,
      sdr:       sdr,
    );

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('WeldRegistryEntry — serialisation', () {
    test('toJson round-trip preserves all fields', () {
      final entry = _entry(
        jointId:   'abc-123',
        signature: _fakeSig('f'),
        machineId: 'M-42',
        diameter:  200.0,
        material:  'PP',
        sdr:       'SDR17.6',
      );
      final json    = entry.toJson();
      final decoded = WeldRegistryEntry.fromJson(json);

      expect(decoded.jointId,   equals(entry.jointId));
      expect(decoded.signature, equals(entry.signature));
      expect(decoded.machineId, equals(entry.machineId));
      expect(decoded.diameter,  closeTo(entry.diameter, 0.001));
      expect(decoded.material,  equals(entry.material));
      expect(decoded.sdr,       equals(entry.sdr));
      expect(
        decoded.timestamp.millisecondsSinceEpoch,
        equals(entry.timestamp.millisecondsSinceEpoch),
      );
    });

    test('timestamp is serialised as UTC ISO-8601', () {
      final entry = _entry();
      final json  = entry.toJson();
      expect(json['timestamp'], endsWith('Z'),
          reason: 'timestamp must be UTC (ends with Z)');
    });
  });

  // ── registry_append ──────────────────────────────────────────────────────────

  group('registry_append', () {
    late Directory dir;

    setUp(() => dir = _tmpDir());
    tearDown(() => dir.deleteSync(recursive: true));

    test('creates file on first append', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(_entry(), registryPath: path);
      expect(File(path).existsSync(), isTrue);
    });

    test('file contains valid JSON array after append', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(_entry(), registryPath: path);
      final raw  = File(path).readAsStringSync();
      final list = jsonDecode(raw);
      expect(list, isA<List>());
      expect((list as List).length, equals(1));
    });

    test('second append grows the list to 2', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(_entry(jointId: 'j-1'), registryPath: path);
      await WeldRegistry.append(_entry(jointId: 'j-2'), registryPath: path);
      final raw  = jsonDecode(File(path).readAsStringSync()) as List;
      expect(raw.length, equals(2));
    });

    test('existing entries are NOT mutated on append', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
          _entry(jointId: 'original'), registryPath: path);
      await WeldRegistry.append(
          _entry(jointId: 'new-entry'), registryPath: path);

      final list = jsonDecode(File(path).readAsStringSync()) as List;
      expect((list.first as Map)['jointId'], equals('original'),
          reason: 'first entry must remain unchanged');
    });

    test('sdr field is persisted correctly', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
          _entry(sdr: 'SDR17.6'), registryPath: path);
      final list = jsonDecode(File(path).readAsStringSync()) as List;
      expect((list.first as Map)['sdr'], equals('SDR17.6'));
    });

    test('50 sequential appends — file has 50 entries', () async {
      final path = _registryPath(dir);
      for (var i = 0; i < 50; i++) {
        await WeldRegistry.append(
            _entry(jointId: 'j-$i'), registryPath: path);
      }
      final list = jsonDecode(File(path).readAsStringSync()) as List;
      expect(list.length, equals(50));
    });
  });

  // ── registry_export ──────────────────────────────────────────────────────────

  group('registry_export', () {
    late Directory dir;

    setUp(() => dir = _tmpDir());
    tearDown(() => dir.deleteSync(recursive: true));

    test('exportRegistry returns empty list when file does not exist', () async {
      final path = _registryPath(dir);
      final list = await WeldRegistry.exportRegistry(registryPath: path);
      expect(list, isEmpty);
    });

    test('exportRegistry returns all appended entries', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
          _entry(jointId: 'j-1'), registryPath: path);
      await WeldRegistry.append(
          _entry(jointId: 'j-2'), registryPath: path);
      await WeldRegistry.append(
          _entry(jointId: 'j-3'), registryPath: path);

      final list = await WeldRegistry.exportRegistry(registryPath: path);
      expect(list.length, equals(3));
    });

    test('exportRegistry preserves insertion order', () async {
      final path = _registryPath(dir);
      for (var i = 1; i <= 5; i++) {
        await WeldRegistry.append(
            _entry(jointId: 'j-$i'), registryPath: path);
      }
      final list = await WeldRegistry.exportRegistry(registryPath: path);
      for (var i = 0; i < 5; i++) {
        expect(list[i].jointId, equals('j-${i + 1}'));
      }
    });

    test('exportRegistry round-trips diameter, material, and sdr', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
        _entry(diameter: 315.0, material: 'PP', sdr: 'SDR17.6'),
        registryPath: path,
      );
      final list = await WeldRegistry.exportRegistry(registryPath: path);
      expect(list.first.diameter, closeTo(315.0, 0.001));
      expect(list.first.material, equals('PP'));
      expect(list.first.sdr,      equals('SDR17.6'));
    });

    test('exportRegistry returns typed WeldRegistryEntry objects', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(_entry(), registryPath: path);
      final list = await WeldRegistry.exportRegistry(registryPath: path);
      expect(list.first, isA<WeldRegistryEntry>());
    });
  });

  // ── registry_verify ──────────────────────────────────────────────────────────

  group('registry_verify', () {
    late Directory dir;

    setUp(() => dir = _tmpDir());
    tearDown(() => dir.deleteSync(recursive: true));

    test('verifyFromRegistry returns true for exact match', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
        _entry(jointId: 'target', signature: _fakeSig('b')),
        registryPath: path,
      );
      final valid = await WeldRegistry.verifyFromRegistry(
        jointId:      'target',
        signature:    _fakeSig('b'),
        registryPath: path,
      );
      expect(valid, isTrue);
    });

    test('verifyFromRegistry returns false for wrong signature', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
        _entry(jointId: 'target', signature: _fakeSig('b')),
        registryPath: path,
      );
      final valid = await WeldRegistry.verifyFromRegistry(
        jointId:      'target',
        signature:    _fakeSig('c'),  // wrong
        registryPath: path,
      );
      expect(valid, isFalse);
    });

    test('verifyFromRegistry returns false for wrong jointId', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
        _entry(jointId: 'real', signature: _fakeSig('b')),
        registryPath: path,
      );
      final valid = await WeldRegistry.verifyFromRegistry(
        jointId:      'fake',  // wrong
        signature:    _fakeSig('b'),
        registryPath: path,
      );
      expect(valid, isFalse);
    });

    test('verifyFromRegistry returns false when registry is empty', () async {
      final path = _registryPath(dir);
      final valid = await WeldRegistry.verifyFromRegistry(
        jointId:      'anything',
        signature:    _fakeSig('a'),
        registryPath: path,
      );
      expect(valid, isFalse);
    });

    test('verifyFromRegistry finds correct entry among many', () async {
      final path  = _registryPath(dir);
      final sigOf = (int i) => '$i'.padLeft(64, '0');

      for (var i = 0; i < 20; i++) {
        await WeldRegistry.append(
          _entry(jointId: 'j-$i', signature: sigOf(i)),
          registryPath: path,
        );
      }
      final valid = await WeldRegistry.verifyFromRegistry(
        jointId:      'j-10',
        signature:    sigOf(10),
        registryPath: path,
      );
      expect(valid, isTrue);
    });

    test('verifyFromRegistry both jointId AND signature must match', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
        _entry(jointId: 'j-A', signature: _fakeSig('a')),
        registryPath: path,
      );
      await WeldRegistry.append(
        _entry(jointId: 'j-B', signature: _fakeSig('b')),
        registryPath: path,
      );

      // Cross-match must fail
      final cross = await WeldRegistry.verifyFromRegistry(
        jointId:      'j-A',
        signature:    _fakeSig('b'),  // j-B's signature on j-A
        registryPath: path,
      );
      expect(cross, isFalse,
          reason: 'cross-matching jointId and signature must not verify');
    });
  });

  // ── findByJointId ────────────────────────────────────────────────────────────

  group('findByJointId', () {
    late Directory dir;

    setUp(() => dir = _tmpDir());
    tearDown(() => dir.deleteSync(recursive: true));

    test('returns entry when found', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
          _entry(jointId: 'target'), registryPath: path);
      final found = await WeldRegistry.findByJointId(
          'target', registryPath: path);
      expect(found, isNotNull);
      expect(found!.jointId, equals('target'));
    });

    test('returns null when not found', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
          _entry(jointId: 'other'), registryPath: path);
      final found = await WeldRegistry.findByJointId(
          'missing', registryPath: path);
      expect(found, isNull);
    });

    test('returns null for empty registry', () async {
      final path = _registryPath(dir);
      final found = await WeldRegistry.findByJointId(
          'anything', registryPath: path);
      expect(found, isNull);
    });

    test('returns sdr field correctly', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
        _entry(jointId: 'sdr-test', sdr: 'SDR17.6'),
        registryPath: path,
      );
      final found = await WeldRegistry.findByJointId(
          'sdr-test', registryPath: path);
      expect(found?.sdr, equals('SDR17.6'));
    });
  });
}
