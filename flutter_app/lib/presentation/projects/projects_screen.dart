import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../di/providers.dart';
import '../../data/local/database/app_database.dart';
import '../widgets/status_badge.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/logo_symbol.png', height: 28),
            const SizedBox(width: 10),
            const Text('Projects'),
          ],
        ),
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
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: StreamBuilder<List<ProjectRecord>>(
        stream: db.projectsDao.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.sertecRed),
            );
          }
          final projects = snapshot.data ?? [];
          if (projects.isEmpty) {
            return _EmptyState(
              message: authState.isAuthenticated
                  ? 'No projects yet.\nTap the sync icon to pull your assigned projects.'
                  : 'Sign in to see your projects.',
            );
          }
          return ListView.builder(
            itemCount: projects.length,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemBuilder: (context, i) => _ProjectCard(project: projects[i]),
          );
        },
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final ProjectRecord project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = project.status == 'active';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isActive
              ? () => context.push('/projects/${project.id}/weld/setup')
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // ── Icon ──────────────────────────────────────────────────
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.sertecRed.withOpacity(0.09)
                        : AppColors.lightGray,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.account_tree_outlined,
                    size: 22,
                    color: isActive
                        ? AppColors.sertecRed
                        : AppColors.neutralGray,
                  ),
                ),
                const SizedBox(width: 14),

                // ── Content ───────────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      if (project.location != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13,
                                color: AppColors.neutralGray),
                            const SizedBox(width: 3),
                            Text(
                              project.location!,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.neutralGray,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      if (isActive)
                        const Text(
                          'Tap to start a new weld →',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.sertecRed,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Status badge ──────────────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusBadge(
                      label: project.status,
                      status: isActive ? BadgeStatus.active : BadgeStatus.inactive,
                    ),
                    if (isActive) ...[
                      const SizedBox(height: 8),
                      Icon(Icons.chevron_right,
                          color: AppColors.sertecRed.withOpacity(0.6)),
                    ],
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
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.sertecRed.withOpacity(0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                size: 36,
                color: AppColors.sertecRed,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.neutralGray,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
