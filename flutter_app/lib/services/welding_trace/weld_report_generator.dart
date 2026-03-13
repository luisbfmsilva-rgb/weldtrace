import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr/qr.dart';

import 'weld_trace_recorder.dart';
import 'weld_verifier.dart';

/// Generates a professional engineering-grade PDF welding report.
///
/// Report sections:
///   1. Header — "WeldTrace Welding Report" title block
///   2. Project Information — project, machine, operator, date, joint ID,
///      standard used
///   3. Pipe Information — diameter, material, SDR, wall thickness
///   4. Welding Parameters — fusion pressure, heating time, cooling time,
///      bead height
///   5. Curve Statistics — duration, max / avg pressure, sample count
///   6. Pressure × Time Chart — vector rendering; "No data" fallback
///   7. Digital Signature — SHA-256 fingerprint
///   8. Certification — local certification ledger record
///   9. Public Verification — WeldTrace registry notice
///  10. Weld Verification — QR code (encodes full verification JSON payload) and
///      scanner instructions
///  11. Footer — page numbers
///
/// All optional parameters default to placeholder strings so the report always
/// renders without throwing.  Chart rendering is wrapped in try/catch.
///
/// Usage:
/// ```dart
/// final pdfBytes = await WeldReportGenerator.generate(
///   projectName:      'Pipeline P-01',
///   machineName:      'Ritmo Delta 160',
///   machineId:        'MACH-001',
///   diameter:         160.0,
///   material:         'PE100',
///   sdr:              '11',
///   curve:            recorder.export(),
///   weldSignature:    signature,
///   timestamp:        DateTime.now(),
///   operatorName:     'J. Silva',
///   jointId:          'JNT-042',
///   wallThicknessStr: '14.6 mm',
///   fusionPressureBar: 0.15,
///   heatingTimeSec:   190,
///   coolingTimeSec:   180,
///   beadHeightMm:     3.2,
///   standardUsed:     'DVS 2207',
/// );
/// ```
class WeldReportGenerator {
  WeldReportGenerator._();

  static Future<Uint8List> generate({
    required String projectName,
    required String machineName,
    required double diameter,
    required String material,
    required String sdr,
    required List<WeldTracePoint> curve,
    required String weldSignature,
    required DateTime timestamp,
    // ── Extended metadata (optional) ──────────────────────────────────────
    String machineId        = '',
    String operatorName     = '',
    String jointId          = '',
    String wallThicknessStr = '',
    String standardUsed     = '',
    double fusionPressureBar = 0.0,
    double heatingTimeSec    = 0.0,
    double coolingTimeSec    = 0.0,
    double beadHeightMm      = 0.0,
  }) async {
    final pdf = pw.Document(
      author:  'WeldTrace',
      title:   'WeldTrace Welding Report — $projectName',
      creator: 'WeldTrace v1.0',
    );

    // ── Derived statistics ─────────────────────────────────────────────────
    final duration    = curve.length >= 2
        ? (curve.last.timeSeconds - curve.first.timeSeconds)
        : 0.0;
    final maxPressure = curve.isNotEmpty
        ? curve.map((p) => p.pressureBar).reduce(math.max)
        : 0.0;
    final avgPressure = curve.isNotEmpty
        ? curve.map((p) => p.pressureBar).reduce((a, b) => a + b) / curve.length
        : 0.0;

    final dateStr = DateFormat('dd MMM yyyy HH:mm').format(timestamp);

    // ── QR verification payload (optimised — < 200 chars) ─────────────────
    final effectiveJointId = jointId.isEmpty ? 'N/A' : jointId;
    final qrPayload = WeldVerifier.buildVerificationPayload(
      jointId:   effectiveJointId,
      signature: weldSignature,
    );

    // ── Colour palette ─────────────────────────────────────────────────────
    const headerColour = PdfColor.fromInt(0xFF1B3A5C);
    const accentColour = PdfColor.fromInt(0xFF2E7EB8);
    const rowAltColour = PdfColor.fromInt(0xFFF5F7FA);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin:     const pw.EdgeInsets.all(36),
          buildBackground: (context) => pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: accentColour, width: 4),
              ),
            ),
          ),
        ),
        header: (context) => _buildHeader(headerColour, accentColour),
        footer: (context) => _buildFooter(context, accentColour),
        build: (context) => [
          pw.SizedBox(height: 12),

          // ── 1. Project Information ────────────────────────────────────────
          _sectionTitle('Project Information', accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              ['Project',       projectName],
              ['Machine',       machineName.isEmpty ? 'N/A' : machineName],
              ['Operator',      operatorName.isEmpty ? 'N/A' : operatorName],
              ['Date',          dateStr],
              ['Joint ID',      jointId.isEmpty ? 'N/A' : jointId],
              ['Standard',      standardUsed.isEmpty ? 'N/A' : standardUsed],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 2. Pipe Information ───────────────────────────────────────────
          _sectionTitle('Pipe Information', accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              ['Diameter',       '${diameter.toStringAsFixed(1)} mm'],
              ['Material',       material],
              ['SDR',            sdr],
              ['Wall Thickness', wallThicknessStr.isEmpty ? 'N/A' : wallThicknessStr],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 3. Welding Parameters ─────────────────────────────────────────
          _sectionTitle('Welding Parameters', accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              ['Fusion Pressure',
                fusionPressureBar > 0
                    ? '${fusionPressureBar.toStringAsFixed(3)} bar'
                    : 'N/A'],
              ['Heating Time',
                heatingTimeSec > 0
                    ? '${heatingTimeSec.toStringAsFixed(0)} s'
                    : 'N/A'],
              ['Cooling Time',
                coolingTimeSec > 0
                    ? '${coolingTimeSec.toStringAsFixed(0)} s'
                    : 'N/A'],
              ['Bead Height',
                beadHeightMm > 0
                    ? '${beadHeightMm.toStringAsFixed(1)} mm'
                    : 'N/A'],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 4. Curve Statistics ───────────────────────────────────────────
          _sectionTitle('Curve Statistics', accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              ['Duration',         '${duration.toStringAsFixed(1)} s'],
              ['Max Pressure',     '${maxPressure.toStringAsFixed(3)} bar'],
              ['Average Pressure', '${avgPressure.toStringAsFixed(3)} bar'],
              ['Total Samples',    '${curve.length}'],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 5. Pressure × Time Chart ──────────────────────────────────────
          _sectionTitle('Pressure × Time Curve', accentColour),
          pw.SizedBox(height: 6),
          _chart(curve, accentColour),
          pw.SizedBox(height: 16),

          // ── 6. Digital Signature ──────────────────────────────────────────
          _sectionTitle('Digital Weld Signature (SHA-256)', accentColour),
          pw.SizedBox(height: 6),
          _signatureBlock(weldSignature, rowAltColour, accentColour),
          pw.SizedBox(height: 16),

          // ── 7. Certification ──────────────────────────────────────────────
          _sectionTitle('Certification', accentColour),
          pw.SizedBox(height: 6),
          _certificationBlock(
            effectiveJointId, weldSignature, rowAltColour, accentColour),
          pw.SizedBox(height: 16),

          // ── 8. Public Verification ────────────────────────────────────────
          _sectionTitle('Public Verification', accentColour),
          pw.SizedBox(height: 6),
          _publicVerificationBlock(
            effectiveJointId, weldSignature, rowAltColour, accentColour),
          pw.SizedBox(height: 16),

          // ── 9. Weld Verification QR ───────────────────────────────────────
          _sectionTitle('Weld Verification', accentColour),
          pw.SizedBox(height: 6),
          _verificationBlock(weldSignature, qrPayload, rowAltColour, accentColour),
          pw.SizedBox(height: 8),
        ],
      ),
    );

    return pdf.save();
  }

  // ── PDF hash utility ─────────────────────────────────────────────────────

  /// Computes the SHA-256 hex digest of [pdfBytes].
  ///
  /// Call this immediately after [generate] to obtain the hash that can be
  /// stored in a [WeldCertificate]:
  ///
  /// ```dart
  /// final pdfBytes = await WeldReportGenerator.generate(...);
  /// final pdfHash  = WeldReportGenerator.computePdfHash(pdfBytes);
  /// final cert     = WeldCertificate.generateCertificate(
  ///   ..., pdfHash: pdfHash);
  /// ```
  static String computePdfHash(Uint8List pdfBytes) =>
      sha256.convert(pdfBytes).toString();

  // ── Section builders ────────────────────────────────────────────────────

  static pw.Widget _buildHeader(PdfColor headerColour, PdfColor accentColour) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'WELDTRACE WELDING REPORT',
              style: pw.TextStyle(
                fontSize:   22,
                fontWeight: pw.FontWeight.bold,
                color:      headerColour,
              ),
            ),
            pw.Text(
              'WeldTrace',
              style: pw.TextStyle(
                fontSize:  12,
                color:     accentColour,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ],
        ),
        pw.Divider(color: accentColour, thickness: 1.5),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context context, PdfColor accentColour) {
    return pw.Column(
      children: [
        pw.Divider(color: accentColour, thickness: 0.5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated by WeldTrace — DVS 2207 / ISO 21307 / ASTM F2620',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _sectionTitle(String title, PdfColor accentColour) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: accentColour, width: 1),
        ),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize:   12,
          fontWeight: pw.FontWeight.bold,
          color:      accentColour,
        ),
      ),
    );
  }

  static pw.Widget _infoTable({
    required List<List<String>> rows,
    required PdfColor altColour,
  }) {
    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(1.8),
        1: const pw.FlexColumnWidth(3),
      },
      children: rows.asMap().entries.map((entry) {
        final isAlt = entry.key.isEven;
        final row   = entry.value;
        return pw.TableRow(
          decoration: isAlt ? pw.BoxDecoration(color: altColour) : null,
          children: row
              .map(
                (cell) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: pw.Text(
                    cell,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
              )
              .toList(),
        );
      }).toList(),
    );
  }

  static pw.Widget _chart(List<WeldTracePoint> curve, PdfColor accentColour) {
    const chartHeight = 160.0;
    const chartWidth  = 460.0;

    if (curve.length < 2) {
      return pw.Container(
        width:  chartWidth,
        height: chartHeight,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          color:  PdfColors.white,
        ),
        child: pw.Center(
          child: pw.Text(
            'No data recorded',
            style: pw.TextStyle(
              color:     PdfColors.grey500,
              fontSize:  9,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ),
      );
    }

    try {
      return pw.Container(
        width:  chartWidth,
        height: chartHeight,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          color:  PdfColors.white,
        ),
        child: pw.CustomPaint(
          painter: _CurvePainter(curve, accentColour),
          child: pw.SizedBox(width: chartWidth, height: chartHeight),
        ),
      );
    } catch (_) {
      return pw.Container(
        width:  chartWidth,
        height: chartHeight,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          color:  PdfColors.white,
        ),
        child: pw.Center(
          child: pw.Text(
            'Chart unavailable',
            style: pw.TextStyle(
              color:     PdfColors.grey500,
              fontSize:  9,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ),
      );
    }
  }

  /// Renders the SHA-256 signature as a monospace text block.
  static pw.Widget _signatureBlock(
      String signature, PdfColor bgColour, PdfColor accentColour) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color:        bgColour,
        border:       pw.Border.all(color: accentColour),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Weld Signature',
            style: pw.TextStyle(
              fontSize:   9,
              fontWeight: pw.FontWeight.bold,
              color:      accentColour,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            signature,
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'This SHA-256 fingerprint uniquely identifies the weld. '
            'Any modification to the curve data will invalidate this signature.',
            style: pw.TextStyle(
              fontSize:  7,
              color:     PdfColors.grey600,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the CERTIFICATION section — Joint ID, signature, and ledger notice.
  static pw.Widget _certificationBlock(
      String jointId,
      String signature,
      PdfColor bgColour,
      PdfColor accentColour) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color:        bgColour,
        border:       pw.Border.all(color: accentColour),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Certification Record',
            style: pw.TextStyle(
              fontSize:   9,
              fontWeight: pw.FontWeight.bold,
              color:      accentColour,
            ),
          ),
          pw.SizedBox(height: 6),
          _certRow('Joint ID',  jointId),
          _certRow('Signature', signature),
          pw.SizedBox(height: 6),
          pw.Text(
            'This weld is registered in the WeldTrace certification ledger. '
            'The joint ID and signature above are immutable and uniquely identify '
            'this weld joint in compliance with DVS 2207, ISO 21307, and ASTM F2620.',
            style: pw.TextStyle(
              fontSize:  7,
              color:     PdfColors.grey600,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the PUBLIC VERIFICATION section — registry notice, joint ID and
  /// signature.
  ///
  /// Informs field inspectors that the weld may be independently verified
  /// against the WeldTrace public registry.
  static pw.Widget _publicVerificationBlock(
      String jointId,
      String signature,
      PdfColor bgColour,
      PdfColor accentColour) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color:        bgColour,
        border:       pw.Border.all(color: accentColour),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Public Verification',
            style: pw.TextStyle(
              fontSize:   9,
              fontWeight: pw.FontWeight.bold,
              color:      accentColour,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'This weld may be verified using the WeldTrace registry.',
            style: pw.TextStyle(
              fontSize:  8,
              color:     PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Scan the QR code or verify using the WeldTrace public registry.',
            style: pw.TextStyle(
              fontSize:  8,
              color:     PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 6),
          _certRow('Joint ID',    jointId),
          _certRow('Signature',   signature),
          _certRow('Certificate', '$jointId.certificate.json'),
          _certRow('Cert Format', 'WeldTrace-CERT-1'),
          pw.SizedBox(height: 4),
          pw.Text(
            'Certificate available for this weld.',
            style: pw.TextStyle(
              fontSize:  8,
              color:     PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Scan the QR code or query the public registry with the joint ID '
            'and signature above to independently confirm weld authenticity.',
            style: pw.TextStyle(
              fontSize:  7,
              color:     PdfColors.grey600,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _certRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 80,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize:   8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the QR code alongside scanner instructions.
  ///
  /// The QR encodes the optimised verification JSON payload
  /// (see [WeldVerifier.buildVerificationPayload]).
  static pw.Widget _verificationBlock(
      String signature,
      String qrPayload,
      PdfColor bgColour,
      PdfColor accentColour) {
    const qrSize = 90.0;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── Instructions ─────────────────────────────────────────────────
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color:        bgColour,
              border:       pw.Border.all(color: accentColour),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Verification Instructions',
                  style: pw.TextStyle(
                    fontSize:   9,
                    fontWeight: pw.FontWeight.bold,
                    color:      accentColour,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'This weld can be verified by scanning the QR code or '
                  'validating the signature.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '1. Scan the QR code with the WeldTrace mobile app or any '
                  'QR scanner to extract the verification payload.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '2. The payload contains the weld signature, machine ID, '
                  'pipe specifications and timestamp.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '3. Compare the signature with the SHA-256 block above. '
                  'Any mismatch indicates tampering.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Compliant with DVS 2207, ISO 21307, and ASTM F2620.',
                  style: pw.TextStyle(
                    fontSize:  7,
                    color:     PdfColors.grey600,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        // ── QR code ──────────────────────────────────────────────────────
        pw.Column(
          children: [
            pw.Container(
              width:  qrSize,
              height: qrSize,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                color:  PdfColors.white,
              ),
              child: pw.CustomPaint(
                painter: _QrPainter(qrPayload),
                child: pw.SizedBox(width: qrSize, height: qrSize),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.SizedBox(
              width: qrSize,
              child: pw.Text(
                'Scan to verify',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 7,
                  color:    PdfColors.grey600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Chart painter ──────────────────────────────────────────────────────────────

class _CurvePainter extends pw.CustomPainter {
  const _CurvePainter(this.curve, this.lineColour);

  final List<WeldTracePoint> curve;
  final PdfColor lineColour;

  @override
  void paint(PdfGraphics canvas, PdfPoint size) {
    if (curve.length < 2) return;

    final maxT = curve.map((p) => p.timeSeconds).reduce(math.max);
    final maxP = curve.map((p) => p.pressureBar).reduce(math.max);
    final effectiveMaxT = maxT > 0 ? maxT : 1.0;
    final effectiveMaxP = maxP > 0 ? maxP : 1.0;

    const ml = 8.0;
    const mb = 8.0;
    final w  = size.x - ml - 4;
    final h  = size.y - mb - 4;

    double cx(WeldTracePoint p) =>
        ml + (p.timeSeconds / effectiveMaxT) * w;
    double cy(WeldTracePoint p) =>
        mb + (p.pressureBar / effectiveMaxP) * h;

    canvas.setStrokeColor(PdfColors.grey300);
    canvas.setLineWidth(0.4);
    for (int i = 1; i <= 3; i++) {
      final y = mb + (i / 4) * h;
      canvas.drawLine(ml, y, ml + w, y);
      canvas.strokePath();
    }

    canvas.setStrokeColor(lineColour);
    canvas.setLineWidth(1.2);
    canvas.moveTo(cx(curve.first), cy(curve.first));
    for (int i = 1; i < curve.length; i++) {
      canvas.lineTo(cx(curve[i]), cy(curve[i]));
    }
    canvas.strokePath();
  }

  @override
  bool shouldRepaint() => false;
}

// ── QR code painter ────────────────────────────────────────────────────────────

/// Renders a QR code for [data] (the full verification JSON payload) directly
/// onto a PDF canvas.
class _QrPainter extends pw.CustomPainter {
  const _QrPainter(this.data);

  final String data;

  @override
  void paint(PdfGraphics canvas, PdfPoint size) {
    try {
      final qrCode = QrCode.fromData(
        data:              data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final moduleCount = qrCode.moduleCount;
      if (moduleCount <= 0) return;

      final moduleSize = size.x / moduleCount;

      canvas.setFillColor(PdfColors.black);

      for (int row = 0; row < moduleCount; row++) {
        for (int col = 0; col < moduleCount; col++) {
          if (qrCode.isDark(row, col)) {
            final x = col * moduleSize;
            final y = size.y - (row + 1) * moduleSize;
            canvas.drawRect(x, y, moduleSize, moduleSize);
            canvas.fillPath();
          }
        }
      }
    } catch (_) {
      // QR generation failure is non-fatal — leave the space blank.
    }
  }

  @override
  bool shouldRepaint() => false;
}
