import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tabs = [
      _TabItem(icon: Icons.dashboard_outlined,               label: l10n.t('Dashboard'),  path: '/dashboard'),
      _TabItem(icon: Icons.folder_outlined,                  label: l10n.t('Projects'),   path: '/projects'),
      _TabItem(icon: Icons.local_fire_department_outlined,   label: l10n.t('Welds'),      path: '/welds'),
      _TabItem(icon: Icons.precision_manufacturing_outlined, label: l10n.t('Machines'),   path: '/machines'),
      _TabItem(icon: Icons.description_outlined,             label: l10n.t('Reports'),    path: '/reports'),
      _TabItem(icon: Icons.settings_outlined,                label: l10n.t('Settings'),   path: '/settings'),
    ];

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        indicatorColor: AppColors.sertecRed.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.icon, size: 22),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({required this.icon, required this.label, required this.path});
  final IconData icon;
  final String label;
  final String path;
}
