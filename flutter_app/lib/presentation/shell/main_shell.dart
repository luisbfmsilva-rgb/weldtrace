import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    _TabItem(icon: Icons.dashboard_outlined, label: 'Dashboard', path: '/dashboard'),
    _TabItem(icon: Icons.folder_outlined, label: 'Projects', path: '/projects'),
    _TabItem(icon: Icons.local_fire_department_outlined, label: 'Welds', path: '/welds'),
    _TabItem(icon: Icons.precision_manufacturing_outlined, label: 'Machines', path: '/machines'),
    _TabItem(icon: Icons.description_outlined, label: 'Reports', path: '/reports'),
    _TabItem(icon: Icons.settings_outlined, label: 'Settings', path: '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
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
        destinations: _tabs.map((t) => NavigationDestination(
          icon: Icon(t.icon, size: 22),
          label: t.label,
        )).toList(),
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
