// ─────────────────────────────────────────────────────────────────────────────
// WeldTrace — Shared TypeScript types for the API layer
// ─────────────────────────────────────────────────────────────────────────────

// ── User / Auth ──────────────────────────────────────────────────────────────

export type UserRole = "manager" | "supervisor" | "welder" | "auditor";

export interface UserProfile {
  id: string;
  email: string;
  role: UserRole;
  companyId: string;
  firstName: string;
  lastName: string;
  welderCertificationNumber: string | null;
  certificationExpiry: string | null;
  isActive: boolean;
}

export interface AssignedProject {
  id: string;
  name: string;
  status: string;
  location: string | null;
  roleInProject: string;
}

export interface AuthUser {
  id: string;
  email: string;
  role: UserRole;
  companyId: string;
  firstName: string;
  lastName: string;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export interface LoginResponse extends AuthTokens {
  user: AuthUser & { assignedProjects: AssignedProject[] };
}

export interface MeResponse {
  user: UserProfile & { assignedProjects: AssignedProject[] };
}

// ── Weld ─────────────────────────────────────────────────────────────────────

export type WeldType = "electrofusion" | "butt_fusion";
export type WeldStatus = "in_progress" | "completed" | "cancelled" | "failed";
export type StandardCode = "DVS_2207" | "ISO_21307" | "ASTM_F2620";

export interface StartWeldPayload {
  projectId: string;
  machineId: string;
  weldType: WeldType;
  pipeMaterial: string;
  pipeDiameter: number;
  pipeSdr?: string;
  pipeWallThickness?: number;
  ambientTemperature?: number;
  gpsLat?: number;
  gpsLng?: number;
  standardUsed?: StandardCode;
  standardId?: string;
  notes?: string;
}

export interface RecordStepPayload {
  phaseName: string;
  phaseOrder: number;
  startedAt?: string;
  completedAt?: string;
  nominalValue?: number;
  actualValue?: number;
  unit?: string;
  validationPassed?: boolean;
  notes?: string;
}

export interface RecordErrorPayload {
  errorType: string;
  errorMessage: string;
  phaseName?: string;
  parameterName?: string;
  actualValue?: number;
  allowedMin?: number;
  allowedMax?: number;
}

export interface CancelWeldPayload {
  cancelReason: string;
}

// ── Sensor Logs ──────────────────────────────────────────────────────────────

export interface SensorLogRecord {
  recordedAt: string;
  pressureBar?: number | null;
  temperatureCelsius?: number | null;
  phaseName?: string | null;
  weldStepId?: string | null;
}

export interface SensorLogBatchPayload {
  weldId: string;
  records: SensorLogRecord[];
}

export interface SensorLogBatchResult {
  inserted: number;
  weldId: string;
  batchSize: number;
}

// ── Sync ─────────────────────────────────────────────────────────────────────

export interface SyncUploadPayload {
  welds?: SyncWeld[];
  weldSteps?: SyncWeldStep[];
  weldErrors?: SyncWeldError[];
  weldPhotos?: SyncWeldPhoto[];
  sensorLogBatches?: SyncSensorLogBatch[];
}

export interface SyncWeld {
  id: string;
  projectId: string;
  machineId: string;
  weldType: WeldType;
  status: WeldStatus;
  pipeMaterial: string;
  pipeDiameter: number;
  pipeSdr?: string | null;
  pipeWallThickness?: number | null;
  ambientTemperature?: number | null;
  gpsLat?: number | null;
  gpsLng?: number | null;
  standardUsed?: StandardCode | null;
  standardId?: string | null;
  isCancelled: boolean;
  cancelReason?: string | null;
  cancelTimestamp?: string | null;
  notes?: string | null;
  startedAt: string;
  completedAt?: string | null;
}

export interface SyncWeldStep {
  id: string;
  weldId: string;
  phaseName: string;
  phaseOrder: number;
  startedAt?: string | null;
  completedAt?: string | null;
  nominalValue?: number | null;
  actualValue?: number | null;
  unit?: string | null;
  validationPassed?: boolean | null;
  notes?: string | null;
}

export interface SyncWeldError {
  id: string;
  weldId: string;
  errorType: string;
  errorMessage: string;
  phaseName?: string | null;
  parameterName?: string | null;
  actualValue?: number | null;
  allowedMin?: number | null;
  allowedMax?: number | null;
  recordedAt: string;
}

export interface SyncWeldPhoto {
  id: string;
  weldId: string;
  storagePath: string;
  photoType: string;
  caption?: string | null;
  takenAt: string;
}

export interface SyncSensorLogBatch {
  weldId: string;
  logs: SensorLogRecord[];
}

export interface SyncUploadResult {
  welds: EntitySyncResult;
  weldSteps: EntitySyncResult;
  weldErrors: EntitySyncResult;
  weldPhotos: EntitySyncResult;
  sensorLogs: EntitySyncResult;
  syncedAt: string;
}

export interface EntitySyncResult {
  inserted: number;
  errors: string[];
}

export interface SyncUpdatesResponse {
  projects: unknown[];
  projectUsers: unknown[];
  machines: unknown[];
  sensorCalibrations: unknown[];
  weldingStandards: unknown[];
  weldingParameters: unknown[];
  downloadedAt: string;
}

// ── Pagination ────────────────────────────────────────────────────────────────

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  limit: number;
  offset: number;
}

// ── API Error ─────────────────────────────────────────────────────────────────

export interface ApiErrorResponse {
  error: string;
  code?: string;
  details?: unknown;
}
