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
    String machineId               = '',
    String operatorName            = '',
    String operatorId              = '',
    String jointId                 = '',
    String wallThicknessStr        = '',
    String standardUsed            = '',
    double fusionPressureBar        = 0.0,
    double heatingTimeSec           = 0.0,
    double coolingTimeSec           = 0.0,
    double beadHeightMm             = 0.0,
    // ── V1.0 additions ────────────────────────────────────────────────────
    String traceQuality            = 'N/A',
    String machineModel            = '',
    String machineSerialNumber     = '',
    double hydraulicCylinderAreaMm2 = 0.0,
    // ── V1.1 — status & cancellation ─────────────────────────────────────
    /// 'completed' | 'cooling_incomplete' | 'cancelled'
    String completionStatus        = 'completed',
    String cancelReason            = '',
    // ── V1.2 — GPS location ──────────────────────────────────────────────
    double? gpsLat,
    double? gpsLng,
    // ── V1.3 — Branding logos ─────────────────────────────────────────────
    /// Raw PNG/JPEG bytes of the Sertec FusionCertify logo (top-left).
    Uint8List? sertecLogoBytes,
    /// Raw PNG/JPEG bytes of the manager's company logo (top-right).
    Uint8List? companyLogoBytes,
    // ── V1.4 — Extended project / machine metadata ────────────────────────
    String projectLocation        = '',
    String machineBrand           = '',
    String machineLastCalibration = '',
    String machineNextCalibration = '',
    int    weldNumber             = 0,
    // ── V1.4 — Post-weld photos ───────────────────────────────────────────
    Uint8List? weldPhotoBytes,
    Uint8List? welderPhotoBytes,
    Uint8List? alignmentPhotoBytes,
    // ── V1.5 — Observations / notes & nominal (theoretical) curve ─────────
    String notes              = '',
    List<WeldTracePoint> nominalCurve = const [],
    // ── V1.6 — Report language ────────────────────────────────────────────
    /// 'pt' (default) or 'en'.  Translates section titles and row labels.
    String lang               = 'pt',
  }) async {
    // ── Inline translation helper ─────────────────────────────────────────
    final _ptLabels = const <String, String>{
      // Section titles
      'Certified Welding Report': 'Relatório de Soldagem Certificado',
      'Project':               'Projeto',
      'Joint Identification':  'Identificação da Junta',
      'Machine':               'Máquina',
      'Pipe':                  'Tubo',
      'Welding Standard':      'Norma de Soldagem',
      'Weld Parameters':       'Parâmetros de Soldagem',
      'Trace Quality':         'Qualidade do Rastreamento',
      'Curve Statistics':      'Estatísticas da Curva',
      'Signature (SHA-256)':   'Assinatura (SHA-256)',
      'Certificate':           'Certificado',
      'Public Verification':   'Verificação Pública',
      'QR Verification':       'Verificação QR',
      'Assessment':            'Avaliação',
      // Row labels
      'Project Name':          'Nome do Projeto',
      'Date':                  'Data',
      'Operator':              'Soldador',
      'Operator ID':           'ID do Soldador',
      'Location (GPS)':        'Localização (GPS)',
      'Joint ID':              'ID da Junta',
      'Serial Number':         'Número de Série',
      'Machine ID':            'ID da Máquina',
      'Hydraulic Cylinder Area': 'Área do Cilindro Hidráulico',
      'Material':              'Material',
      'Diameter':              'Diâmetro',
      'SDR':                   'SDR',
      'Wall Thickness':        'Espessura de Parede',
      'Standard':              'Norma',
      'Fusion Pressure':       'Pressão de Fusão',
      'Heating Time':          'Tempo de Aquecimento',
      'Cooling Time':          'Tempo de Resfriamento',
      'Bead Height':           'Altura do Cordão',
      'Quality':               'Qualidade',
      'Samples':               'Amostras',
      'Duration':              'Duração',
      'Max Pressure':          'Pressão Máxima',
      'Average Pressure':      'Pressão Média',
      // Assessment messages
      'Welding completed successfully.':
          'Soldagem concluída com sucesso.',
      'Welding completed but cooling phase was ended early. '
          'The joint must be assessed before entering service.':
          'Soldagem concluída, mas o resfriamento foi encerrado antes do tempo. '
          'A junta deve ser avaliada antes de entrar em operação.',
      'Weld cancelled — no reason recorded.':
          'Solda cancelada — nenhum motivo registrado.',
    };
    String t(String key) =>
        lang == 'pt' ? (_ptLabels[key] ?? key) : key;

    final pdf = pw.Document(
      author:  'Sertec FusionCertify',
      title:   'Sertec FusionCertify — Certified Welding Report — $projectName',
      creator: 'Sertec FusionCertify v1.0',
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

    // ── Colour palette (Sertec FusionCertify brand) ────────────────────────
    const headerColour = PdfColor.fromInt(0xFF8B1E2D);
    const accentColour = PdfColor.fromInt(0xFF6E1723);
    const rowAltColour = PdfColor.fromInt(0xFFF5F5F5);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        ),
        header: (context) => _buildHeader(
          headerColour,
          accentColour,
          sertecLogoBytes:   sertecLogoBytes,
          companyLogoBytes:  companyLogoBytes,
          weldNumber:        weldNumber,
          reportTitle:       t('Certified Welding Report'),
        ),
        footer: (context) => _buildFooter(context, accentColour),
        build: (context) => [
          pw.SizedBox(height: 12),

          // ── 1. Project ────────────────────────────────────────────────────
          _sectionTitle(t('Project'), accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              if (weldNumber > 0) ['Solda n°', '$weldNumber'],
              [t('Project Name'), projectName.isEmpty ? 'N/A' : projectName],
              if (projectLocation.isNotEmpty) ['Localização', projectLocation],
              [t('Date'),         dateStr],
              if (operatorName.isNotEmpty) [t('Operator'), operatorName],
              if (operatorId.isNotEmpty)   [t('Operator ID'), operatorId],
              if (gpsLat != null && gpsLng != null)
                [t('Location (GPS)'),
                 '${gpsLat.toStringAsFixed(6)}, ${gpsLng.toStringAsFixed(6)}'],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 2. Joint Identification ───────────────────────────────────────
          _sectionTitle(t('Joint Identification'), accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              [t('Joint ID'), jointId.isEmpty ? 'N/A' : jointId],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 3. Machine ────────────────────────────────────────────────────
          _sectionTitle(t('Machine'), accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              if (machineBrand.isNotEmpty) ['Marca', machineBrand],
              ['Modelo', () {
                if (machineModel.isNotEmpty) return machineModel;
                if (machineName.isNotEmpty)  return machineName;
                return 'N/A';
              }()],
              [t('Serial Number'),
                machineSerialNumber.isNotEmpty ? machineSerialNumber
                    : (machineId.isNotEmpty ? machineId : 'N/A')],
              [t('Machine ID'), machineId.isEmpty ? 'N/A' : machineId],
              [t('Hydraulic Cylinder Area'),
                hydraulicCylinderAreaMm2 > 0
                    ? '${hydraulicCylinderAreaMm2.toStringAsFixed(1)} mm²'
                    : 'N/A'],
              if (machineLastCalibration.isNotEmpty)
                ['Última Calibração', machineLastCalibration],
              if (machineNextCalibration.isNotEmpty)
                ['Próxima Calibração', machineNextCalibration],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 4. Pipe ───────────────────────────────────────────────────────
          _sectionTitle(t('Pipe'), accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              [t('Material'),       material.isEmpty ? 'N/A' : material],
              [t('Diameter'),       '${diameter.toStringAsFixed(1)} mm'],
              [t('SDR'),            sdr.isEmpty ? 'N/A' : sdr],
              [t('Wall Thickness'), wallThicknessStr.isEmpty ? 'N/A' : wallThicknessStr],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 5. Welding Standard ───────────────────────────────────────────
          _sectionTitle(t('Welding Standard'), accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              [t('Standard'), standardUsed.isEmpty ? 'N/A' : standardUsed],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 6. Weld Parameters ────────────────────────────────────────────
          _sectionTitle(t('Weld Parameters'), accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              [t('Fusion Pressure'),
                fusionPressureBar > 0
                    ? '${fusionPressureBar.toStringAsFixed(3)} bar'
                    : 'N/A'],
              [t('Heating Time'),
                heatingTimeSec > 0
                    ? '${heatingTimeSec.toStringAsFixed(0)} s'
                    : 'N/A'],
              [t('Cooling Time'),
                coolingTimeSec > 0
                    ? '${(coolingTimeSec / 60).toStringAsFixed(1)} min'
                    : 'N/A'],
              [t('Bead Height'),
                beadHeightMm > 0
                    ? '${beadHeightMm.toStringAsFixed(1)} mm'
                    : 'N/A'],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 7. Trace Quality ──────────────────────────────────────────────
          _sectionTitle(t('Trace Quality'), accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              [t('Quality'), _traceQualityLabel(traceQuality)],
              [t('Samples'), '${curve.length}'],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 8. Curve Statistics ───────────────────────────────────────────
          _sectionTitle(t('Curve Statistics'), accentColour),
          pw.SizedBox(height: 6),
          _infoTable(
            rows: [
              [t('Duration'),         '${duration.toStringAsFixed(1)} s'],
              [t('Max Pressure'),     '${maxPressure.toStringAsFixed(3)} bar'],
              [t('Average Pressure'), '${avgPressure.toStringAsFixed(3)} bar'],
            ],
            altColour: rowAltColour,
          ),
          pw.SizedBox(height: 16),

          // ── 9. Pressure × Time Chart ──────────────────────────────────────
          _sectionTitle('Curva Pressão × Tempo', accentColour),
          pw.SizedBox(height: 6),
          _chart(curve, accentColour, nominalCurve: nominalCurve),
          pw.SizedBox(height: 16),

          // ── 10. Signature ──────────────────────────────────────────────────
          _sectionTitle(t('Signature (SHA-256)'), accentColour),
          pw.SizedBox(height: 6),
          _signatureBlock(weldSignature, rowAltColour, accentColour),
          pw.SizedBox(height: 16),

          // ── 11. Certificate ────────────────────────────────────────────────
          _sectionTitle(t('Certificate'), accentColour),
          pw.SizedBox(height: 6),
          _certificationBlock(
            effectiveJointId, weldSignature, rowAltColour, accentColour),
          pw.SizedBox(height: 16),

          // ── 12. Public Verification ────────────────────────────────────────
          _sectionTitle(t('Public Verification'), accentColour),
          pw.SizedBox(height: 6),
          _publicVerificationBlock(
            effectiveJointId, weldSignature, rowAltColour, accentColour),
          pw.SizedBox(height: 16),

          // ── 13. QR Verification ────────────────────────────────────────────
          _sectionTitle(t('QR Verification'), accentColour),
          pw.SizedBox(height: 6),
          _verificationBlock(weldSignature, qrPayload, rowAltColour, accentColour),
          pw.SizedBox(height: 16),

          // ── 14. Assessment ─────────────────────────────────────────────────
          _sectionTitle(t('Assessment'), accentColour),
          pw.SizedBox(height: 6),
          _assessmentBlock(completionStatus, cancelReason, t),
          pw.SizedBox(height: 8),

          // ── 14b. Observations / notes (optional) ───────────────────────────
          if (notes.trim().isNotEmpty) ...[
            _sectionTitle('Observações', accentColour),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: rowAltColour,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Text(
                notes.trim(),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.SizedBox(height: 16),
          ],

          // ── 15. Alignment photo (optional, from preparation step 4) ────────
          if (alignmentPhotoBytes != null) ...[
            _sectionTitle('Foto — Tubagens Alinhadas', accentColour),
            pw.SizedBox(height: 6),
            pw.ClipRRect(
              horizontalRadius: 4,
              verticalRadius: 4,
              child: pw.Image(
                pw.MemoryImage(alignmentPhotoBytes),
                width:  PdfPageFormat.a4.availableWidth,
                height: 200,
                fit:    pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 16),
          ],

          // ── 16. Weld bead photo (optional) ─────────────────────────────────
          if (weldPhotoBytes != null) ...[
            _sectionTitle('Foto — Cordão de Solda', accentColour),
            pw.SizedBox(height: 6),
            pw.ClipRRect(
              horizontalRadius: 4,
              verticalRadius: 4,
              child: pw.Image(
                pw.MemoryImage(weldPhotoBytes),
                width:  PdfPageFormat.a4.availableWidth,
                height: 200,
                fit:    pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 16),
          ],

          // ── 17. Welder photo (optional) ────────────────────────────────────
          if (welderPhotoBytes != null) ...[
            _sectionTitle('Foto — Soldador', accentColour),
            pw.SizedBox(height: 6),
            pw.ClipRRect(
              horizontalRadius: 4,
              verticalRadius: 4,
              child: pw.Image(
                pw.MemoryImage(welderPhotoBytes),
                width:  200,
                height: 200,
                fit:    pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 8),
          ],
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

  // ── Assessment block ─────────────────────────────────────────────────────

  static pw.Widget _assessmentBlock(
    String status,
    String cancelReason,
    String Function(String) t,
  ) {
    const successColour  = PdfColor.fromInt(0xFF1B5E20);
    const warningColour  = PdfColor.fromInt(0xFFE65100);
    const errorColour    = PdfColor.fromInt(0xFFB71C1C);

    final colour = switch (status) {
      'completed'          => successColour,
      'cooling_incomplete' => warningColour,
      _                   => errorColour,
    };

    final icon = switch (status) {
      'completed' => 'OK',
      _           => 'XX',
    };

    final message = switch (status) {
      'completed'          => t('Welding completed successfully.'),
      'cooling_incomplete' => t(
          'Welding completed but cooling phase was ended early. '
          'The joint must be assessed before entering service.',
        ),
      _                   => cancelReason.isNotEmpty
          ? cancelReason
          : t('Weld cancelled — no reason recorded.'),
    };

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: colour, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$icon  ',
            style: pw.TextStyle(
              color: colour,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              message,
              style: pw.TextStyle(color: colour, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section builders ────────────────────────────────────────────────────────

  static pw.Widget _buildHeader(
    PdfColor headerColour,
    PdfColor accentColour, {
    Uint8List? sertecLogoBytes,
    Uint8List? companyLogoBytes,
    int weldNumber    = 0,
    String reportTitle = 'Certified Welding Report',
  }) {
    final subtitle = weldNumber > 0
        ? '$reportTitle — Solda n° $weldNumber'
        : reportTitle;

    // Left side: logo image (if provided) + fallback text brand
    final leftContent = sertecLogoBytes != null
        ? pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(
                pw.MemoryImage(sertecLogoBytes),
                width:  60,
                height: 60,
                fit: pw.BoxFit.contain,
              ),
              pw.SizedBox(width: 8),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    'Sertec FusionCertify™',
                    style: pw.TextStyle(
                      fontSize:   16,
                      fontWeight: pw.FontWeight.bold,
                      color:      headerColour,
                    ),
                  ),
                  pw.Text(
                    subtitle,
                    style: pw.TextStyle(fontSize: 9, color: accentColour),
                  ),
                ],
              ),
            ],
          )
        : pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Sertec FusionCertify™',
                style: pw.TextStyle(
                  fontSize:   20,
                  fontWeight: pw.FontWeight.bold,
                  color:      headerColour,
                ),
              ),
              pw.Text(
                subtitle,
                style: pw.TextStyle(fontSize: 11, color: accentColour),
              ),
            ],
          );

    // Right side: company logo (if provided) or domain text
    final rightContent = companyLogoBytes != null
        ? pw.Image(
            pw.MemoryImage(companyLogoBytes),
            width:  72,
            height: 60,
            fit: pw.BoxFit.contain,
          )
        : pw.Text(
            'sertec.pt',
            style: pw.TextStyle(
              fontSize:  9,
              color:     PdfColors.grey500,
              fontStyle: pw.FontStyle.italic,
            ),
          );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [leftContent, rightContent],
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
              'Powered by Sertec FusionCertify™  ·  DVS 2207 / ISO 21307 / ASTM F2620',
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

  /// Maps an internal trace-quality code to a human-readable PDF label.
  static String _traceQualityLabel(String quality) {
    switch (quality) {
      case 'OK':
        return 'OK — trace curve complete';
      case 'LOW_SAMPLE_COUNT':
        return 'LOW SAMPLE COUNT — insufficient trace data';
      default:
        return quality.isEmpty ? 'N/A' : quality;
    }
  }

  static pw.Widget _chart(
    List<WeldTracePoint> curve,
    PdfColor accentColour, {
    List<WeldTracePoint> nominalCurve = const [],
  }) {
    const chartHeight  = 150.0;
    const chartWidth   = 440.0;
    const yLabelWidth  = 22.0;
    final axisStyle    = pw.TextStyle(fontSize: 7, color: PdfColors.grey600);

    pw.Widget chartBody;
    // Show the theoretical curve even when no actual data was recorded.
    final hasActual  = curve.length >= 2;
    final hasNominal = nominalCurve.length >= 2;
    if (!hasActual && !hasNominal) {
      chartBody = pw.Container(
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
    } else {
      try {
        chartBody = pw.Container(
          width:  chartWidth,
          height: chartHeight,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            color:  PdfColors.white,
          ),
          child: pw.CustomPaint(
            painter: _curvePainter(
              curve,
              accentColour,
              nominalCurve: nominalCurve,
            ),
            child: pw.SizedBox(width: chartWidth, height: chartHeight),
          ),
        );
      } catch (_) {
        chartBody = pw.Container(
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

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // ── Y-axis label (rotated) ──────────────────────────────────────
            pw.SizedBox(
              width:  yLabelWidth,
              height: chartHeight,
              child: pw.Center(
                child: pw.Transform.rotate(
                  angle: -1.5708, // -π/2
                  child: pw.Text('Pressao [bar]', style: axisStyle),
                ),
              ),
            ),
            chartBody,
          ],
        ),
        // ── X-axis label ────────────────────────────────────────────────────
        pw.Container(
          width:   yLabelWidth + chartWidth,
          padding: const pw.EdgeInsets.only(left: yLabelWidth, top: 3),
          child: pw.Center(
            child: pw.Text('Time (s)', style: axisStyle),
          ),
        ),
      ],
    );
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
            'This weld is registered in the Sertec FusionCertify™ certification ledger. '
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
            'This weld may be verified using the Sertec FusionCertify™ registry.',
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
                painter: _qrPainter(qrPayload),
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

/// Returns a [pw.CustomPainter] callback that draws the pressure-time curve.
///
/// [pw.CustomPainter] is a function typedef in pdf ≥ 3.11:
///   `typedef CustomPainter = void Function(PdfGraphics, PdfPoint)`
pw.CustomPainter _curvePainter(
  List<WeldTracePoint> curve,
  PdfColor lineColour, {
  List<WeldTracePoint> nominalCurve = const [],
}) =>
    (PdfGraphics canvas, PdfPoint size) {
      final hasActual  = curve.length >= 2;
      final hasNominal = nominalCurve.length >= 2;
      if (!hasActual && !hasNominal) return;

      // Compute scale from all available data.
      final allPoints = [...curve, ...nominalCurve];
      final maxT = allPoints.map((p) => p.timeSeconds).reduce(math.max);
      final maxP = allPoints.map((p) => p.pressureBar).reduce(math.max);
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

      // Grid lines
      canvas.setStrokeColor(PdfColors.grey300);
      canvas.setLineWidth(0.4);
      for (int i = 1; i <= 3; i++) {
        final y = mb + (i / 4) * h;
        canvas.drawLine(ml, y, ml + w, y);
        canvas.strokePath();
      }
      for (int i = 1; i <= 4; i++) {
        final x = ml + (i / 5) * w;
        canvas.drawLine(x, mb, x, mb + h);
        canvas.strokePath();
      }

      // Theoretical (nominal) curve — dashed grey line
      if (hasNominal) {
        canvas.setStrokeColor(PdfColors.blueGrey300);
        canvas.setLineWidth(0.8);
        canvas.moveTo(cx(nominalCurve.first), cy(nominalCurve.first));
        for (int i = 1; i < nominalCurve.length; i++) {
          // Simulate dashes: draw segment, skip one unit
          final x1 = cx(nominalCurve[i - 1]);
          final y1 = cy(nominalCurve[i - 1]);
          final x2 = cx(nominalCurve[i]);
          final y2 = cy(nominalCurve[i]);
          final dx = x2 - x1;
          final dy = y2 - y1;
          final len = math.sqrt(dx * dx + dy * dy);
          if (len == 0) continue;
          const dash = 4.0;
          const gap  = 3.0;
          double t = 0;
          bool draw = true;
          while (t < len) {
            final seg = draw ? dash : gap;
            final t2  = math.min(t + seg, len);
            final px1 = x1 + dx * (t / len);
            final py1 = y1 + dy * (t / len);
            final px2 = x1 + dx * (t2 / len);
            final py2 = y1 + dy * (t2 / len);
            if (draw) {
              canvas.drawLine(px1, py1, px2, py2);
              canvas.strokePath();
            }
            t += seg;
            draw = !draw;
          }
        }
      }

      // Actual (measured) curve — solid coloured line
      if (hasActual) {
        canvas.setStrokeColor(lineColour);
        canvas.setLineWidth(1.2);
        canvas.moveTo(cx(curve.first), cy(curve.first));
        for (int i = 1; i < curve.length; i++) {
          canvas.lineTo(cx(curve[i]), cy(curve[i]));
        }
        canvas.strokePath();
      }
    };

// ── QR code painter ────────────────────────────────────────────────────────────

/// Renders a QR code for [data] (the full verification JSON payload) directly
/// onto a PDF canvas.
pw.CustomPainter _qrPainter(String data) =>
    (PdfGraphics canvas, PdfPoint size) {
      try {
        final qrCode = QrCode.fromData(
          data:              data,
          errorCorrectLevel: QrErrorCorrectLevel.M,
        );
        final qrImage     = QrImage(qrCode);
        final moduleCount = qrImage.moduleCount;
        if (moduleCount <= 0) return;

        final moduleSize = size.x / moduleCount;

        canvas.setFillColor(PdfColors.black);

        for (int row = 0; row < moduleCount; row++) {
          for (int col = 0; col < moduleCount; col++) {
            if (qrImage.isDark(row, col)) {
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
    };
