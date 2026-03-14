/// Central constants used across the application.
/// Replace placeholder values with your actual Supabase project credentials.
class AppConstants {
  AppConstants._();

  // ── Supabase ───────────────────────────────────────────────────────────────
  // These values are injected at build time via --dart-define:
  //   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  //               --dart-define=SUPABASE_ANON_KEY=eyJ...
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key',
  );

  // ── API base URL (Express backend) ────────────────────────────────────────
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://your-api.replit.app/api',
  );

  // ── Database ───────────────────────────────────────────────────────────────
  static const dbName = 'weldtrace.db';

  // ── Sensor ────────────────────────────────────────────────────────────────
  // BLE scanning timeout
  static const bleScanTimeoutSeconds = 15;
  // Sensor log sampling interval — 1 Hz
  static const sensorSamplingIntervalMs = 1000;
  // Max records per sensor log batch upload
  static const sensorBatchMaxRecords = 200;

  // ── Sync ──────────────────────────────────────────────────────────────────
  static const syncRetryMaxAttempts = 3;
  static const syncRetryBaseDelayMs = 2000;

  // ── Weld ──────────────────────────────────────────────────────────────────
  static const weldMaxAmbientTemperatureCelsius = 50.0;
  static const weldMinAmbientTemperatureCelsius = -15.0;
}
