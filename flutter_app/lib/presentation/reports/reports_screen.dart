import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _projectFilter = 'all';
  List<ProjectRecord> _projects = [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final db = ref.read(databaseProvider);
    final projects = await db.projectsDao.getAll();
    if (mounted) setState(() => _projects = projects);
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(title: const Text('Reports')),
      body: Column(
        children: [
          // ── Project filter ────────────────────────────────────────────
          _ProjectFilter(
            projects: _projects,
            selected: _projectFilter,
            onChanged: (v) => setState(() => _projectFilter = v),
          ),

          // ── Completed welds list ──────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<WeldRecord>>(
              stream: db.weldsDao.watchCompleted(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.sertecRed));
                }
                var welds = snapshot.data ?? [];
                if (_projectFilter != 'all') {
                  welds = welds.where((w) => w.projectId == _projectFilter).toList();
                }
                if (welds.isEmpty) {
                  return const _EmptyReports();
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: welds.length,
                  itemBuilder: (ctx, i) => _ReportCard(
                    weld: welds[i],
                    onView: () => context.push('/welds/${welds[i].id}'),
                    onShare: welds[i].tracePdf != null
                        ? () => _share(welds[i].tracePdf!)
                        : null,
                    onPrint: welds[i].tracePdf != null
                        ? () => _print(welds[i].tracePdf!)
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _share(Uint8List bytes) async {
    final file = XFile.fromData(bytes,
        mimeType: 'application/pdf', name: 'weld_certificate.pdf');
    await Share.shareXFiles([file], text: 'Sertec FusionCertify™ — Weld Certificate');
  }

  Future<void> _print(Uint8List bytes) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}

// ── Project filter ─────────────────────────────────────────────────────────────

class _ProjectFilter extends StatelessWidget {
  const _ProjectFilter({
    required this.projects,
    required this.selected,
    required this.onChanged,
  });

  final List<ProjectRecord> projects;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          const Text('Project:', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All Projects')),
                  ...projects.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))),
                ],
                onChanged: (v) => onChanged(v ?? 'all'),
              ),
            ),
          ),
        ]),
      );
}

// ── Report card ────────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.weld,
    required this.onView,
    this.onShare,
    this.onPrint,
  });

  final WeldRecord weld;
  final VoidCallback onView;
  final VoidCallback? onShare;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.description, color: Color(0xFF2E7D32), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${weld.pipeMaterial} — Ø${weld.pipeDiameter.toStringAsFixed(0)} mm',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                if (weld.pipeSdr != null)
                  Text('SDR ${weld.pipeSdr}',
                      style: const TextStyle(fontSize: 12, color: AppColors.neutralGray)),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.neutralGray),
            ]),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.neutralGray),
              const SizedBox(width: 4),
              Text(
                weld.completedAt != null ? fmt.format(weld.completedAt!.toLocal()) : '-',
                style: const TextStyle(fontSize: 11, color: AppColors.neutralGray),
              ),
              const Spacer(),
              if (weld.traceSignature != null)
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified, size: 14, color: Color(0xFF2E7D32)),
                  SizedBox(width: 4),
                  Text('Certified', style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                ]),
            ]),
            if (onShare != null || onPrint != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                if (onPrint != null) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: const Text('Print'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.sertecRed,
                      side: const BorderSide(color: AppColors.sertecRed),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onPrint,
                  ),
                  const SizedBox(width: 8),
                ],
                if (onShare != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: const Text('Share'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.sertecRed,
                      side: const BorderSide(color: AppColors.sertecRed),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onShare,
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyReports extends StatelessWidget {
  const _EmptyReports();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.sertecRed.withValues(alpha: 0.07), shape: BoxShape.circle),
            child: const Icon(Icons.description_outlined, size: 36, color: AppColors.sertecRed),
          ),
          const SizedBox(height: 16),
          const Text('No completed welds yet.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Complete welds to generate certificates and reports.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.neutralGray)),
        ]),
      );
}
