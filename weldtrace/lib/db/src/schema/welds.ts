import { pgTable, text, boolean, timestamp, uuid, numeric, pgEnum } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { projectsTable } from "./projects";
import { machinesTable } from "./machines";
import { usersTable } from "./users";
import { weldingStandardsTable, standardCodeEnum, weldTypeEnum } from "./welding_standards";

export const weldStatusEnum = pgEnum("weld_status", ["in_progress", "completed", "cancelled", "failed"]);
export const photoTypeEnum = pgEnum("photo_type", ["pipe_before", "pipe_after", "fitting", "weld_complete", "defect", "general"]);
export const certificateStatusEnum = pgEnum("certificate_status", ["draft", "issued", "revoked"]);

export const weldsTable = pgTable("welds", {
  id: uuid("id").primaryKey().defaultRandom(),
  projectId: uuid("project_id").notNull().references(() => projectsTable.id),
  machineId: uuid("machine_id").notNull().references(() => machinesTable.id),
  operatorId: uuid("operator_id").notNull().references(() => usersTable.id),
  standardId: uuid("standard_id").references(() => weldingStandardsTable.id),
  weldType: weldTypeEnum("weld_type").notNull(),
  status: weldStatusEnum("status").notNull().default("in_progress"),
  pipeMaterial: text("pipe_material").notNull(),
  pipeDiameter: numeric("pipe_diameter").notNull(),
  pipeSdr: text("pipe_sdr"),
  pipeWallThickness: numeric("pipe_wall_thickness"),
  ambientTemperature: numeric("ambient_temperature"),
  gpsLat: numeric("gps_lat", { precision: 10, scale: 7 }),
  gpsLng: numeric("gps_lng", { precision: 10, scale: 7 }),
  standardUsed: standardCodeEnum("standard_used"),
  isCancelled: boolean("is_cancelled").notNull().default(false),
  cancelReason: text("cancel_reason"),
  cancelTimestamp: timestamp("cancel_timestamp", { withTimezone: true }),
  notes: text("notes"),
  startedAt: timestamp("started_at", { withTimezone: true }).notNull().defaultNow(),
  completedAt: timestamp("completed_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
});

export const weldStepsTable = pgTable("weld_steps", {
  id: uuid("id").primaryKey().defaultRandom(),
  weldId: uuid("weld_id").notNull().references(() => weldsTable.id, { onDelete: "cascade" }),
  phaseName: text("phase_name").notNull(),
  phaseOrder: numeric("phase_order").notNull(),
  startedAt: timestamp("started_at", { withTimezone: true }),
  completedAt: timestamp("completed_at", { withTimezone: true }),
  nominalValue: numeric("nominal_value"),
  actualValue: numeric("actual_value"),
  unit: text("unit"),
  validationPassed: boolean("validation_passed"),
  notes: text("notes"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
});

export const weldPhotosTable = pgTable("weld_photos", {
  id: uuid("id").primaryKey().defaultRandom(),
  weldId: uuid("weld_id").notNull().references(() => weldsTable.id, { onDelete: "cascade" }),
  storagePath: text("storage_path").notNull(),
  photoType: photoTypeEnum("photo_type").notNull().default("general"),
  caption: text("caption"),
  takenAt: timestamp("taken_at", { withTimezone: true }).notNull().defaultNow(),
  uploadedBy: uuid("uploaded_by").references(() => usersTable.id),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const weldSignaturesTable = pgTable("weld_signatures", {
  id: uuid("id").primaryKey().defaultRandom(),
  weldId: uuid("weld_id").notNull().references(() => weldsTable.id, { onDelete: "cascade" }),
  signedBy: uuid("signed_by").notNull().references(() => usersTable.id),
  signatureHash: text("signature_hash").notNull(),
  signatureRole: text("signature_role").notNull(),
  signedAt: timestamp("signed_at", { withTimezone: true }).notNull().defaultNow(),
  ipAddress: text("ip_address"),
  deviceInfo: text("device_info"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const weldCertificatesTable = pgTable("weld_certificates", {
  id: uuid("id").primaryKey().defaultRandom(),
  weldId: uuid("weld_id").notNull().references(() => weldsTable.id),
  certificateHash: text("certificate_hash").notNull().unique(),
  issuedBy: uuid("issued_by").references(() => usersTable.id),
  issuedAt: timestamp("issued_at", { withTimezone: true }).notNull().defaultNow(),
  certificateStatus: certificateStatusEnum("certificate_status").notNull().default("draft"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
});

export const insertWeldSchema = createInsertSchema(weldsTable).omit({ id: true, createdAt: true, updatedAt: true });
export type InsertWeld = z.infer<typeof insertWeldSchema>;
export type Weld = typeof weldsTable.$inferSelect;

export const insertWeldStepSchema = createInsertSchema(weldStepsTable).omit({ id: true, createdAt: true, updatedAt: true });
export type InsertWeldStep = z.infer<typeof insertWeldStepSchema>;
export type WeldStep = typeof weldStepsTable.$inferSelect;

export const insertWeldPhotoSchema = createInsertSchema(weldPhotosTable).omit({ id: true, createdAt: true });
export type InsertWeldPhoto = z.infer<typeof insertWeldPhotoSchema>;
export type WeldPhoto = typeof weldPhotosTable.$inferSelect;

export const insertWeldCertificateSchema = createInsertSchema(weldCertificatesTable).omit({ id: true, createdAt: true, updatedAt: true });
export type InsertWeldCertificate = z.infer<typeof insertWeldCertificateSchema>;
export type WeldCertificate = typeof weldCertificatesTable.$inferSelect;
