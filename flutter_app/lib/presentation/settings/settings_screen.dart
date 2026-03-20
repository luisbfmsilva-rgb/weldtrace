import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../di/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _showLanguageDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Language'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(Icons.check, color: Colors.green),
              title: Text('English'),
              dense: true,
            ),
            ListTile(
              enabled: false,
              leading: Icon(Icons.lock_clock_outlined),
              title: Text('Português (coming soon)'),
              dense: true,
            ),
            ListTile(
              enabled: false,
              leading: Icon(Icons.lock_clock_outlined),
              title: Text('Español (coming soon)'),
              dense: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final theme = Theme.of(context);
    final isManager = user?.role == 'manager';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // User profile section
          if (user != null) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      '${user.firstName[0]}${user.lastName[0]}',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(user.email,
                          style: theme.textTheme.bodySmall),
                      Text(
                        user.role.toUpperCase(),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
          ],

          ListTile(
            leading: const Icon(Icons.sensors),
            title: const Text('Sensor Setup'),
            subtitle: const Text('Connect & calibrate BLE sensor'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/sensors'),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync Now'),
            subtitle: const Text('Upload pending records and pull updates'),
            onTap: () async {
              final service = ref.read(syncServiceProvider);
              service.start();
              final result = await service.syncNow();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.hasErrors
                        ? 'Sync completed with errors'
                        : 'Sync complete'),
                    backgroundColor:
                        result.hasErrors ? Colors.orange : const Color(0xFF2E7D32),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Standards'),
            subtitle: const Text('DVS 2207 · ISO 21307 · ASTM F2620'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language'),
            subtitle: const Text('English'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguageDialog(context),
          ),

          if (isManager) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('User Management'),
              subtitle: const Text('Add, edit and remove users'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/users'),
            ),
          ],

          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Sign Out',
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
