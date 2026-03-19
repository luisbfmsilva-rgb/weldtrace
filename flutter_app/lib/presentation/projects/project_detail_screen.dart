import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';
import '../widgets/status_badge.dart';
import 'project_form.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  ProjectRecord? _project;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final p = await db.projectsDao.getById(widget.projectId);
    setState(() { _project = p; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_project == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Project not found')));
    }

    final p = _project!;
    final isActive = p.status == 'active';

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProjectFormScreen(existing: p),
              ));
              _load(); // refresh after edit
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(p.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                StatusBadge(
                  label: p.status,
                  status: isActive ? BadgeStatus.active : BadgeStatus.inactive,
                ),
              ]),
              const SizedBox(height: 8),
              if (p.clientName != null) _Meta(Icons.business_outlined, p.clientName!),
              if (p.location != null) _Meta(Icons.location_on_outlined, p.location!),
              if (p.contractNumber != null) _Meta(Icons.tag_outlined, 'Contract: ${p.contractNumber}'),
              if (p.description != null) ...[
                const SizedBox(height: 8),
                Text(p.description!, style: const TextStyle(color: AppColors.neutralGray, fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(height: 8),

          // ── Welds in this project ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Text('Welds', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              if (isActive)
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New Weld'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.sertecRed),
                  onPressed: () => context.push(
                    '/weld/setup',
                    extra: {'preselectedProjectId': p.id},
                  ),
                ),
            ]),
          ),

          Expanded(
            child: StreamBuilder<List<WeldRecord>>(
              stream: ref.watch(databaseProvider).weldsDao.watchByProject(p.id),
              builder: (context, snapshot) {
                final welds = snapshot.data ?? [];
                if (welds.isEmpty) {
                  return _EmptyWelds(
                    isActive: isActive,
                    onNew: () => context.push(
                      '/weld/setup',
                      extra: {'preselectedProjectId': p.id},
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: welds.length,
                  itemBuilder: (context, i) => _WeldRow(
                    weld: welds[i],
                    onTap: () => context.push('/welds/${welds[i].id}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isActive
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.sertecRed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.local_fire_department),
              label: const Text('New Weld'),
              onPressed: () => context.push(
                '/weld/setup',
                extra: {'preselectedProjectId': p.id},
              ),
            )
          : null,
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, size: 14, color: AppColors.neutralGray),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 13, color: AppColors.neutralGray)),
        ]),
      );
}

class _WeldRow extends StatelessWidget {
  const _WeldRow({required this.weld, required this.onTap});
  final WeldRecord weld;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy HH:mm');
    final statusColor = switch (weld.status) {
      'completed' => const Color(0xFF2E7D32),
      'in_progress' => AppColors.sertecRed,
      _ => AppColors.neutralGray,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
        ),
        child: Row(children: [
          Icon(Icons.local_fire_department, color: statusColor, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${weld.pipeMaterial} Ø${weld.pipeDiameter.toStringAsFixed(0)} mm',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(fmt.format(weld.startedAt.toLocal()),
                style: const TextStyle(fontSize: 11, color: AppColors.neutralGray)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
            child: Text(weld.status.toUpperCase().replaceAll('_', ' '),
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: AppColors.neutralGray, size: 18),
        ]),
      ),
    );
  }
}

class _EmptyWelds extends StatelessWidget {
  const _EmptyWelds({required this.isActive, required this.onNew});
  final bool isActive;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.local_fire_department_outlined, size: 40, color: AppColors.neutralGray),
          const SizedBox(height: 12),
          const Text('No welds in this project yet.',
              style: TextStyle(color: AppColors.neutralGray, fontSize: 13)),
          if (isActive) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Start First Weld'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.sertecRed),
              onPressed: onNew,
            ),
          ],
        ]),
      );
}
