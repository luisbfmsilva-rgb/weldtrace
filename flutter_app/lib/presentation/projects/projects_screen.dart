import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';
import '../widgets/status_badge.dart';
import 'project_form.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_outlined),
            tooltip: 'Sync',
            onPressed: () async {
              final service = ref.read(syncServiceProvider);
              service.start();
              await service.syncNow();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sync complete')),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<ProjectRecord>>(
        stream: db.projectsDao.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.sertecRed));
          }
          final projects = snapshot.data ?? [];
          if (projects.isEmpty) {
            return _EmptyState(onAdd: () => _openForm(context));
          }
          return ListView.builder(
            itemCount: projects.length,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemBuilder: (context, i) => _ProjectCard(
              project: projects[i],
              onEdit: () => _openForm(context, existing: projects[i]),
              onDelete: () => _delete(context, ref, projects[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.sertecRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
        onPressed: () => _openForm(context),
      ),
    );
  }

  void _openForm(BuildContext context, {ProjectRecord? existing}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProjectFormScreen(existing: existing),
    ));
  }

  void _delete(BuildContext context, WidgetRef ref, ProjectRecord project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: Text('This will permanently delete "${project.name}". This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider).projectsDao.deleteById(project.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Project deleted')),
        );
      }
    }
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onEdit,
    required this.onDelete,
  });

  final ProjectRecord project;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = project.status == 'active';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.055), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/projects/${project.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.sertecRed.withValues(alpha: 0.09) : AppColors.lightGray,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.account_tree_outlined, size: 22,
                      color: isActive ? AppColors.sertecRed : AppColors.neutralGray),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(project.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                      if (project.clientName != null) ...[
                        const SizedBox(height: 2),
                        Row(children: [
                          Icon(Icons.business_outlined, size: 12, color: AppColors.neutralGray),
                          const SizedBox(width: 3),
                          Text(project.clientName!, style: TextStyle(fontSize: 12, color: AppColors.neutralGray)),
                        ]),
                      ],
                      if (project.location != null) ...[
                        const SizedBox(height: 2),
                        Row(children: [
                          Icon(Icons.location_on_outlined, size: 12, color: AppColors.neutralGray),
                          const SizedBox(width: 3),
                          Text(project.location!, style: TextStyle(fontSize: 12, color: AppColors.neutralGray)),
                        ]),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusBadge(
                      label: project.status,
                      status: isActive ? BadgeStatus.active : BadgeStatus.inactive,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: onEdit,
                          child: const Icon(Icons.edit_outlined, size: 18, color: AppColors.neutralGray),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: onDelete,
                          child: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.sertecRed.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open_outlined, size: 36, color: AppColors.sertecRed),
            ),
            const SizedBox(height: 20),
            const Text('No projects yet.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
            const SizedBox(height: 8),
            const Text('Create your first project to start recording welds.',
                style: TextStyle(fontSize: 13, color: AppColors.neutralGray), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(backgroundColor: AppColors.sertecRed),
              icon: const Icon(Icons.add),
              label: const Text('Create Project'),
            ),
          ],
        ),
      ),
    );
  }
}
