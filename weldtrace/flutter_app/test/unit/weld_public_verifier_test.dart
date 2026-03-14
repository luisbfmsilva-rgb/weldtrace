import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:weldtrace/services/welding_trace/weld_public_verifier.dart';
import 'package:weldtrace/services/welding_trace/weld_registry.dart';
import 'package:weldtrace/services/welding_trace/weld_verifier.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

/// 64-character fake SHA-256 hex string filled with [char].
String _fakeSig([String char = 'a']) => List.filled(64, char).join();

Directory _tmpDir() =>
    Directory.systemTemp.createTempSync('weld_public_verifier_test_');

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
      timestamp: DateTime.utc(2025, 6, 1, 8, 0, 0),
      machineId: machineId,
      diameter:  diameter,
      material:  material,
      sdr:       sdr,
    );

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // ── QR decode ──────────────────────────────────────────────────────────────

  group('qr_decode_valid', () {
    test('decodes a correctly built WeldTrace payload', () {
      final raw = WeldVerifier.buildVerificationPayload(
        jointId:   'joint-abc',
        signature: _fakeSig('b'),
      );
      final result = WeldPublicVerifier.decodeQrPayload(raw);
      expect(result.jointId,   equals('joint-abc'));
      expect(result.signature, equals(_fakeSig('b')));
    });

    test('returns QrPayloadResult type', () {
      final raw = WeldVerifier.buildVerificationPayload(
        jointId:   'j-1',
        signature: _fakeSig(),
      );
      expect(WeldPublicVerifier.decodeQrPayload(raw), isA<QrPayloadResult>());
    });

    test('payload with extra fields is accepted', () {
      // Unknown keys beyond the required set must not cause a failure
      final raw =
          '{"app":"WeldTrace","joint":"j-extra","sig":"${_fakeSig('c')}",'
          '"v":1,"verify":"registry","extra":"ignored"}';
      final result = WeldPublicVerifier.decodeQrPayload(raw);
      expect(result.jointId,   equals('j-extra'));
      expect(result.signature, equals(_fakeSig('c')));
    });

    test('decodes round-trip through buildVerificationPayload', () {
      const jointId   = '018f4e5a-1b2c-7d3e-9a4b-5c6d7e8f9a0b';
      final  signature = _fakeSig('d');
      final  raw       = WeldVerifier.buildVerificationPayload(
        jointId:   jointId,
        signature: signature,
      );
      final result = WeldPublicVerifier.decodeQrPayload(raw);
      expect(result.jointId,   equals(jointId));
      expect(result.signature, equals(signature));
    });
  });

  group('qr_decode_invalid', () {
    test('throws WeldPublicVerifierException for non-JSON string', () {
      expect(
        () => WeldPublicVerifier.decodeQrPayload('not-json'),
        throwsA(isA<WeldPublicVerifierException>()),
      );
    });

    test('throws for JSON array (not object)', () {
      expect(
        () => WeldPublicVerifier.decodeQrPayload('[1,2,3]'),
        throwsA(isA<WeldPublicVerifierException>()),
      );
    });

    test('throws for wrong app identifier', () {
      final payload = '{"app":"OtherApp","joint":"j","sig":"${_fakeSig()}","v":1}';
      expect(
        () => WeldPublicVerifier.decodeQrPayload(payload),
        throwsA(isA<WeldPublicVerifierException>()),
      );
    });

    test('throws for unsupported version', () {
      final payload =
          '{"app":"WeldTrace","joint":"j","sig":"${_fakeSig()}","v":2}';
      expect(
        () => WeldPublicVerifier.decodeQrPayload(payload),
        throwsA(isA<WeldPublicVerifierException>()),
      );
    });

    test('throws for missing "joint" field', () {
      final payload =
          '{"app":"WeldTrace","sig":"${_fakeSig()}","v":1}';
      expect(
        () => WeldPublicVerifier.decodeQrPayload(payload),
        throwsA(isA<WeldPublicVerifierException>()),
      );
    });

    test('throws for missing "sig" field', () {
      final payload =
          '{"app":"WeldTrace","joint":"j-1","v":1}';
      expect(
        () => WeldPublicVerifier.decodeQrPayload(payload),
        throwsA(isA<WeldPublicVerifierException>()),
      );
    });

    test('throws for empty "joint" field', () {
      final payload =
          '{"app":"WeldTrace","joint":"","sig":"${_fakeSig()}","v":1}';
      expect(
        () => WeldPublicVerifier.decodeQrPayload(payload),
        throwsA(isA<WeldPublicVerifierException>()),
      );
    });

    test('throws for empty "sig" field', () {
      final payload =
          '{"app":"WeldTrace","joint":"j-1","sig":"","v":1}';
      expect(
        () => WeldPublicVerifier.decodeQrPayload(payload),
        throwsA(isA<WeldPublicVerifierException>()),
      );
    });

    test('throws for empty string input', () {
      expect(
        () => WeldPublicVerifier.decodeQrPayload(''),
        throwsA(isA<WeldPublicVerifierException>()),
      );
    });

    test('exception message is descriptive', () {
      try {
        WeldPublicVerifier.decodeQrPayload('bad-json');
        fail('Expected WeldPublicVerifierException');
      } on WeldPublicVerifierException catch (e) {
        expect(e.message, isNotEmpty);
        expect(e.toString(), contains('WeldPublicVerifierException'));
      }
    });
  });

  // ── registry_lookup ─────────────────────────────────────────────────────────

  group('registry_lookup_success', () {
    late Directory dir;

    setUp(() => dir = _tmpDir());
    tearDown(() => dir.deleteSync(recursive: true));

    test('findRegistryEntry returns entry when jointId exists', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
          _entry(jointId: 'target'), registryPath: path);

      final found = await WeldPublicVerifier.findRegistryEntry(
        jointId:      'target',
        registryPath: path,
      );
      expect(found, isNotNull);
      expect(found!.jointId, equals('target'));
    });

    test('findRegistryEntry returns correct entry among several', () async {
      final path = _registryPath(dir);
      for (var i = 0; i < 5; i++) {
        await WeldRegistry.append(
            _entry(jointId: 'j-$i'), registryPath: path);
      }
      final found = await WeldPublicVerifier.findRegistryEntry(
        jointId:      'j-3',
        registryPath: path,
      );
      expect(found?.jointId, equals('j-3'));
    });

    test('findRegistryEntry preserves all fields', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
        _entry(
          jointId:   'field-check',
          signature: _fakeSig('f'),
          diameter:  315.0,
          material:  'PP',
          sdr:       'SDR17.6',
        ),
        registryPath: path,
      );
      final found = await WeldPublicVerifier.findRegistryEntry(
        jointId:      'field-check',
        registryPath: path,
      );
      expect(found?.signature, equals(_fakeSig('f')));
      expect(found?.diameter,  closeTo(315.0, 0.001));
      expect(found?.material,  equals('PP'));
      expect(found?.sdr,       equals('SDR17.6'));
    });
  });

  group('registry_lookup_missing', () {
    late Directory dir;

    setUp(() => dir = _tmpDir());
    tearDown(() => dir.deleteSync(recursive: true));

    test('findRegistryEntry returns null when jointId not in registry', () async {
      final path = _registryPath(dir);
      await WeldRegistry.append(
          _entry(jointId: 'existing'), registryPath: path);

      final found = await WeldPublicVerifier.findRegistryEntry(
        jointId:      'non-existent',
        registryPath: path,
      );
      expect(found, isNull);
    });

    test('findRegistryEntry returns null for empty registry', () async {
      final path = _registryPath(dir);
      final found = await WeldPublicVerifier.findRegistryEntry(
        jointId:      'anything',
        registryPath: path,
      );
      expect(found, isNull);
    });
  });

  // ── public_verification ──────────────────────────────────────────────────────

  group('public_verification_success', () {
    test('verifyJoint returns true for exact match in registry', () {
      final registry = [
        _entry(jointId: 'j-1', signature: _fakeSig('a')),
        _entry(jointId: 'j-2', signature: _fakeSig('b')),
        _entry(jointId: 'j-3', signature: _fakeSig('c')),
      ];
      final valid = WeldPublicVerifier.verifyJoint(
        jointId:   'j-2',
        signature: _fakeSig('b'),
        registry:  registry,
      );
      expect(valid, isTrue);
    });

    test('verifyJoint returns true for first entry', () {
      final registry = [_entry(jointId: 'first', signature: _fakeSig('1'))];
      expect(
        WeldPublicVerifier.verifyJoint(
          jointId:   'first',
          signature: _fakeSig('1'),
          registry:  registry,
        ),
        isTrue,
      );
    });

    test('verifyJoint returns true for last entry among 100', () {
      final registry = List.generate(
        100,
        (i) => _entry(jointId: 'j-$i', signature: '$i'.padLeft(64, '0')),
      );
      expect(
        WeldPublicVerifier.verifyJoint(
          jointId:   'j-99',
          signature: '99'.padLeft(64, '0'),
          registry:  registry,
        ),
        isTrue,
      );
    });

    test('end-to-end: QR decode → verifyJoint succeeds', () {
      const jointId   = 'e2e-joint';
      final  signature = _fakeSig('e');
      final  rawQr     = WeldVerifier.buildVerificationPayload(
        jointId:   jointId,
        signature: signature,
      );
      final result   = WeldPublicVerifier.decodeQrPayload(rawQr);
      final registry = [_entry(jointId: jointId, signature: signature)];
      expect(
        WeldPublicVerifier.verifyJoint(
          jointId:   result.jointId,
          signature: result.signature,
          registry:  registry,
        ),
        isTrue,
      );
    });
  });

  group('public_verification_failure', () {
    test('verifyJoint returns false for wrong signature', () {
      final registry = [_entry(jointId: 'j-1', signature: _fakeSig('a'))];
      expect(
        WeldPublicVerifier.verifyJoint(
          jointId:   'j-1',
          signature: _fakeSig('b'),  // wrong
          registry:  registry,
        ),
        isFalse,
      );
    });

    test('verifyJoint returns false for wrong jointId', () {
      final registry = [_entry(jointId: 'real', signature: _fakeSig('a'))];
      expect(
        WeldPublicVerifier.verifyJoint(
          jointId:   'fake',  // wrong
          signature: _fakeSig('a'),
          registry:  registry,
        ),
        isFalse,
      );
    });

    test('verifyJoint returns false for empty registry', () {
      expect(
        WeldPublicVerifier.verifyJoint(
          jointId:   'anything',
          signature: _fakeSig(),
          registry:  [],
        ),
        isFalse,
      );
    });

    test('verifyJoint rejects cross-matched joint+signature pair', () {
      final registry = [
        _entry(jointId: 'j-A', signature: _fakeSig('a')),
        _entry(jointId: 'j-B', signature: _fakeSig('b')),
      ];
      expect(
        WeldPublicVerifier.verifyJoint(
          jointId:   'j-A',
          signature: _fakeSig('b'),  // j-B's sig on j-A
          registry:  registry,
        ),
        isFalse,
        reason: 'cross-matched pair must not verify',
      );
    });

    test('verifyJoint is case-sensitive for jointId', () {
      final registry = [_entry(jointId: 'JOINT-001', signature: _fakeSig())];
      expect(
        WeldPublicVerifier.verifyJoint(
          jointId:   'joint-001',  // lowercase
          signature: _fakeSig(),
          registry:  registry,
        ),
        isFalse,
        reason: 'jointId comparison must be case-sensitive',
      );
    });

    test('verifyJoint is case-sensitive for signature', () {
      final registry = [_entry(signature: _fakeSig('A'))]; // uppercase hex
      expect(
        WeldPublicVerifier.verifyJoint(
          jointId:   'joint-001',
          signature: _fakeSig('a'),  // lowercase hex
          registry:  registry,
        ),
        isFalse,
        reason: 'signature comparison must be case-sensitive',
      );
    });
  });
}
