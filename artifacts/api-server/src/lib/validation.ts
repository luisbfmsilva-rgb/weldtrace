// ─────────────────────────────────────────────────────────────────────────────
// WeldTrace — Zod validation schemas for all API endpoints
// ─────────────────────────────────────────────────────────────────────────────

import { z } from "zod/v4";

// ── Primitives ────────────────────────────────────────────────────────────────

const uuid = z.string().uuid("Must be a valid UUID");
const isoTimestamp = z.string().regex(
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/,
  "Must be an ISO 8601 timestamp",
);
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Must be a date in YYYY-MM-DD format");

const userRole = z.enum(["manager", "supervisor", "welder", "auditor"]);
const weldType = z.enum(["electrofusion", "butt_fusion"]);
const standardCode = z.enum(["DVS_2207", "ISO_21307", "ASTM_F2620"]);
const weldStatus = z.enum(["in_progress", "completed", "cancelled", "failed"]);

// ── Auth ──────────────────────────────────────────────────────────────────────

export const LoginBody = z.object({
  email: z.email("Invalid email address"),
  password: z.string().min(8, "Password must be at least 8 characters"),
});
export type LoginBody = z.infer<typeof LoginBody>;

export const RegisterBody = z.object({
  email: z.email("Invalid email address"),
  password: z.string().min(8, "Password must be at least 8 characters"),
  firstName: z.string().min(1).max(100),
  lastName: z.string().min(1).max(100),
  role: userRole,
  companyId: uuid,
  welderCertificationNumber: z.string().max(100).optional(),
  certificationExpiry: isoDate.optional(),
});
export type RegisterBody = z.infer<typeof RegisterBody>;

export const RefreshBody = z.object({
  refreshToken: z.string().min(1, "refreshToken is required"),
});
export type RefreshBody = z.infer<typeof RefreshBody>;

// ── Projects ──────────────────────────────────────────────────────────────────

export const CreateProjectBody = z.object({
  name: z.string().min(1).max(255),
  description: z.string().max(2000).optional(),
  location: z.string().max(500).optional(),
  gpsLat: z.number().min(-90).max(90).optional(),
  gpsLng: z.number().min(-180).max(180).optional(),
  startDate: isoDate.optional(),
  endDate: isoDate.optional(),
  clientName: z.string().max(255).optional(),
  contractNumber: z.string().max(100).optional(),
});
export type CreateProjectBody = z.infer<typeof CreateProjectBody>;

export const UpdateProjectBody = CreateProjectBody.partial().extend({
  status: z.enum(["active", "completed", "suspended"]).optional(),
});
export type UpdateProjectBody = z.infer<typeof UpdateProjectBody>;

export const AssignUserBody = z.object({
  userId: uuid,
  roleInProject: userRole,
});
export type AssignUserBody = z.infer<typeof AssignUserBody>;

export const AssignMachineBody = z.object({
  machineId: uuid,
});
export type AssignMachineBody = z.infer<typeof AssignMachineBody>;

export const ProjectsQuery = z.object({
  status: z.enum(["active", "completed", "suspended"]).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});
export type ProjectsQuery = z.infer<typeof ProjectsQuery>;

// ── Machines ──────────────────────────────────────────────────────────────────

export const CreateMachineBody = z.object({
  serialNumber: z.string().min(1).max(100),
  model: z.string().min(1).max(255),
  manufacturer: z.string().min(1).max(255),
  type: z.enum(["electrofusion", "butt_fusion", "universal"]),
  manufactureYear: z.number().int().min(1900).max(2100).optional(),
  notes: z.string().max(2000).optional(),
});
export type CreateMachineBody = z.infer<typeof CreateMachineBody>;

export const UpdateMachineBody = z.object({
  model: z.string().min(1).max(255).optional(),
  manufacturer: z.string().min(1).max(255).optional(),
  notes: z.string().max(2000).optional(),
  isActive: z.boolean().optional(),
  lastCalibrationDate: isoDate.optional(),
  nextCalibrationDate: isoDate.optional(),
});
export type UpdateMachineBody = z.infer<typeof UpdateMachineBody>;

export const CreateMaintenanceBody = z.object({
  maintenanceType: z.enum(["calibration", "repair", "inspection", "service"]),
  performedAt: isoTimestamp,
  nextDueDate: isoDate.optional(),
  notes: z.string().max(2000).optional(),
  attachmentsPath: z.string().max(500).optional(),
});
export type CreateMaintenanceBody = z.infer<typeof CreateMaintenanceBody>;

export const CreateCalibrationBody = z.object({
  sensorSerial: z.string().min(1).max(100),
  calibrationDate: isoDate,
  referenceDevice: z.string().min(1).max(255),
  referenceCertificate: z.string().min(1).max(255),
  offsetValue: z.number().default(0),
  slopeValue: z.number().positive().default(1),
  notes: z.string().max(2000).optional(),
});
export type CreateCalibrationBody = z.infer<typeof CreateCalibrationBody>;

// ── Welds ─────────────────────────────────────────────────────────────────────

export const StartWeldBody = z.object({
  projectId: uuid,
  machineId: uuid,
  weldType,
  pipeMaterial: z.string().min(1).max(100),
  pipeDiameter: z.number().positive("Pipe diameter must be positive"),
  pipeSdr: z.string().max(20).optional(),
  pipeWallThickness: z.number().positive().optional(),
  ambientTemperature: z.number().min(-50).max(80).optional(),
  gpsLat: z.number().min(-90).max(90).optional(),
  gpsLng: z.number().min(-180).max(180).optional(),
  standardUsed: standardCode.optional(),
  standardId: uuid.optional(),
  notes: z.string().max(2000).optional(),
});
export type StartWeldBody = z.infer<typeof StartWeldBody>;

export const RecordStepBody = z.object({
  phaseName: z.string().min(1).max(100),
  phaseOrder: z.number().int().min(1).max(20),
  startedAt: isoTimestamp.optional(),
  completedAt: isoTimestamp.optional(),
  nominalValue: z.number().optional(),
  actualValue: z.number().optional(),
  unit: z.string().max(50).optional(),
  validationPassed: z.boolean().optional(),
  notes: z.string().max(2000).optional(),
});
export type RecordStepBody = z.infer<typeof RecordStepBody>;

export const RecordErrorBody = z.object({
  errorType: z.string().min(1).max(100),
  errorMessage: z.string().min(1).max(1000),
  phaseName: z.string().max(100).optional(),
  parameterName: z.string().max(100).optional(),
  actualValue: z.number().optional(),
  allowedMin: z.number().optional(),
  allowedMax: z.number().optional(),
});
export type RecordErrorBody = z.infer<typeof RecordErrorBody>;

export const CancelWeldBody = z.object({
  cancelReason: z.string().min(5).max(1000, "Cancel reason must be between 5 and 1000 characters"),
});
export type CancelWeldBody = z.infer<typeof CancelWeldBody>;

export const WeldsQuery = z.object({
  projectId: uuid.optional(),
  status: weldStatus.optional(),
  operatorId: uuid.optional(),
  weldType: weldType.optional(),
  fromDate: isoTimestamp.optional(),
  toDate: isoTimestamp.optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});
export type WeldsQuery = z.infer<typeof WeldsQuery>;

// ── Sensor Logs ───────────────────────────────────────────────────────────────

export const SensorLogRecordSchema = z.object({
  recordedAt: isoTimestamp,
  pressureBar: z.number().min(0).max(1000).nullable().optional(),
  temperatureCelsius: z.number().min(-50).max(500).nullable().optional(),
  phaseName: z.string().max(100).nullable().optional(),
  weldStepId: uuid.nullable().optional(),
});
export type SensorLogRecordSchema = z.infer<typeof SensorLogRecordSchema>;

export const SensorLogBatchBody = z.object({
  weldId: uuid,
  records: z
    .array(SensorLogRecordSchema)
    .min(1, "At least one record is required")
    .max(200, "Maximum 200 records per batch — split into smaller requests"),
});
export type SensorLogBatchBody = z.infer<typeof SensorLogBatchBody>;

export const SensorLogsQuery = z.object({
  phaseName: z.string().max(100).optional(),
  limit: z.coerce.number().int().min(1).max(10000).default(3600),
});
export type SensorLogsQuery = z.infer<typeof SensorLogsQuery>;

// ── Sync ──────────────────────────────────────────────────────────────────────

const SyncWeldSchema = z.object({
  id: uuid,
  projectId: uuid,
  machineId: uuid,
  weldType,
  status: weldStatus,
  pipeMaterial: z.string().min(1),
  pipeDiameter: z.number().positive(),
  pipeSdr: z.string().nullable().optional(),
  pipeWallThickness: z.number().nullable().optional(),
  ambientTemperature: z.number().nullable().optional(),
  gpsLat: z.number().nullable().optional(),
  gpsLng: z.number().nullable().optional(),
  standardUsed: standardCode.nullable().optional(),
  standardId: uuid.nullable().optional(),
  isCancelled: z.boolean().default(false),
  cancelReason: z.string().nullable().optional(),
  cancelTimestamp: isoTimestamp.nullable().optional(),
  notes: z.string().nullable().optional(),
  startedAt: isoTimestamp,
  completedAt: isoTimestamp.nullable().optional(),
});

const SyncWeldStepSchema = z.object({
  id: uuid,
  weldId: uuid,
  phaseName: z.string().min(1),
  phaseOrder: z.number().int().min(1),
  startedAt: isoTimestamp.nullable().optional(),
  completedAt: isoTimestamp.nullable().optional(),
  nominalValue: z.number().nullable().optional(),
  actualValue: z.number().nullable().optional(),
  unit: z.string().nullable().optional(),
  validationPassed: z.boolean().nullable().optional(),
  notes: z.string().nullable().optional(),
});

const SyncWeldErrorSchema = z.object({
  id: uuid,
  weldId: uuid,
  errorType: z.string().min(1),
  errorMessage: z.string().min(1),
  phaseName: z.string().nullable().optional(),
  parameterName: z.string().nullable().optional(),
  actualValue: z.number().nullable().optional(),
  allowedMin: z.number().nullable().optional(),
  allowedMax: z.number().nullable().optional(),
  recordedAt: isoTimestamp,
});

const SyncWeldPhotoSchema = z.object({
  id: uuid,
  weldId: uuid,
  storagePath: z.string().min(1),
  photoType: z.enum(["pipe_before", "pipe_after", "fitting", "weld_complete", "defect", "general"]),
  caption: z.string().nullable().optional(),
  takenAt: isoTimestamp,
});

const SyncSensorLogBatchSchema = z.object({
  weldId: uuid,
  logs: z.array(SensorLogRecordSchema).min(1).max(200),
});

export const SyncUploadBody = z.object({
  welds: z.array(SyncWeldSchema).max(100).default([]),
  weldSteps: z.array(SyncWeldStepSchema).max(500).default([]),
  weldErrors: z.array(SyncWeldErrorSchema).max(200).default([]),
  weldPhotos: z.array(SyncWeldPhotoSchema).max(50).default([]),
  sensorLogBatches: z.array(SyncSensorLogBatchSchema).max(20).default([]),
});
export type SyncUploadBody = z.infer<typeof SyncUploadBody>;

export const SyncUpdatesQuery = z.object({
  since: isoTimestamp.describe("ISO 8601 timestamp — only changes after this date are returned"),
  projectId: uuid.optional().describe("Scope updates to a specific project"),
});
export type SyncUpdatesQuery = z.infer<typeof SyncUpdatesQuery>;

// ── Standards ─────────────────────────────────────────────────────────────────

export const WeldingStandardsQuery = z.object({
  weldType: weldType.optional(),
  pipeMaterial: z.string().max(100).optional(),
  standardCode: standardCode.optional(),
});
export type WeldingStandardsQuery = z.infer<typeof WeldingStandardsQuery>;

export const WeldingParametersQuery = z.object({
  phaseName: z.string().max(100).optional(),
  pipeDiameter: z.coerce.number().positive().optional(),
  pipeSdr: z.string().max(20).optional(),
});
export type WeldingParametersQuery = z.infer<typeof WeldingParametersQuery>;
