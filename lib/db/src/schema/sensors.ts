import { pgTable, text, boolean, timestamp, uuid, numeric, date, pgEnum } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { machinesTable } from "./machines";
import { usersTable } from "./users";
import { weldsTable } from "./welds";
import { weldStepsTable } from "./welds";

export const maintenanceTypeEnum = pgEnum("maintenance_type", ["calibration", "repair", "inspection", "service"]);

export const sensorLogsTable = pgTable("sensor_logs", {
  id: uuid("id").primaryKey().defaultRandom(),
  weldId: uuid("weld_id").notNull().references(() => weldsTable.id, { onDelete: "cascade" }),
  weldStepId: uuid("weld_step_id").references(() => weldStepsTable.id, { onDelete: "set null" }),
  recordedAt: timestamp("recorded_at", { withTimezone: true }).notNull(),
  pressureBar: numeric("pressure_bar", { precision: 8, scale: 4 }),
  temperatureCelsius: numeric("temperature_celsius", { precision: 8, scale: 4 }),
  phaseName: text("phase_name"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const weldErrorsTable = pgTable("weld_errors", {
  id: uuid("id").primaryKey().defaultRandom(),
  weldId: uuid("weld_id").notNull().references(() => weldsTable.id, { onDelete: "cascade" }),
  errorType: text("error_type").notNull(),
  errorMessage: text("error_message").notNull(),
  phaseName: text("phase_name"),
  parameterName: text("parameter_name"),
  actualValue: numeric("actual_value"),
  allowedMin: numeric("allowed_min"),
  allowedMax: numeric("allowed_max"),
  recordedAt: timestamp("recorded_at", { withTimezone: true }).notNull().defaultNow(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const machineMaitenanceTable = pgTable("machine_maintenance", {
  id: uuid("id").primaryKey().defaultRandom(),
  machineId: uuid("machine_id").notNull().references(() => machinesTable.id, { onDelete: "cascade" }),
  maintenanceType: maintenanceTypeEnum("maintenance_type").notNull(),
  performedBy: uuid("performed_by").references(() => usersTable.id, { onDelete: "set null" }),
  performedAt: timestamp("performed_at", { withTimezone: true }).notNull(),
  nextDueDate: date("next_due_date"),
  notes: text("notes"),
  attachmentsPath: text("attachments_path"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const sensorCalibrationsTable = pgTable("sensor_calibrations", {
  id: uuid("id").primaryKey().defaultRandom(),
  machineId: uuid("machine_id").notNull().references(() => machinesTable.id, { onDelete: "cascade" }),
  sensorSerial: text("sensor_serial").notNull(),
  calibrationDate: date("calibration_date").notNull(),
  calibratedBy: uuid("calibrated_by").references(() => usersTable.id, { onDelete: "set null" }),
  referenceDevice: text("reference_device").notNull(),
  referenceCertificate: text("reference_certificate").notNull(),
  offsetValue: numeric("offset_value", { precision: 10, scale: 6 }).notNull().default("0"),
  slopeValue: numeric("slope_value", { precision: 10, scale: 6 }).notNull().default("1"),
  notes: text("notes"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const insertSensorLogSchema = createInsertSchema(sensorLogsTable).omit({ id: true, createdAt: true });
export type InsertSensorLog = z.infer<typeof insertSensorLogSchema>;
export type SensorLog = typeof sensorLogsTable.$inferSelect;

export const insertSensorLogBatchSchema = z.object({
  weldId: z.string().uuid(),
  logs: z.array(insertSensorLogSchema.omit({ weldId: true })).min(1).max(500),
});
export type InsertSensorLogBatch = z.infer<typeof insertSensorLogBatchSchema>;

export const insertWeldErrorSchema = createInsertSchema(weldErrorsTable).omit({ id: true, createdAt: true });
export type InsertWeldError = z.infer<typeof insertWeldErrorSchema>;
export type WeldError = typeof weldErrorsTable.$inferSelect;

export const insertMaintenanceSchema = createInsertSchema(machineMaitenanceTable).omit({ id: true, createdAt: true });
export type InsertMaintenance = z.infer<typeof insertMaintenanceSchema>;
export type Maintenance = typeof machineMaitenanceTable.$inferSelect;

export const insertSensorCalibrationSchema = createInsertSchema(sensorCalibrationsTable).omit({ id: true, createdAt: true });
export type InsertSensorCalibration = z.infer<typeof insertSensorCalibrationSchema>;
export type SensorCalibration = typeof sensorCalibrationsTable.$inferSelect;
