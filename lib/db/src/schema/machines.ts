import { pgTable, text, boolean, timestamp, uuid, integer, date, pgEnum } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { companiesTable } from "./companies";
import { usersTable } from "./users";
import { projectsTable } from "./projects";

export const machineTypeEnum = pgEnum("machine_type", ["electrofusion", "butt_fusion", "universal"]);

export const machinesTable = pgTable("machines", {
  id: uuid("id").primaryKey().defaultRandom(),
  companyId: uuid("company_id").notNull().references(() => companiesTable.id),
  serialNumber: text("serial_number").notNull(),
  model: text("model").notNull(),
  manufacturer: text("manufacturer").notNull(),
  type: machineTypeEnum("type").notNull(),
  manufactureYear: integer("manufacture_year"),
  lastCalibrationDate: date("last_calibration_date"),
  nextCalibrationDate: date("next_calibration_date"),
  isApproved: boolean("is_approved").notNull().default(false),
  approvedBy: uuid("approved_by").references(() => usersTable.id),
  approvedAt: timestamp("approved_at", { withTimezone: true }),
  isActive: boolean("is_active").notNull().default(true),
  notes: text("notes"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
});

export const projectMachinesTable = pgTable("project_machines", {
  id: uuid("id").primaryKey().defaultRandom(),
  projectId: uuid("project_id").notNull().references(() => projectsTable.id, { onDelete: "cascade" }),
  machineId: uuid("machine_id").notNull().references(() => machinesTable.id, { onDelete: "cascade" }),
  assignedAt: timestamp("assigned_at", { withTimezone: true }).notNull().defaultNow(),
  assignedBy: uuid("assigned_by").references(() => usersTable.id),
});

export const insertMachineSchema = createInsertSchema(machinesTable).omit({ id: true, createdAt: true, updatedAt: true });
export type InsertMachine = z.infer<typeof insertMachineSchema>;
export type Machine = typeof machinesTable.$inferSelect;

export const insertProjectMachineSchema = createInsertSchema(projectMachinesTable).omit({ id: true, assignedAt: true });
export type InsertProjectMachine = z.infer<typeof insertProjectMachineSchema>;
export type ProjectMachine = typeof projectMachinesTable.$inferSelect;
