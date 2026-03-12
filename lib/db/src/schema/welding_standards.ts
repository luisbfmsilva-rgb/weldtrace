import { pgTable, text, boolean, timestamp, uuid, date, numeric, integer, pgEnum } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";

export const standardCodeEnum = pgEnum("standard_code", ["DVS_2207", "ISO_21307", "ASTM_F2620"]);
export const weldTypeEnum = pgEnum("weld_type", ["electrofusion", "butt_fusion"]);

export const weldingStandardsTable = pgTable("welding_standards", {
  id: uuid("id").primaryKey().defaultRandom(),
  standardCode: standardCodeEnum("standard_code").notNull(),
  weldType: weldTypeEnum("weld_type").notNull(),
  pipeMaterial: text("pipe_material").notNull(),
  version: text("version").notNull(),
  description: text("description"),
  validFrom: date("valid_from").notNull(),
  validUntil: date("valid_until"),
  isActive: boolean("is_active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const weldingParametersTable = pgTable("welding_parameters", {
  id: uuid("id").primaryKey().defaultRandom(),
  standardId: uuid("standard_id").notNull().references(() => weldingStandardsTable.id, { onDelete: "cascade" }),
  phaseName: text("phase_name").notNull(),
  phaseOrder: integer("phase_order").notNull(),
  parameterName: text("parameter_name").notNull(),
  unit: text("unit").notNull(),
  nominalValue: numeric("nominal_value"),
  minValue: numeric("min_value"),
  maxValue: numeric("max_value"),
  pipeDiameterMin: numeric("pipe_diameter_min"),
  pipeDiameterMax: numeric("pipe_diameter_max"),
  pipeSdr: text("pipe_sdr"),
  tolerancePct: numeric("tolerance_pct"),
  notes: text("notes"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const insertWeldingStandardSchema = createInsertSchema(weldingStandardsTable).omit({ id: true, createdAt: true });
export type InsertWeldingStandard = z.infer<typeof insertWeldingStandardSchema>;
export type WeldingStandard = typeof weldingStandardsTable.$inferSelect;

export const insertWeldingParameterSchema = createInsertSchema(weldingParametersTable).omit({ id: true, createdAt: true });
export type InsertWeldingParameter = z.infer<typeof insertWeldingParameterSchema>;
export type WeldingParameter = typeof weldingParametersTable.$inferSelect;
