import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:weldtrace/services/welding_trace/weld_ledger.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Returns a fresh temporary ledger file path for each test.
/// The file is placed in the system temp directory and is unique per call.
String _tempLedgerPath() {
  final dir  = Directory.systemTemp.createTempSync('weld_ledger_test_');
  return '${dir.path}/ledger.json';
}

WeldLedgerEntry _entry({
  String jointId   = 'jnt-001',
  String signature = 'aabbcc',
  String machineId = 'MACH-001',
  double diameter  = 160.0,
  String material  = 'PE100',
  DateTime? ts,
}) =>
    WeldLedgerEntry(
      jointId:   jointId,
      signature: signature,
      timestamp: ts ?? DateTime.utc(2025, 6, 15, 8, 30),
      machineId: machineId,
      diameter:  diameter,
      material:  material,
    );

void main() {
  // ── WeldLedger ──────────────────────────────────────────────────────────────

  group('WeldLedger', () {
    // ── Append ────────────────────────────────────────────────────────────────

    test('append creates ledger file on first call', () async {
      final path = _tempLedgerPath();
      expect(File(path).existsSync(), isFalse);

      await WeldLedger.append(_entry(), ledgerPath: path);

      expect(File(path).existsSync(), isTrue);
    });

    test('append stores the entry correctly', () async {
      final path = _tempLedgerPath();
      final e    = _entry(jointId: 'jnt-001', signature: 'sig-001');
      await WeldLedger.append(e, ledgerPath: path);

      final entries = await WeldLedger.loadAll(ledgerPath: path);
      expect(entries.length, equals(1));
      expect(entries.first.jointId,   equals('jnt-001'));
      expect(entries.first.signature, equals('sig-001'));
    });

    test('append preserves existing entries (append-only)', () async {
      final path = _tempLedgerPath();
      await WeldLedger.append(_entry(jointId: 'jnt-A', signature: 'sig-A'),
          ledgerPath: path);
      await WeldLedger.append(_entry(jointId: 'jnt-B', signature: 'sig-B'),
          ledgerPath: path);
      await WeldLedger.append(_entry(jointId: 'jnt-C', signature: 'sig-C'),
          ledgerPath: path);

      final entries = await WeldLedger.loadAll(ledgerPath: path);
      expect(entries.length, equals(3));
      expect(entries[0].jointId, equals('jnt-A'));
      expect(entries[1].jointId, equals('jnt-B'));
      expect(entries[2].jointId, equals('jnt-C'));
    });

    test('append does not modify earlier entries', () async {
      final path = _tempLedgerPath();
      final ts1  = DateTime.utc(2025, 1, 1);
      final ts2  = DateTime.utc(2025, 6, 1);

      await WeldLedger.append(
          _entry(jointId: 'jnt-1', signature: 'sig-1', ts: ts1),
          ledgerPath: path);
      await WeldLedger.append(
          _entry(jointId: 'jnt-2', signature: 'sig-2', ts: ts2),
          ledgerPath: path);

      final entries = await WeldLedger.loadAll(ledgerPath: path);
      expect(entries[0].signature, equals('sig-1'));
      expect(entries[0].timestamp, equals(ts1));
    });

    // ── Persistence ───────────────────────────────────────────────────────────

    test('loadAll returns empty list when file does not exist', () async {
      final path    = _tempLedgerPath();
      final entries = await WeldLedger.loadAll(ledgerPath: path);
      expect(entries, isEmpty);
    });

    test('loadAll correctly deserialises all fields', () async {
      final path = _tempLedgerPath();
      final ts   = DateTime.utc(2025, 6, 15, 10, 0, 0);
      await WeldLedger.append(
        WeldLedgerEntry(
          jointId:   'jnt-full',
          signature: 'fullsig',
          timestamp: ts,
          machineId: 'M-99',
          diameter:  315.0,
          material:  'PP',
        ),
        ledgerPath: path,
      );

      final loaded = await WeldLedger.loadAll(ledgerPath: path);
      expect(loaded.length, equals(1));
      final e = loaded.first;
      expect(e.jointId,   equals('jnt-full'));
      expect(e.signature, equals('fullsig'));
      expect(e.machineId, equals('M-99'));
      expect(e.diameter,  closeTo(315.0, 1e-9));
      expect(e.material,  equals('PP'));
      expect(e.timestamp, equals(ts));
      expect(e.timestamp.isUtc, isTrue);
    });

    test('entries survive write-read roundtrip via file', () async {
      final path    = _tempLedgerPath();
      final orignal = List.generate(
        10,
        (i) => _entry(
          jointId:   'jnt-$i',
          signature: 'sig-$i',
          diameter:  110.0 + i,
        ),
      );

      for (final e in orignal) {
        await WeldLedger.append(e, ledgerPath: path);
      }

      final loaded = await WeldLedger.loadAll(ledgerPath: path);
      expect(loaded.length, equals(10));
      for (int i = 0; i < 10; i++) {
        expect(loaded[i].jointId,   equals('jnt-$i'));
        expect(loaded[i].signature, equals('sig-$i'));
        expect(loaded[i].diameter,  closeTo(110.0 + i, 1e-9));
      }
    });

    // ── Signature lookup ──────────────────────────────────────────────────────

    test('verifyLedgerEntry returns true for existing signature', () async {
      final path = _tempLedgerPath();
      await WeldLedger.append(
          _entry(signature: 'known-sig'), ledgerPath: path);

      final found = await WeldLedger.verifyLedgerEntry('known-sig',
          ledgerPath: path);
      expect(found, isTrue);
    });

    test('verifyLedgerEntry returns false for unknown signature', () async {
      final path = _tempLedgerPath();
      await WeldLedger.append(
          _entry(signature: 'known-sig'), ledgerPath: path);

      final found = await WeldLedger.verifyLedgerEntry('unknown-sig',
          ledgerPath: path);
      expect(found, isFalse);
    });

    test('verifyLedgerEntry returns false on empty ledger', () async {
      final path  = _tempLedgerPath();
      final found = await WeldLedger.verifyLedgerEntry('any-sig',
          ledgerPath: path);
      expect(found, isFalse);
    });

    test('verifyLedgerEntry finds signature among many entries', () async {
      final path = _tempLedgerPath();
      for (int i = 0; i < 50; i++) {
        await WeldLedger.append(
            _entry(jointId: 'jnt-$i', signature: 'sig-$i'),
            ledgerPath: path);
      }

      expect(
          await WeldLedger.verifyLedgerEntry('sig-25', ledgerPath: path),
          isTrue);
      expect(
          await WeldLedger.verifyLedgerEntry('sig-49', ledgerPath: path),
          isTrue);
      expect(
          await WeldLedger.verifyLedgerEntry('sig-99', ledgerPath: path),
          isFalse);
    });

    // ── findByJointId ──────────────────────────────────────────────────────────

    test('findByJointId returns correct entry', () async {
      final path = _tempLedgerPath();
      await WeldLedger.append(
          _entry(jointId: 'jnt-A', signature: 'sig-A'), ledgerPath: path);
      await WeldLedger.append(
          _entry(jointId: 'jnt-B', signature: 'sig-B'), ledgerPath: path);

      final found = await WeldLedger.findByJointId('jnt-B', ledgerPath: path);
      expect(found, isNotNull);
      expect(found!.signature, equals('sig-B'));
    });

    test('findByJointId returns null when not found', () async {
      final path  = _tempLedgerPath();
      await WeldLedger.append(
          _entry(jointId: 'jnt-A'), ledgerPath: path);
      final found = await WeldLedger.findByJointId('jnt-Z', ledgerPath: path);
      expect(found, isNull);
    });

    // ── Joint ID uniqueness ────────────────────────────────────────────────────

    test('joint IDs are unique across independent ledger entries', () async {
      final path = _tempLedgerPath();

      // Simulate 100 welds each with a distinct jointId
      for (int i = 0; i < 100; i++) {
        await WeldLedger.append(
          _entry(
            jointId:   'jnt-unique-$i',
            signature: 'sig-$i',
          ),
          ledgerPath: path,
        );
      }

      final entries    = await WeldLedger.loadAll(ledgerPath: path);
      final jointIds   = entries.map((e) => e.jointId).toSet();
      expect(jointIds.length, equals(100),
          reason: 'All 100 joint IDs must be unique');
    });

    test('same signature cannot be distinguished from two joints', () async {
      // Two different joints can theoretically share a signature only in case
      // of SHA-256 collision (astronomically unlikely).  This test confirms
      // that verifyLedgerEntry uses exact matching, not "first only".
      final path = _tempLedgerPath();
      await WeldLedger.append(
          _entry(jointId: 'jnt-X', signature: 'shared-sig'), ledgerPath: path);
      await WeldLedger.append(
          _entry(jointId: 'jnt-Y', signature: 'shared-sig'), ledgerPath: path);

      final found = await WeldLedger.verifyLedgerEntry('shared-sig',
          ledgerPath: path);
      expect(found, isTrue);

      final entries = await WeldLedger.loadAll(ledgerPath: path);
      expect(entries.where((e) => e.signature == 'shared-sig').length,
          equals(2));
    });
  });
}
