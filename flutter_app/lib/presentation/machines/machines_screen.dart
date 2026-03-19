import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';
import 'machine_form.dart';

class MachinesScreen extends ConsumerWidget {
  const MachinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(title: const Text('Machines')),
      body: StreamBuilder<List<MachineRecord>>(
        stream: db.machinesDao.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.sertecRed));
          }
          final machines = snapshot.data ?? [];
          if (machines.isEmpty) {
            return _EmptyState(onAdd: () => _openForm(context));
          }
          return ListView.builder(
            itemCount: machines.length,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemBuilder: (context, i) => _MachineCard(
              machine: machines[i],
              onEdit: () => _openForm(context, existing: machines[i]),
              onDelete: () => _delete(context, ref, machines[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.sertecRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Machine'),
        onPressed: () => _openForm(context),
      ),
    );
  }

  void _openForm(BuildContext context, {MachineRecord? existing}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MachineFormScreen(existing: existing),
    ));
  }

  void _delete(BuildContext context, WidgetRef ref, MachineRecord machine) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Machine?'),
        content: Text('Delete "${machine.manufacturer} ${machine.model}" (S/N: ${machine.serialNumber})?'),
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
      await ref.read(databaseProvider).machinesDao.deleteById(machine.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Machine deleted')),
        );
      }
    }
  }
}

class _MachineCard extends StatelessWidget {
  const _MachineCard({required this.machine, required this.onEdit, required this.onDelete});
  final MachineRecord machine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approved = machine.isApproved;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.055), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: approved ? const Color(0xFF2E7D32).withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.precision_manufacturing,
                  color: approved ? const Color(0xFF2E7D32) : Colors.orange, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${machine.manufacturer} ${machine.model}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('S/N: ${machine.serialNumber}',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.neutralGray)),
                  const SizedBox(height: 3),
                  Row(children: [
                    _Badge(label: machine.type.toUpperCase().replaceAll('_', ' '),
                        color: AppColors.sertecRed),
                    const SizedBox(width: 6),
                    _Badge(label: approved ? 'APPROVED' : 'PENDING',
                        color: approved ? const Color(0xFF2E7D32) : Colors.orange),
                  ]),
                  if (machine.hydraulicCylinderAreaMm2 != null) ...[
                    const SizedBox(height: 3),
                    Text('Cylinder: ${machine.hydraulicCylinderAreaMm2!.toStringAsFixed(2)} mm²',
                        style: const TextStyle(fontSize: 11, color: AppColors.neutralGray)),
                  ],
                  if (machine.nextCalibrationDate != null) ...[
                    const SizedBox(height: 2),
                    Text('Cal. due: ${machine.nextCalibrationDate}',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.error)),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: AppColors.neutralGray,
                  onPressed: onEdit,
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.redAccent,
                  onPressed: onDelete,
                  tooltip: 'Delete',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.sertecRed.withValues(alpha: 0.07), shape: BoxShape.circle),
                child: const Icon(Icons.precision_manufacturing_outlined, size: 36, color: AppColors.sertecRed),
              ),
              const SizedBox(height: 20),
              const Text('No machines registered.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF333333))),
              const SizedBox(height: 8),
              const Text('Register your welding machines before starting a weld.',
                  style: TextStyle(fontSize: 13, color: AppColors.neutralGray), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAdd,
                style: FilledButton.styleFrom(backgroundColor: AppColors.sertecRed),
                icon: const Icon(Icons.add),
                label: const Text('Add Machine'),
              ),
            ],
          ),
        ),
      );
}
