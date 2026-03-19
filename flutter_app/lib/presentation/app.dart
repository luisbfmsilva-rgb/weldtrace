import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../di/providers.dart';
import 'auth/login_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'machines/machines_screen.dart';
import 'machines/machine_form.dart';
import 'projects/projects_screen.dart';
import 'projects/project_form.dart';
import 'projects/project_detail_screen.dart';
import 'qr/qr_scan_screen.dart';
import 'reports/reports_screen.dart';
import 'sensors/sensor_screen.dart';
import 'settings/settings_screen.dart';
import 'shell/main_shell.dart';
import 'splash/splash_screen.dart';
import 'welds/welds_screen.dart';
import 'welds/weld_detail_screen.dart';
import 'welding/weld_setup_screen.dart';
import 'welding/weld_type_selector_screen.dart';
import 'welding/welding_session_screen.dart';

class FusionCertifyApp extends ConsumerWidget {
  const FusionCertifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    final router = GoRouter(
      initialLocation: '/splash',
      redirect: (context, state) {
        final loc = state.matchedLocation;
        if (loc == '/splash') return null;

        final isAuth = authState.isAuthenticated;
        final onLogin = loc == '/login';

        if (!isAuth && !onLogin) return '/login';
        if (isAuth && onLogin) return '/dashboard';
        return null;
      },
      routes: [
        // ── Public routes ──────────────────────────────────────────────
        GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),

        // ── Main shell with BottomNav ──────────────────────────────────
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => MainShell(navigationShell: shell),
          branches: [
            // 0 – Dashboard
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/dashboard',
                builder: (_, __) => const DashboardScreen(),
              ),
            ]),
            // 1 – Projects
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/projects',
                builder: (_, __) => const ProjectsScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (_, __) => const ProjectFormScreen(),
                  ),
                  GoRoute(
                    path: ':projectId',
                    builder: (_, state) => ProjectDetailScreen(
                      projectId: state.pathParameters['projectId']!,
                    ),
                  ),
                ],
              ),
            ]),
            // 2 – Welds
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/welds',
                builder: (_, __) => const WeldsScreen(),
                routes: [
                  GoRoute(
                    path: ':weldId',
                    builder: (_, state) => WeldDetailScreen(
                      weldId: state.pathParameters['weldId']!,
                    ),
                  ),
                ],
              ),
            ]),
            // 3 – Machines
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/machines',
                builder: (_, __) => const MachinesScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (_, __) => const MachineFormScreen(),
                  ),
                ],
              ),
            ]),
            // 4 – Reports
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/reports',
                builder: (_, __) => const ReportsScreen(),
              ),
            ]),
            // 5 – Settings
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
              ),
            ]),
          ],
        ),

        // ── Weld flow (full-screen, outside shell) ─────────────────────
        GoRoute(
          path: '/weld/setup',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>?;
            final projectId = extra?['preselectedProjectId'] as String?;
            return WeldTypeSelectorScreen(preselectedProjectId: projectId);
          },
          routes: [
            GoRoute(
              path: 'butt',
              builder: (_, state) {
                final extra = state.extra as Map<String, dynamic>?;
                final projectId = extra?['preselectedProjectId'] as String?;
                return WeldSetupScreen(preselectedProjectId: projectId);
              },
            ),
          ],
        ),
        GoRoute(
          path: '/weld/session',
          builder: (context, state) {
            final args = state.extra as WeldSessionArgs;
            return WeldingSessionScreen(args: args);
          },
        ),

        // ── QR verification (full-screen) ─────────────────────────────
        GoRoute(
          path: '/qr/verify',
          builder: (_, __) => const QRScanScreen(),
        ),

        // ── Sensor screen ─────────────────────────────────────────────
        GoRoute(
          path: '/sensors',
          builder: (_, __) => const SensorScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Sertec FusionCertify',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      routerConfig: router,
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.sertecRed,
        primary: AppColors.sertecRed,
        secondary: AppColors.darkRed,
        error: AppColors.error,
        surface: Colors.white,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.lightGray,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.sertecRed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.sertecRed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.sertecRed,
          side: const BorderSide(color: AppColors.sertecRed, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          minimumSize: const Size(double.infinity, 52),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.sertecRed),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.sertecRed, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shadowColor: Colors.black12,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 65,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.sertecRed);
          }
          return const TextStyle(fontSize: 11, color: AppColors.neutralGray);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.sertecRed);
          }
          return const IconThemeData(color: AppColors.neutralGray);
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.sertecRed : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFEEEEEE), thickness: 1, space: 1),
      extensions: [
        WeldTraceColors(
          warning: AppColors.warning,
          success: AppColors.success,
          sensorPressure: AppColors.chartPressure,
          sensorTemperature: AppColors.chartTemperature,
        ),
      ],
    );
  }
}

/// Custom theme extension for FusionCertify semantic colors.
class WeldTraceColors extends ThemeExtension<WeldTraceColors> {
  const WeldTraceColors({
    required this.warning,
    required this.success,
    required this.sensorPressure,
    required this.sensorTemperature,
  });

  final Color warning;
  final Color success;
  final Color sensorPressure;
  final Color sensorTemperature;

  @override
  WeldTraceColors copyWith({
    Color? warning,
    Color? success,
    Color? sensorPressure,
    Color? sensorTemperature,
  }) =>
      WeldTraceColors(
        warning: warning ?? this.warning,
        success: success ?? this.success,
        sensorPressure: sensorPressure ?? this.sensorPressure,
        sensorTemperature: sensorTemperature ?? this.sensorTemperature,
      );

  @override
  WeldTraceColors lerp(WeldTraceColors? other, double t) {
    if (other == null) return this;
    return WeldTraceColors(
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      sensorPressure: Color.lerp(sensorPressure, other.sensorPressure, t)!,
      sensorTemperature: Color.lerp(sensorTemperature, other.sensorTemperature, t)!,
    );
  }
}
