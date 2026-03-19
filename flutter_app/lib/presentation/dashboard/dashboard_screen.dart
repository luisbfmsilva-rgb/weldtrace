import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/logo_symbol.png', height: 26),
            const SizedBox(width: 10),
            const Text('FusionCertify™'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_outlined),
            tooltip: 'Verify Weld',
            onPressed: () => context.push('/qr/verify'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Welcome ───────────────────────────────────────────────────
            if (auth.user != null) ...[
              _WelcomeCard(user: auth.user),
              const SizedBox(height: 16),
            ],

            // ── Stats row ─────────────────────────────────────────────────
            _StatsRow(db: db),
            const SizedBox(height: 20),

            // ── Quick actions ─────────────────────────────────────────────
            const _SectionHeader(title: 'Quick Actions'),
            const SizedBox(height: 10),
            _QuickActions(),
            const SizedBox(height: 20),

            // ── Recent welds ──────────────────────────────────────────────
            const _SectionHeader(title: 'Recent Welds'),
            const SizedBox(height: 10),
            _RecentWeldsList(db: db),
          ],
        ),
      ),
    );
  }
}

// ── Welcome card ───────────────────────────────────────────────────────────────

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.user});
  final dynamic user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.sertecRed, AppColors.darkRed],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Olá, ${user.firstName}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  user.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    user.role.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.verified_user, color: Colors.white54, size: 42),
        ],
      ),
    );
  }
}

// ── Stats row ──────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StreamStatCard(
          label: 'Active Projects',
          icon: Icons.folder_open_outlined,
          color: AppColors.sertecRed,
          stream: db.projectsDao.watchAll().map(
            (list) => list.where((p) => p.status == 'active').length.toString(),
          ),
        )),
        const SizedBox(width: 10),
        Expanded(child: _StreamStatCard(
          label: 'Total Welds',
          icon: Icons.local_fire_department_outlined,
          color: const Color(0xFF1565C0),
          stream: db.weldsDao.watchAll().map((list) => list.length.toString()),
        )),
        const SizedBox(width: 10),
        Expanded(child: _StreamStatCard(
          label: 'Machines',
          icon: Icons.precision_manufacturing_outlined,
          color: const Color(0xFF2E7D32),
          stream: db.machinesDao.watchAll().map((list) => list.length.toString()),
        )),
      ],
    );
  }
}

class _StreamStatCard extends StatelessWidget {
  const _StreamStatCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.stream,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Stream<String> stream;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          StreamBuilder<String>(
            stream: stream,
            builder: (_, snap) => Text(
              snap.data ?? '-',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.neutralGray, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ── Quick actions ──────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _ActionButton(
          label: 'New Project',
          icon: Icons.add_circle_outline,
          color: AppColors.sertecRed,
          onTap: () => context.push('/projects/new'),
        )),
        const SizedBox(width: 10),
        Expanded(child: _ActionButton(
          label: 'New Weld',
          icon: Icons.local_fire_department_outlined,
          color: const Color(0xFF1565C0),
          onTap: () => context.push('/weld/setup'),
        )),
        const SizedBox(width: 10),
        Expanded(child: _ActionButton(
          label: 'Add Machine',
          icon: Icons.precision_manufacturing_outlined,
          color: const Color(0xFF2E7D32),
          onTap: () => context.push('/machines/new'),
        )),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent welds ───────────────────────────────────────────────────────────────

class _RecentWeldsList extends StatelessWidget {
  const _RecentWeldsList({required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WeldRecord>>(
      stream: db.weldsDao.watchAll(),
      builder: (context, snapshot) {
        final welds = (snapshot.data ?? []).take(5).toList();
        if (welds.isEmpty) {
          return const _EmptyCard(message: 'No welds recorded yet.');
        }
        return Column(
          children: welds
              .map((w) => _WeldListTile(weld: w, db: db))
              .toList(),
        );
      },
    );
  }
}

class _WeldListTile extends StatelessWidget {
  const _WeldListTile({required this.weld, required this.db});
  final WeldRecord weld;
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy HH:mm');
    final isCompleted = weld.status == 'completed';
    final statusColor = isCompleted
        ? const Color(0xFF2E7D32)
        : weld.status == 'in_progress'
            ? AppColors.sertecRed
            : AppColors.neutralGray;

    return GestureDetector(
      onTap: () => context.push('/welds/${weld.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.local_fire_department, color: statusColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${weld.pipeMaterial} Ø${weld.pipeDiameter.toStringAsFixed(0)} mm',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    fmt.format(weld.startedAt.toLocal()),
                    style: const TextStyle(fontSize: 11, color: AppColors.neutralGray),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                weld.status.toUpperCase().replaceAll('_', ' '),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF333333),
        ),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.neutralGray, fontSize: 13),
        ),
      );
}
