# WeldTrace — Industrial Weld Traceability System

## Overview

Full-stack platform for recording and tracking thermoplastic pipe welding operations (PE, PP and similar materials). Supports welding standards DVS 2207, ISO 21307, and ASTM F2620. Designed for three-component deployment:

1. **Flutter Mobile App** — field tablets, offline-first
2. **Cloud Backend** — Supabase + Express API
3. **Fusion Cloud** — React/Next.js web dashboard (planned)

## Stack

- **Monorepo tool**: pnpm workspaces
- **Node.js version**: 24
- **Package manager**: pnpm
- **TypeScript version**: 5.9
- **API framework**: Express 5
- **Database**: PostgreSQL (Supabase) + Drizzle ORM (schema only)
- **Auth**: Supabase Auth (JWT bearer tokens)
- **Validation**: Zod v3.25+ (`zod/v4` compat path), field-level error responses
- **API codegen**: Orval (from OpenAPI spec)
- **Build**: esbuild (CJS bundle)

## API Architecture

The API follows a layered architecture:

```text
routes/          → thin routing only, no business logic
controllers/     → all business logic and Supabase queries
lib/validation.ts → all Zod schemas for request validation
lib/errors.ts    → ApiError, NotFoundError, sendError(), unwrap()
types/index.ts   → shared TypeScript interfaces for the entire API
middlewares/auth.ts → JWT verification, role guards
```

### Error Response Format

All errors return `{ error: string, code?: string, details?: unknown }`.

Validation errors (400) include `details: [{ path, message }]` for field-level messages.

HTTP codes in use: 200, 201, 204, 207 (multi-status sync), 400, 401, 403, 404, 409, 500.

## Environment Variables Required

| Secret | Description |
|--------|-------------|
| `SUPABASE_URL` | Supabase project URL (e.g. https://xxxx.supabase.co) |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key — full admin access |
| `SUPABASE_ANON_KEY` | Anon/public key — used by clients |

## Structure

```text
workspace/
├── artifacts/
│   └── api-server/               # Express 5 API server
│       └── src/
│           ├── lib/
│           │   └── supabase.ts   # Supabase admin + user clients
│           ├── middlewares/
│           │   └── auth.ts       # JWT auth middleware + role guards
│           └── routes/
│               ├── health.ts     # GET /api/healthz
│               ├── auth.ts       # /api/auth/* (login, register, refresh, me)
│               ├── projects.ts   # /api/projects/* CRUD + user/machine assignment
│               ├── machines.ts   # /api/machines/* + calibrations + maintenance
│               ├── welds.ts      # /api/welds/* + steps + errors
│               ├── sensor_logs.ts # /api/welds/:id/sensor-logs/batch
│               ├── standards.ts  # /api/welding-standards/* (read-only reference)
│               └── sync.ts       # /api/sync/upload + /api/sync/download
│
├── lib/
│   ├── db/src/schema/            # Drizzle ORM schema (mirrors Supabase)
│   │   ├── companies.ts
│   │   ├── users.ts
│   │   ├── projects.ts
│   │   ├── machines.ts
│   │   ├── welding_standards.ts
│   │   ├── welds.ts
│   │   └── sensors.ts
│   ├── api-spec/openapi.yaml     # OpenAPI 3.1 contract
│   ├── api-client-react/         # Generated React Query hooks
│   └── api-zod/                  # Generated Zod schemas
│
├── supabase/
│   └── migrations/
│       ├── 001_initial_schema.sql   # All 17 tables + enums + indexes + triggers
│       ├── 002_rls_policies.sql     # Row Level Security policies per role
│       ├── 003_seed_welding_standards.sql  # DVS 2207, ISO 21307, ASTM F2620 data
│       └── FULL_MIGRATION.sql       # Combined file for one-shot SQL Editor paste
│
└── scripts/src/
    └── migrate-supabase.ts          # Migration helper + instructions
```

## Database Tables (Supabase/PostgreSQL)

| Table | Purpose |
|-------|---------|
| `companies` | Top-level tenant |
| `users` | Linked to auth.users, role-based |
| `projects` | Construction projects |
| `project_users` | User-to-project assignments |
| `machines` | Welding machines (must be approved) |
| `project_machines` | Machine-to-project assignments |
| `welding_standards` | DVS 2207 / ISO 21307 / ASTM F2620 definitions |
| `welding_parameters` | Phase limits per standard, diameter, SDR |
| `welds` | Individual weld records (immutable after completion) |
| `weld_steps` | Per-phase records within a weld |
| `weld_photos` | Photos attached to welds |
| `weld_signatures` | Digital signatures (future certification) |
| `sensor_logs` | 1 Hz pressure + temperature readings (batch uploaded) |
| `weld_errors` | Auto-cancellation parameter violations |
| `machine_maintenance` | Maintenance history |
| `sensor_calibrations` | Sensor calibration records (RBC-certified) |
| `weld_certificates` | Future digital certification system |

## API Routes

### Auth
- `POST /api/auth/register` — Create user (admin)
- `POST /api/auth/login` — Login, returns JWT + refresh token
- `POST /api/auth/refresh` — Refresh access token
- `GET /api/auth/me` — Current user profile
- `POST /api/auth/logout` — Invalidate session

### Projects
- `GET /api/projects` — List projects (company-scoped via RLS)
- `GET /api/projects/:id` — Project detail with users + machines
- `POST /api/projects` — Create (manager/supervisor only)
- `PATCH /api/projects/:id` — Update
- `POST /api/projects/:id/users` — Assign user to project
- `DELETE /api/projects/:id/users/:userId` — Remove user
- `POST /api/projects/:id/machines` — Assign machine

### Machines
- `GET /api/machines` — List machines
- `GET /api/machines/:id` — Detail with maintenance + calibrations
- `POST /api/machines` — Register machine
- `PATCH /api/machines/:id` — Update
- `PATCH /api/machines/:id/approve` — Approve for use
- `POST /api/machines/:id/maintenance` — Log maintenance
- `POST /api/machines/:id/calibrations` — Log sensor calibration
- `GET /api/machines/:id/calibrations` — Calibration history

### Welds
- `GET /api/welds` — List welds (filterable by project, status)
- `GET /api/welds/:id` — Full weld detail
- `POST /api/welds` — Start new weld
- `PATCH /api/welds/:id/complete` — Mark completed (immutable after)
- `PATCH /api/welds/:id/cancel` — Cancel with reason
- `POST /api/welds/:id/steps` — Record phase step
- `POST /api/welds/:id/errors` — Record parameter violation

### Sensor Logs (batch upload)
- `POST /api/welds/:weldId/sensor-logs/batch` — Batch upload (max 500 records)
- `GET /api/welds/:weldId/sensor-logs` — Retrieve for graph rendering

### Standards
- `GET /api/welding-standards` — List standards (DVS, ISO, ASTM)
- `GET /api/welding-standards/:id/parameters` — Phase parameters

### Sync (offline-first mobile support)
- `POST /api/sync/upload` — Push pending local records to cloud
- `GET /api/sync/download` — Pull project/machine/standard updates

## User Roles & Permissions

| Role | Projects | Machines | Welds | Standards | Reports |
|------|----------|----------|-------|-----------|---------|
| Manager | Full CRUD | Full + Approve | Full | Read | Full |
| Supervisor | Full CRUD | Full + Approve | Full | Read | Full |
| Welder | Read (assigned) | Read | Create + own welds | Read | — |
| Auditor | Read | Read | Read (completed) | Read | Read |

## Row Level Security

All tables have RLS enabled. Key rules:
- Users can only access data within their `company_id`
- Welders can only access projects they are assigned to via `project_users`
- Completed welds are immutable (no UPDATE/DELETE permitted via RLS)
- `sensor_logs` have no UPDATE or DELETE policy — write-once by design
- `welding_standards` and `welding_parameters` are read-only for all authenticated users

## Applying Migrations to Supabase

**Option 1 — SQL Editor (recommended):**
1. Open Supabase dashboard → SQL Editor
2. Paste the contents of `supabase/migrations/FULL_MIGRATION.sql`
3. Run — this creates all tables, RLS policies, and seeds welding standards data

**Option 2 — Supabase CLI:**
```bash
supabase db push --project-ref <your-project-ref>
```

## Architecture Notes

### Sensor Log Batch Upload
Sensor data is captured at 1 Hz during welding operations. The mobile Sync Service batches 100–200 records per upload request to prevent network overload during active welding. The API accepts up to 500 records per batch call to `POST /api/welds/:weldId/sensor-logs/batch`.

### Offline-First Sync
The mobile app stores all data locally in SQLite (Drift) with `sync_status: pending | synced | conflict`. The Sync Service calls `/api/sync/upload` when connectivity is available, then `/api/sync/download` to pull updates. Completed welds are immutable and cannot be overwritten by downloads.

### Sensor Calibrations
The plug-and-play sensor kit (hydraulic T-connector pressure sensor + PT100 temperature sensor) must be periodically calibrated against an RBC-certified reference gauge. Calibration records include `offset_value` and `slope_value` applied to raw readings, and are stored per `sensor_serial` in `sensor_calibrations`.

### Future: Digital Certification
The `weld_certificates` and `weld_signatures` tables are reserved for the future digital certification module. They exist in the schema but are not yet fully implemented in the business logic.

## Flutter Mobile App — Weld Traceability Layer

Source: `flutter_app/lib/`

### Certificate System (`services/welding_trace/`)

| File | Purpose |
|------|---------|
| `weld_certificate.dart` | `WeldCertificate` model (schema v1 / `WeldTrace-CERT-1`), `CertSyncStatus` constants |
| `weld_registry.dart` | Append-only local JSON registry (`registry_export.json`) |
| `weld_ledger.dart` | Local JSON certification ledger |
| `weld_public_verifier.dart` | Public verification (registry, schema, signature, PDF hash) |
| `weld_report_generator.dart` | 17-section PDF engineering report (V1.4: `projectLocation`, `machineBrand`, calibration dates, `weldNumber`, 3 photo sections (alignment/weld/welder); 48pt left margin; 60×60 logo; cooling in minutes; header shows "Solda n°") |
| `weld_sync_service.dart` | `SyncResult` model + `WeldSyncService` (offline-first default) |
| `curve_compression.dart` | Gzip compression for pressure/time curves |

### Configuration (`config/`)

| File | Purpose |
|------|---------|
| `weldtrace_config.dart` | `WeldTraceConfig(syncEnabled, syncEndpoint)` — sync disabled by default |

### Workflow Engine (`workflow/weld_workflow_engine.dart`)

Steps executed on `completeWeld()`:
1. Export pressure/time curve
2. Generate SHA-256 joint signature
3. Serialise + gzip-compress curve
4. Determine trace quality (`OK` / `LOW_SAMPLE_COUNT`) — **moved before PDF so it is included in the report**
5. Generate PDF engineering report (non-fatal) — receives `traceQuality`, `operatorId`, `machineModel`, `machineSerialNumber`, `hydraulicCylinderAreaMm2`
6. Persist trace data to SQLite (Drift)
6b. Append to local certification ledger (non-fatal)
6c. Append to global certification registry (non-fatal)
6d. Attempt SaaS certificate upload via `WeldSyncService` (non-blocking, non-fatal)
7. Mark weld IMMUTABLE

New constructor fields (V1.0): `operatorId`, `machineModel`, `machineSerialNumber`, `hydraulicCylinderAreaMm2`.  
V1.3: `completeWeld()` and `cancel()` now accept optional `sertecLogoBytes` and `companyLogoBytes`; session screen loads these before calling the engine.

### Internationalisation (`core/l10n/`)

| File | Purpose |
|------|---------|
| `app_localizations.dart` | 317+ EN/PT-BR translation pairs; `AppLocalizations.of(context).t(key)` API; Flutter `LocalizationsDelegate` |
| `locale_notifier.dart` | Riverpod `StateNotifierProvider<LocaleNotifier, Locale>`; persists language choice to SharedPreferences (`app_locale` key) |

`MaterialApp.router` in `presentation/app.dart` watches `localeProvider` and passes it to the `locale:` field, so the whole app rebuilds on language change.  
Supported locales: `en` (English) and `pt` (Português do Brasil).

### Company Logo (`core/providers/company_logo_provider.dart`)

`CompanyLogoNotifier` — `StateNotifierProvider<CompanyLogoNotifier, AsyncValue<Uint8List?>>`.  
Stores PNG to `getApplicationDocumentsDirectory()/company_logo.png`, path in SharedPreferences `company_logo_path`.  
Managers can pick/change/remove via Settings → Company Logo tile.  
Logo bytes are loaded in `_loadLogos()` in the session screen and passed to `WeldReportGenerator.generate()`.

### SaaS Sync Layer (Optional)

`WeldSyncService` is offline-first: every method returns `SyncResult.offline()` by default.  
No external dependencies are required.  The service is injected into `WeldWorkflowEngine`  
via an optional constructor parameter (`syncService`).

`SyncResult` factory constructors:
- `SyncResult.offline()` — sync disabled / no network
- `SyncResult.success([message])` — uploaded successfully
- `SyncResult.failure(message)` — network/server error

`CertSyncStatus` string constants: `pending`, `synced`, `offline`

### Test Coverage (`test/unit/`)

| File | Groups | Tests |
|------|--------|-------|
| `weld_trace_test.dart` | — | ~73 |
| `weld_public_verifier_test.dart` | 4 | 29 |
| `weld_registry_test.dart` | 3 | 23 |
| `weld_certificate_test.dart` | 5 | 41 |
| `weld_ledger_test.dart` | 3 | 15 |
| `curve_compression_test.dart` | 2 | 11 |
| `weld_sync_test.dart` | 3 | 27 |
