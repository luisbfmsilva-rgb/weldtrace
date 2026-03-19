import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';

/// Scans a weld QR code and shows verification result.
class QRScanScreen extends ConsumerStatefulWidget {
  const QRScanScreen({super.key});

  @override
  ConsumerState<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends ConsumerState<QRScanScreen> {
  final MobileScannerController _scanner = MobileScannerController();
  bool _scanned = false;
  bool _loading = false;
  _ScanResult? _result;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned || _loading) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() { _scanned = true; _loading = true; });
    await _scanner.stop();

    try {
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      final jointId = payload['jointId'] as String?;
      final signature = payload['signature'] as String?;

      if (jointId == null || signature == null) {
        setState(() {
          _result = _ScanResult.invalid(
            raw: raw,
            reason: 'Invalid QR payload — missing jointId or signature.',
          );
          _loading = false;
        });
        return;
      }

      final db = ref.read(databaseProvider);
      final welds = await db.weldsDao.getAll();
      final match = welds.where((w) => w.jointId == jointId).firstOrNull;

      if (match == null) {
        setState(() {
          _result = _ScanResult.notFound(jointId: jointId);
          _loading = false;
        });
        return;
      }

      final sigOk = match.traceSignature?.startsWith(signature) ?? false;
      setState(() {
        _result = sigOk
            ? _ScanResult.valid(weld: match)
            : _ScanResult.tampered(weld: match);
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _result = _ScanResult.invalid(raw: raw, reason: 'Could not parse QR code.');
        _loading = false;
      });
    }
  }

  void _reset() {
    setState(() { _scanned = false; _result = null; _loading = false; });
    _scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Verify Weld', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_scanned)
            TextButton(
              onPressed: _reset,
              child: const Text('Scan Again', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _result != null
          ? _ResultView(result: _result!, onReset: _reset,
              onDetail: _result!.weld != null
                  ? () => context.push('/welds/${_result!.weld!.id}')
                  : null)
          : Stack(
              children: [
                MobileScanner(
                  controller: _scanner,
                  onDetect: _onDetect,
                ),
                // ── Viewfinder overlay ─────────────────────────────────
                _ScannerOverlay(),
                if (_loading)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
              ],
            ),
    );
  }
}

// ── Scanner overlay ────────────────────────────────────────────────────────────

class _ScannerOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const boxSize = 260.0;

    return Stack(
      children: [
        // Dark overlay
        ColorFiltered(
          colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.5), BlendMode.srcOver),
          child: CustomPaint(
            size: size,
            painter: _OverlayPainter(boxSize: boxSize),
          ),
        ),
        // Corner decoration
        Center(
          child: SizedBox(
            width: boxSize,
            height: boxSize,
            child: CustomPaint(painter: _CornerPainter()),
          ),
        ),
        // Label
        Positioned(
          bottom: 120,
          left: 0, right: 0,
          child: const Text(
            'Point at the weld QR code',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _OverlayPainter extends CustomPainter {
  const _OverlayPainter({required this.boxSize});
  final double boxSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final half = boxSize / 2;
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: boxSize, height: boxSize),
        const Radius.circular(12),
      ))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.sertecRed
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 24.0;
    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawLine(const Offset(0, len), Offset.zero, paint);
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    // Top-right
    canvas.drawLine(Offset(w - len, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, len), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, h - len), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(len, h), paint);
    // Bottom-right
    canvas.drawLine(Offset(w - len, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - len), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Result view ────────────────────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.onReset, this.onDetail});
  final _ScanResult result;
  final VoidCallback onReset;
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: result.statusColor.withValues(alpha: 0.1),
                  ),
                  child: Icon(result.statusIcon, size: 40, color: result.statusColor),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(result.title,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: result.statusColor)),
              ),
              if (result.subtitle != null) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(result.subtitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: AppColors.neutralGray)),
                ),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),

              if (result.weld != null) ...[
                _Row('Material', '${result.weld!.pipeMaterial} Ø${result.weld!.pipeDiameter.toStringAsFixed(0)} mm'),
                if (result.weld!.pipeSdr != null) _Row('SDR', result.weld!.pipeSdr!),
                _Row('Status', result.weld!.status.toUpperCase()),
                if (result.weld!.jointId != null) _Row('Joint ID', result.weld!.jointId!.substring(0, 16) + '…'),
              ],

              if (result.rawPayload != null) ...[
                const SizedBox(height: 8),
                Text('Payload:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Text(result.rawPayload!,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
              ],

              const Spacer(),
              if (onDetail != null)
                FilledButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View Weld Details'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.sertecRed,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: onDetail,
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Another'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.sertecRed,
                  side: const BorderSide(color: AppColors.sertecRed),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onReset,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _Row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: AppColors.neutralGray, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
      );
}

// ── Scan result model ──────────────────────────────────────────────────────────

class _ScanResult {
  const _ScanResult._({
    required this.title,
    this.subtitle,
    required this.statusColor,
    required this.statusIcon,
    this.weld,
    this.rawPayload,
  });

  final String title;
  final String? subtitle;
  final Color statusColor;
  final IconData statusIcon;
  final WeldRecord? weld;
  final String? rawPayload;

  factory _ScanResult.valid({required WeldRecord weld}) => _ScanResult._(
        title: 'WELD VERIFIED ✓',
        subtitle: 'This weld certificate is authentic and unmodified.',
        statusColor: const Color(0xFF2E7D32),
        statusIcon: Icons.verified,
        weld: weld,
      );

  factory _ScanResult.tampered({required WeldRecord weld}) => _ScanResult._(
        title: 'SIGNATURE MISMATCH ✗',
        subtitle: 'The QR signature does not match the stored record. This certificate may have been tampered.',
        statusColor: Colors.red,
        statusIcon: Icons.gpp_bad,
        weld: weld,
      );

  factory _ScanResult.notFound({required String jointId}) => _ScanResult._(
        title: 'WELD NOT FOUND',
        subtitle: 'Joint ID not found in local database. Sync with cloud to fetch all welds.',
        statusColor: Colors.orange,
        statusIcon: Icons.search_off,
        rawPayload: 'Joint ID: $jointId',
      );

  factory _ScanResult.invalid({required String raw, required String reason}) => _ScanResult._(
        title: 'INVALID QR CODE',
        subtitle: reason,
        statusColor: Colors.grey,
        statusIcon: Icons.qr_code,
        rawPayload: raw.length > 100 ? raw.substring(0, 100) + '…' : raw,
      );
}
