import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_colors.dart';
import '../di/providers.dart';
import 'auth/login_screen.dart';
import 'projects/projects_screen.dart';
import 'splash/splash_screen.dart';
import 'welding/weld_setup_screen.dart';
import 'welding/welding_session_screen.dart';
import 'machines/machines_screen.dart';
import 'sensors/sensor_screen.dart';
import 'settings/settings_screen.dart';

class FusionCertifyApp extends ConsumerWidget {
  const FusionCertifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    final router = GoRouter(
      initialLocation: '/splash',
      redirect: (context, state) {
        final onSplash = state.matchedLocation == '/splash';
        if (onSplash) return null;

        final isAuth = authState.isAuthenticated;
        final onLogin = state.matchedLocation == '/login';
        if (!isAuth && !onLogin) return '/login';
        if (isAuth && onLogin) return '/projects';
        return null;
      },
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/projects',
          builder: (context, state) => const ProjectsScreen(),
        ),

        // ── Weld flow ──────────────────────────────────────────────────────────
        GoRoute(
          path: '/projects/:projectId/weld/setup',
          builder: (context, state) {
            final projectId = state.pathParameters['projectId']!;
            return WeldSetupScreen(preselectedProjectId: projectId);
          },
        ),
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
        style: TextButton.styleFrom(
          foregroundColor: AppColors.sertecRed,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.sertecRed, width: 1.8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.sertecRed : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFEEEEEE),
        thickness: 1,
        space: 1,
      ),
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
