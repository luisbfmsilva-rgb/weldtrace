import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';

class WeldsScreen extends ConsumerStatefulWidget {
  const WeldsScreen({super.key});

  @override
  ConsumerState<WeldsScreen> createState() => _WeldsScreenState();
}

class _WeldsScreenState extends ConsumerState<WeldsScreen> {
  String _filter = 'all'; // all, completed, in_progress, failed

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        title: const Text('Welds'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Weld',
            onPressed: () => context.push('/weld/setup'),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter chips ──────────────────────────────────────────────
          _FilterBar(
            selected: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),

          // ── List ──────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<WeldRecord>>(
              stream: db.weldsDao.watchAll(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.sertecRed));
                }
                var welds = snapshot.data ?? [];
                if (_filter != 'all') {
                  welds = welds.where((w) => w.status == _filter).toList();
                }
                if (welds.isEmpty) {
                  return _EmptyState(
                    filter: _filter,
                    onNew: () => context.push('/weld/setup'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: welds.length,
                  itemBuilder: (context, i) => _WeldCard(
                    weld: welds[i],
                    db: db,
                    onTap: () => context.push('/welds/${welds[i].id}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.sertecRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.local_fire_department),
        label: const Text('New Weld'),
        onPressed: () => context.push('/weld/setup'),
      ),
    );
  }
}

// ── Filter bar ─────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('all', 'All'),
      ('completed', 'Completed'),
      ('in_progress', 'In Progress'),
      ('failed', 'Failed'),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final (value, label) = f;
            final isSelected = selected == value;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (_) => onChanged(value),
                selectedColor: AppColors.sertecRed.withValues(alpha: 0.15),
                checkmarkColor: AppColors.sertecRed,
                labelStyle: TextStyle(
                  color: isSelected ? AppColors.sertecRed : Colors.grey.shade600,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Weld card ──────────────────────────────────────────────────────────────────

class _WeldCard extends StatelessWidget {
  const _WeldCard({required this.weld, required this.db, required this.onTap});
  final WeldRecord weld;
  final AppDatabase db;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy • HH:mm');
    final statusColor = _statusColor(weld.status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.local_fire_department, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${weld.pipeMaterial} — Ø${weld.pipeDiameter.toStringAsFixed(0)} mm',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        if (weld.pipeSdr != null)
                          Text('SDR ${weld.pipeSdr}',
                              style: const TextStyle(fontSize: 12, color: AppColors.neutralGray)),
                      ],
                    ),
                  ),
                  _StatusChip(status: weld.status, color: statusColor),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _InfoPill(icon: Icons.calendar_today_outlined, text: fmt.format(weld.startedAt.toLocal())),
                  const Spacer(),
                  if (weld.traceSignature != null)
                    const _InfoPill(icon: Icons.verified_outlined, text: 'Certified'),
                  if (weld.jointId != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: const Icon(Icons.qr_code, size: 16, color: AppColors.neutralGray),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'completed' => const Color(0xFF2E7D32),
        'in_progress' => AppColors.sertecRed,
        'failed' => Colors.orange,
        _ => AppColors.neutralGray,
      };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.color});
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status.toUpperCase().replaceAll('_', ' '),
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
        ),
      );
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.neutralGray),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11, color: AppColors.neutralGray)),
        ],
      );
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.onNew});
  final String filter;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.sertecRed.withValues(alpha: 0.07), shape: BoxShape.circle),
              child: const Icon(Icons.local_fire_department_outlined, size: 36, color: AppColors.sertecRed),
            ),
            const SizedBox(height: 16),
            Text(
              filter == 'all' ? 'No welds yet.' : 'No $filter welds.',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('Start by selecting a project and machine.',
                style: TextStyle(fontSize: 13, color: AppColors.neutralGray)),
            const SizedBox(height: 20),
            if (filter == 'all')
              FilledButton.icon(
                onPressed: onNew,
                style: FilledButton.styleFrom(backgroundColor: AppColors.sertecRed),
                icon: const Icon(Icons.add),
                label: const Text('Start Weld'),
              ),
          ],
        ),
      );
}
