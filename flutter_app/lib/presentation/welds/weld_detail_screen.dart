import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';
import '../../services/welding_trace/weld_trace_recorder.dart';

class WeldDetailScreen extends ConsumerStatefulWidget {
  const WeldDetailScreen({super.key, required this.weldId});
  final String weldId;

  @override
  ConsumerState<WeldDetailScreen> createState() => _WeldDetailScreenState();
}

class _WeldDetailScreenState extends ConsumerState<WeldDetailScreen> {
  WeldRecord? _weld;
  ProjectRecord? _project;
  MachineRecord? _machine;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final weld = await db.weldsDao.getById(widget.weldId);
    if (weld == null) {
      setState(() => _loading = false);
      return;
    }
    final project = await db.projectsDao.getById(weld.projectId);
    final machine = await db.machinesDao.getById(weld.machineId);
    setState(() {
      _weld = weld;
      _project = project;
      _machine = machine;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_weld == null) {
      return Scaffold(appBar: AppBar(title: const Text('Weld')),
          body: const Center(child: Text('Weld not found')));
    }

    final weld = _weld!;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final isCompleted = weld.status == 'completed';

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        title: Text('Weld — Ø${weld.pipeDiameter.toStringAsFixed(0)} mm ${weld.pipeMaterial}'),
        actions: [
          if (isCompleted && weld.tracePdf != null) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share PDF',
              onPressed: () => _sharePdf(weld.tracePdf!),
            ),
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Print / Save PDF',
              onPressed: () => _printPdf(weld.tracePdf!),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status banner ────────────────────────────────────────────
          _StatusBanner(status: weld.status),
          const SizedBox(height: 16),

          // ── Weld data ────────────────────────────────────────────────
          _InfoCard(title: 'Weld Data', rows: [
            ('Material', weld.pipeMaterial),
            ('Diameter', 'Ø${weld.pipeDiameter.toStringAsFixed(0)} mm'),
            if (weld.pipeSdr != null) ('SDR', weld.pipeSdr!),
            if (weld.pipeWallThickness != null)
              ('Wall Thickness', '${weld.pipeWallThickness!.toStringAsFixed(2)} mm'),
            ('Weld Type', weld.weldType.replaceAll('_', ' ').toUpperCase()),
            if (weld.standardUsed != null) ('Standard', weld.standardUsed!),
            if (weld.ambientTemperature != null)
              ('Ambient Temp.', '${weld.ambientTemperature!.toStringAsFixed(1)} °C'),
          ]),
          const SizedBox(height: 12),

          // ── Project & Machine ────────────────────────────────────────
          _InfoCard(title: 'Project & Machine', rows: [
            if (_project != null) ('Project', _project!.name),
            if (_project?.clientName != null) ('Client', _project!.clientName!),
            if (_machine != null)
              ('Machine', '${_machine!.manufacturer} ${_machine!.model}'),
            if (_machine != null) ('S/N', _machine!.serialNumber),
          ]),
          const SizedBox(height: 12),

          // ── Timeline ─────────────────────────────────────────────────
          _InfoCard(title: 'Timeline', rows: [
            ('Started', fmt.format(weld.startedAt.toLocal())),
            if (weld.completedAt != null)
              ('Completed', fmt.format(weld.completedAt!.toLocal())),
          ]),
          const SizedBox(height: 12),

          // ── Pressure–time graph ──────────────────────────────────────
          if (isCompleted) _GraphSection(weldId: weld.id),
          const SizedBox(height: 12),

          // ── Traceability ─────────────────────────────────────────────
          if (isCompleted && weld.traceSignature != null)
            _TraceabilityCard(weld: weld),
          const SizedBox(height: 12),

          // ── QR code ──────────────────────────────────────────────────
          if (isCompleted && weld.jointId != null && weld.traceSignature != null)
            _QRCard(weld: weld),
          const SizedBox(height: 16),

          // ── Actions ──────────────────────────────────────────────────
          if (isCompleted && weld.tracePdf != null)
            FilledButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Share Certificate PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.sertecRed,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _sharePdf(weld.tracePdf!),
            ),
        ],
      ),
    );
  }

  Future<void> _sharePdf(Uint8List bytes) async {
    final file = XFile.fromData(bytes, mimeType: 'application/pdf',
        name: 'weld_certificate_${widget.weldId.substring(0, 8)}.pdf');
    await Share.shareXFiles([file], text: 'Sertec FusionCertify™ — Weld Certificate');
  }

  Future<void> _printPdf(Uint8List bytes) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}

// ── Status banner ──────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      'completed' => (const Color(0xFF2E7D32), Icons.check_circle, 'COMPLETED & CERTIFIED'),
      'in_progress' => (AppColors.sertecRed, Icons.pending, 'IN PROGRESS'),
      'failed' => (Colors.orange, Icons.warning_rounded, 'FAILED'),
      _ => (AppColors.neutralGray, Icons.cancel_outlined, status.toUpperCase()),
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
    );
  }
}

// ── Info card ──────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.sertecRed)),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 10),
        ...rows.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 130, child: Text(r.$1, style: const TextStyle(color: AppColors.neutralGray, fontSize: 13))),
                Expanded(child: Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              ]),
            )),
      ]),
    );
  }
}

// ── Graph section ──────────────────────────────────────────────────────────────

class _GraphSection extends ConsumerStatefulWidget {
  const _GraphSection({required this.weldId});
  final String weldId;

  @override
  ConsumerState<_GraphSection> createState() => _GraphSectionState();
}

class _GraphSectionState extends ConsumerState<_GraphSection> {
  List<WeldTracePoint>? _points;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final pts = await db.weldsDao.loadTraceCurve(widget.weldId);
    if (mounted) setState(() => _points = pts);
  }

  @override
  Widget build(BuildContext context) {
    if (_points == null) return const SizedBox.shrink();
    if (_points!.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: const Center(child: Text('No pressure data recorded',
            style: TextStyle(color: AppColors.neutralGray))),
      );
    }

    // Build fl_chart spots from historical WeldTracePoint data
    final spots = _points!
        .map((p) => FlSpot(p.timeSeconds, p.pressureBar))
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pressure × Time Graph',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.sertecRed)),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: LineChart(LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFEEEEEE), strokeWidth: 1),
              getDrawingVerticalLine: (_) => const FlLine(color: Color(0xFFEEEEEE), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                axisNameWidget: const Text('Time (s)', style: TextStyle(fontSize: 10, color: AppColors.neutralGray)),
                sideTitles: SideTitles(showTitles: true, reservedSize: 22,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}s', style: const TextStyle(fontSize: 9, color: AppColors.neutralGray))),
              ),
              leftTitles: AxisTitles(
                axisNameWidget: const Text('bar', style: TextStyle(fontSize: 10, color: AppColors.neutralGray)),
                sideTitles: SideTitles(showTitles: true, reservedSize: 32,
                    getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 9, color: AppColors.neutralGray))),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: AppColors.sertecRed,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.sertecRed.withValues(alpha: 0.08),
                ),
              ),
            ],
          )),
        ),
      ]),
    );
  }
}

// ── Traceability card ──────────────────────────────────────────────────────────

class _TraceabilityCard extends StatelessWidget {
  const _TraceabilityCard({required this.weld});
  final WeldRecord weld;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Traceability',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.sertecRed)),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (weld.jointId != null) ...[
            const Text('Joint ID', style: TextStyle(color: AppColors.neutralGray, fontSize: 12)),
            SelectableText(weld.jointId!,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, fontFamily: 'monospace')),
            const SizedBox(height: 8),
          ],
          const Text('Signature (SHA-256)', style: TextStyle(color: AppColors.neutralGray, fontSize: 12)),
          SelectableText(
            (weld.traceSignature ?? '').substring(0, 16) + '…',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, fontFamily: 'monospace'),
          ),
          if (weld.traceQuality != null) ...[
            const SizedBox(height: 8),
            Text('Trace Quality: ${weld.traceQuality}',
                style: TextStyle(
                  fontSize: 12,
                  color: weld.traceQuality == 'OK' ? const Color(0xFF2E7D32) : Colors.orange,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ]),
      );
}

// ── QR card ────────────────────────────────────────────────────────────────────

class _QRCard extends StatelessWidget {
  const _QRCard({required this.weld});
  final WeldRecord weld;

  @override
  Widget build(BuildContext context) {
    final qrData = jsonEncode({
      'jointId': weld.jointId,
      'signature': weld.traceSignature?.substring(0, 32),
      'app': 'SertecFusionCertify',
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('QR Verification Code',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.sertecRed)),
        const SizedBox(height: 4),
        const Text('Scan to verify this weld certificate',
            style: TextStyle(fontSize: 12, color: AppColors.neutralGray)),
        const SizedBox(height: 14),
        Center(
          child: QrImageView(
            data: qrData,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            'Joint ID: ${weld.jointId?.substring(0, 8)}…',
            style: const TextStyle(fontSize: 11, color: AppColors.neutralGray, fontFamily: 'monospace'),
          ),
        ),
      ]),
    );
  }
}
