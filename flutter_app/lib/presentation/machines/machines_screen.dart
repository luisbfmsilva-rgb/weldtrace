import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../data/local/tables/machines_table.dart';

class MachinesScreen extends ConsumerWidget {
  const MachinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Machines')),
      body: StreamBuilder<List<MachineRecord>>(
        stream: db.machinesDao.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final machines = snapshot.data ?? [];
          if (machines.isEmpty) {
            return const Center(
              child: Text('No machines. Sync to load your company\'s machines.'),
            );
          }
          return ListView.builder(
            itemCount: machines.length,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, i) => _MachineCard(machine: machines[i]),
          );
        },
      ),
    );
  }
}

class _MachineCard extends StatelessWidget {
  const _MachineCard({required this.machine});
  final MachineRecord machine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: machine.isApproved
                    ? const Color(0xFF2E7D32).withOpacity(0.1)
                    : theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.precision_manufacturing,
                color: machine.isApproved
                    ? const Color(0xFF2E7D32)
                    : theme.colorScheme.error,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${machine.manufacturer} ${machine.model}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'S/N: ${machine.serialNumber}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (machine.nextCalibrationDate != null)
                    Text(
                      'Cal. due: ${machine.nextCalibrationDate}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                _StatusBadge(
                  label: machine.isApproved ? 'APPROVED' : 'PENDING',
                  color: machine.isApproved
                      ? const Color(0xFF2E7D32)
                      : Colors.orange,
                ),
                const SizedBox(height: 4),
                _StatusBadge(
                  label: machine.type.toUpperCase().replaceAll('_', ' '),
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: color),
        ),
      );
}
