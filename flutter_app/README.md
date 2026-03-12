# WeldTrace Flutter App

Offline-first field tablet application for thermoplastic pipe weld traceability.

## Supported Standards
- DVS 2207 (butt fusion)
- ISO 21307 (butt fusion)
- ASTM F2620 (butt fusion)

## Build Instructions

### Prerequisites
- Flutter SDK ≥ 3.19.0 (Dart ≥ 3.3.0)
- Android SDK (API 26+) for tablet deployment

### Install dependencies
```bash
flutter pub get
```

### Generate Drift code (required before building)
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Run (development)
```bash
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=your-anon-key \
            --dart-define=API_BASE_URL=https://your-api.replit.app/api
```

### Build release APK
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=API_BASE_URL=https://your-api.replit.app/api
```

## Architecture

```
lib/
├── core/
│   ├── constants/         AppConstants (env vars, sensor config, sync config)
│   ├── errors/            AppException hierarchy (typed, sealed)
│   ├── network/           ApiClient (HTTP, JWT injection, error mapping)
│   └── utils/             Result<T> (Success/Failure without exceptions in UI)
│
├── data/
│   ├── local/
│   │   ├── database/      AppDatabase (Drift root, schema version, migrations)
│   │   ├── tables/        Drift table definitions (6 tables, all with sync_status)
│   │   └── dao/           Data access objects per table (CRUD + sync helpers)
│   ├── remote/            Remote data sources (HTTP via ApiClient)
│   ├── repositories/      Combine local + remote, drive sync_status lifecycle
│   └── models/            Plain Dart model classes (auth, sync payloads)
│
├── domain/                (Future: use-case classes when business rules grow)
│
├── services/
│   ├── sensor/            SensorService (BLE scan/connect, 1 Hz capture, calibration)
│   └── sync/              SyncService (connectivity-aware, retry, upload+download)
│
├── workflow/
│   ├── welding_phase.dart     Phase enum + PhaseParameters (duration, pressure, temperature)
│   └── weld_workflow_engine.dart  Drives phase sequence, detects violations, auto-cancel
│
├── presentation/
│   ├── auth/              LoginScreen
│   ├── projects/          ProjectsScreen (Drift stream, sync trigger)
│   ├── welding/           WeldingSessionScreen (live readings, violations, cancel)
│   ├── machines/          MachinesScreen (approval status, calibration dates)
│   ├── sensors/           SensorScreen (BLE connect/disconnect, live values)
│   └── settings/          SettingsScreen (user profile, sync, logout)
│
└── di/
    └── providers.dart     Riverpod provider graph (DB, API, repos, services, auth state)
```

## Local Database Tables

| Table | Sync Status | Notes |
|-------|-------------|-------|
| projects | synced on download | Seeded from /auth/me assigned_projects |
| machines | synced on download | Must be approved before use |
| welds | pending → synced | Created offline, uploaded on sync |
| weld_steps | pending → synced | One row per phase |
| sensor_logs | pending → synced | Write-once, 1 Hz, max 200 per upload batch |
| sensor_calibrations | synced on download | offset + slope for linear correction |

## Key Design Decisions

- **Offline-first**: All weld data is written to SQLite first. Internet is optional.
- **Immutable completed welds**: Once status = 'completed', no further writes are permitted locally, matching the cloud RLS policy.
- **1 Hz sensor sampling**: SensorService fires a timer every 1000ms and writes one row to sensor_logs.
- **Calibration**: Linear correction (corrected = raw × slope + offset) applied before storage, matching values in sensor_calibrations table.
- **Auto-cancel on violation**: WeldWorkflowEngine emits ParameterViolation events; the UI can automatically cancel a weld when thresholds are crossed.
- **Retry with backoff**: SyncService retries failed uploads up to 3 times with exponential backoff.
