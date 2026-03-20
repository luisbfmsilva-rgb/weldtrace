import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/l10n/locale_notifier.dart';
import '../../core/providers/company_logo_provider.dart';
import '../../di/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n      = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final user      = authState.user;
    final theme     = Theme.of(context);
    final isManager = user?.role == 'manager';
    final locale    = ref.watch(localeProvider);
    final logoState = ref.watch(companyLogoProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('Settings'))),
      body: ListView(
        children: [
          // ── User profile ─────────────────────────────────────────────
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
                      Text(user.email, style: theme.textTheme.bodySmall),
                      Text(
                        l10n.t(user.role),
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

          // ── Sensor ────────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.sensors),
            title: Text(l10n.t('Sensor Setup')),
            subtitle: Text(l10n.t('Connect & calibrate BLE sensor')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/sensors'),
          ),

          // ── Sync ──────────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.sync),
            title: Text(l10n.t('Sync Now')),
            subtitle: Text(
                l10n.t('Upload pending records and pull updates')),
            onTap: () async {
              final service = ref.read(syncServiceProvider);
              service.start();
              final result = await service.syncNow();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.hasErrors
                        ? l10n.t('Sync completed with errors')
                        : l10n.t('Sync complete')),
                    backgroundColor: result.hasErrors
                        ? Colors.orange
                        : const Color(0xFF2E7D32),
                  ),
                );
              }
            },
          ),

          // ── Standards ─────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: Text(l10n.t('Standards')),
            subtitle: const Text('DVS 2207 · ISO 21307 · ASTM F2620'),
            onTap: () {},
          ),

          // ── Language ──────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.t('Language')),
            subtitle: Text(locale.languageCode == 'pt'
                ? 'Português (Brasil)'
                : 'English'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguageDialog(context, ref, locale, l10n),
          ),

          // ── Manager-only section ──────────────────────────────────────
          if (isManager) ...[
            const Divider(),

            // User Management
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: Text(l10n.t('User Management')),
              subtitle: Text(l10n.t('Add, edit and remove users')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/users'),
            ),

            // Company Logo
            _CompanyLogoTile(
              l10n:       l10n,
              logoState:  logoState,
              onPick:     () => ref.read(companyLogoProvider.notifier).pickLogo(),
              onRemove: () async {
                await ref.read(companyLogoProvider.notifier).removeLogo();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.t('Logo removed'))),
                  );
                }
              },
            ),
          ],

          const Divider(),

          // ── Sign out ──────────────────────────────────────────────────
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              l10n.t('Sign Out'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(
    BuildContext context,
    WidgetRef ref,
    Locale current,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('Language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LanguageOption(
              label: 'English',
              flag: '🇬🇧',
              selected: current.languageCode == 'en',
              onTap: () async {
                await ref
                    .read(localeProvider.notifier)
                    .setLocale(const Locale('en'));
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
            _LanguageOption(
              label: 'Português (Brasil)',
              flag: '🇧🇷',
              selected: current.languageCode == 'pt',
              onTap: () async {
                await ref
                    .read(localeProvider.notifier)
                    .setLocale(const Locale('pt'));
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.t('Close')),
          ),
        ],
      ),
    );
  }
}

// ── Company logo tile ─────────────────────────────────────────────────────────

class _CompanyLogoTile extends StatelessWidget {
  const _CompanyLogoTile({
    required this.l10n,
    required this.logoState,
    required this.onPick,
    required this.onRemove,
  });

  final AppLocalizations          l10n;
  final AsyncValue<Uint8List?>    logoState;
  final VoidCallback              onPick;
  final Future<void> Function()   onRemove;

  @override
  Widget build(BuildContext context) {
    final logoBytes = logoState.valueOrNull;

    return ListTile(
      leading: logoBytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                logoBytes!,
                width: 40,
                height: 40,
                fit: BoxFit.contain,
              ),
            )
          : const Icon(Icons.business),
      title: Text(l10n.t('Company Logo')),
      subtitle: Text(l10n.t('Upload your company logo for PDF reports')),
      trailing: logoBytes != null
          ? PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'change') onPick();
                if (v == 'remove') await onRemove();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'change',
                  child: Text(l10n.t('Change Logo')),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(l10n.t('Remove Logo')),
                ),
              ],
            )
          : const Icon(Icons.chevron_right),
      onTap: logoBytes == null ? onPick : null,
    );
  }
}

// ── Language option row ────────────────────────────────────────────────────────

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.flag,
    required this.selected,
    required this.onTap,
  });

  final String    label;
  final String    flag;
  final bool      selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Text(flag, style: const TextStyle(fontSize: 22)),
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
