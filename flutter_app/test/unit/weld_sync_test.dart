import 'package:flutter_test/flutter_test.dart';

import 'package:weldtrace/services/welding_trace/weld_certificate.dart';
import 'package:weldtrace/services/welding_trace/weld_registry.dart';
import 'package:weldtrace/services/welding_trace/weld_sync_service.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

String _fakeSig([String char = 'a']) => List.filled(64, char).join();

WeldCertificate _cert() => WeldCertificate.generateCertificate(
      jointId:      'sync-test-joint',
      signature:    _fakeSig(),
      timestamp:    DateTime.utc(2025, 6, 1, 12, 0),
      machineId:    'M-SYNC-01',
      diameter:     110.0,
      material:     'PE100',
      sdr:          '11',
      traceQuality: 'OK',
    );

WeldRegistryEntry _entry() => WeldRegistryEntry(
      jointId:   'sync-test-entry',
      signature: _fakeSig('b'),
      timestamp: DateTime.utc(2025, 6, 1, 12, 0),
      machineId: 'M-SYNC-01',
      diameter:  110.0,
      material:  'PE100',
      sdr:       '11',
    );

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // ── sync_offline_mode ────────────────────────────────────────────────────────

  group('sync_offline_mode', () {
    late WeldSyncService service;

    setUp(() {
      service = const WeldSyncService();
    });

    test('uploadCertificate returns SyncResult with offline=true', () async {
      final result = await service.uploadCertificate(_cert());
      expect(result.offline, isTrue,
          reason: 'Default implementation must be offline');
    });

    test('uploadCertificate returns SyncResult with success=false', () async {
      final result = await service.uploadCertificate(_cert());
      expect(result.success, isFalse);
    });

    test('uploadRegistryEntry returns SyncResult with offline=true', () async {
      final result = await service.uploadRegistryEntry(_entry());
      expect(result.offline, isTrue);
    });

    test('uploadRegistryEntry returns SyncResult with success=false', () async {
      final result = await service.uploadRegistryEntry(_entry());
      expect(result.success, isFalse);
    });

    test('offline result has a non-null message', () async {
      final result = await service.uploadCertificate(_cert());
      expect(result.message, isNotNull);
      expect(result.message, isNotEmpty);
    });

    test('multiple uploadCertificate calls are all offline', () async {
      final results = await Future.wait([
        service.uploadCertificate(_cert()),
        service.uploadCertificate(_cert()),
        service.uploadCertificate(_cert()),
      ]);
      expect(results.every((r) => r.offline), isTrue);
    });

    test('multiple uploadRegistryEntry calls are all offline', () async {
      final results = await Future.wait([
        service.uploadRegistryEntry(_entry()),
        service.uploadRegistryEntry(_entry()),
      ]);
      expect(results.every((r) => r.offline), isTrue);
    });
  });

  // ── sync_result_objects ──────────────────────────────────────────────────────

  group('sync_result_objects', () {
    test('SyncResult.offline() sets offline=true', () {
      final r = SyncResult.offline();
      expect(r.offline, isTrue);
    });

    test('SyncResult.offline() sets success=false', () {
      final r = SyncResult.offline();
      expect(r.success, isFalse);
    });

    test('SyncResult.offline() has a non-null message', () {
      expect(SyncResult.offline().message, isNotNull);
    });

    test('SyncResult.success() sets success=true', () {
      expect(SyncResult.success().success, isTrue);
    });

    test('SyncResult.success() sets offline=false', () {
      expect(SyncResult.success().offline, isFalse);
    });

    test('SyncResult.success() accepts optional message', () {
      final r = SyncResult.success('Uploaded OK');
      expect(r.message, equals('Uploaded OK'));
    });

    test('SyncResult.success() message is null when not provided', () {
      expect(SyncResult.success().message, isNull);
    });

    test('SyncResult.failure() sets success=false', () {
      expect(SyncResult.failure('500 Internal Server Error').success, isFalse);
    });

    test('SyncResult.failure() sets offline=false', () {
      expect(SyncResult.failure('timeout').offline, isFalse);
    });

    test('SyncResult.failure() stores message', () {
      const msg = 'Connection refused';
      expect(SyncResult.failure(msg).message, equals(msg));
    });

    test('offline and failure are distinguishable', () {
      final offline  = SyncResult.offline();
      final failure  = SyncResult.failure('err');
      expect(offline.offline,  isTrue);
      expect(failure.offline,  isFalse);
    });

    test('success and offline are distinguishable', () {
      final ok = SyncResult.success();
      final no = SyncResult.offline();
      expect(ok.success, isTrue);
      expect(no.success, isFalse);
    });

    test('toString contains all three fields', () {
      final str = SyncResult.offline().toString();
      expect(str, contains('success'));
      expect(str, contains('offline'));
      expect(str, contains('message'));
    });
  });

  // ── cert_sync_status ─────────────────────────────────────────────────────────

  group('cert_sync_status', () {
    test('CertSyncStatus.pending is "pending"', () {
      expect(CertSyncStatus.pending, equals('pending'));
    });

    test('CertSyncStatus.synced is "synced"', () {
      expect(CertSyncStatus.synced, equals('synced'));
    });

    test('CertSyncStatus.offline is "offline"', () {
      expect(CertSyncStatus.offline, equals('offline'));
    });

    test('WeldCertificate.syncStatus defaults to null', () {
      expect(_cert().syncStatus, isNull);
    });

    test('WeldCertificate.syncStatus can be set to pending', () {
      final cert = WeldCertificate.generateCertificate(
        jointId:      'ss-pending',
        signature:    _fakeSig('p'),
        timestamp:    DateTime.utc(2025, 1, 1),
        machineId:    'M-01',
        diameter:     110.0,
        material:     'PE100',
        sdr:          '11',
        traceQuality: 'OK',
        syncStatus:   CertSyncStatus.pending,
      );
      expect(cert.syncStatus, equals(CertSyncStatus.pending));
    });

    test('WeldCertificate.syncStatus can be set to synced', () {
      final cert = WeldCertificate.generateCertificate(
        jointId:      'ss-synced',
        signature:    _fakeSig('s'),
        timestamp:    DateTime.utc(2025, 1, 1),
        machineId:    'M-01',
        diameter:     110.0,
        material:     'PE100',
        sdr:          '11',
        traceQuality: 'OK',
        syncStatus:   CertSyncStatus.synced,
      );
      expect(cert.syncStatus, equals(CertSyncStatus.synced));
    });

    test('syncStatus is not included in toJson', () {
      final cert = WeldCertificate.generateCertificate(
        jointId:      'ss-json',
        signature:    _fakeSig(),
        timestamp:    DateTime.utc(2025, 1, 1),
        machineId:    'M-01',
        diameter:     110.0,
        material:     'PE100',
        sdr:          '11',
        traceQuality: 'OK',
        syncStatus:   CertSyncStatus.pending,
      );
      expect(cert.toJson().containsKey('syncStatus'), isFalse,
          reason: 'syncStatus is transient and must not be serialised');
    });
  });
}
