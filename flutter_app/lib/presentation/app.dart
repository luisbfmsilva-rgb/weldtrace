import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../di/providers.dart';
import 'auth/login_screen.dart';
import 'projects/projects_screen.dart';
import 'welding/weld_setup_screen.dart';
import 'welding/welding_session_screen.dart';
import 'machines/machines_screen.dart';
import 'sensors/sensor_screen.dart';
import 'settings/settings_screen.dart';

class WeldTraceApp extends ConsumerWidget {
  const WeldTraceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    final router = GoRouter(
      initialLocation: authState.isAuthenticated ? '/projects' : '/login',
      redirect: (context, state) {
        final isAuth = authState.isAuthenticated;
        final isOnLogin = state.matchedLocation == '/login';

        if (!isAuth && !isOnLogin) return '/login';
        if (isAuth && isOnLogin) return '/projects';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/projects',
          builder: (context, state) => const ProjectsScreen(),
        ),

        // ── Weld flow ─────────────────────────────────────────────────────
        // Step 1: Setup — select all parameters, create local record
        GoRoute(
          path: '/projects/:projectId/weld/setup',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            return WeldSetupScreen(preselectedProjectId: projectId);
          },
        ),
        // Step 2: Session — live sensor monitoring and phase workflow
        GoRoute(
          path: '/weld/session',
          builder: (context, state) {
            final args = state.extra as WeldSessionArgs;
            return WeldingSessionScreen(args: args);
          },
        ),

        GoRoute(
          path: '/machines',
          builder: (context, state) => const MachinesScreen(),
        ),
        GoRoute(
          path: '/sensors',
          builder: (context, state) => const SensorScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'WeldTrace',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      routerConfig: router,
    );
  }

  ThemeData _buildTheme() {
    const primaryColor = Color(0xFF0052CC);
    const errorColor = Color(0xFFD32F2F);
    const warningColor = Color(0xFFF57F17);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        error: errorColor,
        brightness: Brightness.light,
      ),
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      extensions: [
        WeldTraceColors(
          warning: warningColor,
          success: const Color(0xFF2E7D32),
          sensorPressure: const Color(0xFF0052CC),
          sensorTemperature: const Color(0xFFD32F2F),
        ),
      ],
    );
  }
}

/// Custom theme extension for WeldTrace-specific semantic colors.
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
      sensorTemperature:
          Color.lerp(sensorTemperature, other.sensorTemperature, t)!,
    );
  }
}
