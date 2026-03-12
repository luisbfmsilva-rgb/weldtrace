import { pgTable, text, boolean, timestamp, uuid, date, numeric, pgEnum } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { companiesTable } from "./companies";
import { usersTable } from "./users";

export const projectStatusEnum = pgEnum("project_status", ["active", "completed", "suspended"]);

export const projectsTable = pgTable("projects", {
  id: uuid("id").primaryKey().defaultRandom(),
  companyId: uuid("company_id").notNull().references(() => companiesTable.id),
  name: text("name").notNull(),
  description: text("description"),
  location: text("location"),
  gpsLat: numeric("gps_lat", { precision: 10, scale: 7 }),
  gpsLng: numeric("gps_lng", { precision: 10, scale: 7 }),
  status: projectStatusEnum("status").notNull().default("active"),
  startDate: date("start_date"),
  endDate: date("end_date"),
  clientName: text("client_name"),
  contractNumber: text("contract_number"),
  createdBy: uuid("created_by").notNull().references(() => usersTable.id),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
});

export const projectUsersTable = pgTable("project_users", {
  id: uuid("id").primaryKey().defaultRandom(),
  projectId: uuid("project_id").notNull().references(() => projectsTable.id, { onDelete: "cascade" }),
  userId: uuid("user_id").notNull().references(() => usersTable.id, { onDelete: "cascade" }),
  roleInProject: text("role_in_project").notNull(),
  assignedAt: timestamp("assigned_at", { withTimezone: true }).notNull().defaultNow(),
  assignedBy: uuid("assigned_by").references(() => usersTable.id),
});

export const insertProjectSchema = createInsertSchema(projectsTable).omit({ id: true, createdAt: true, updatedAt: true });
export type InsertProject = z.infer<typeof insertProjectSchema>;
export type Project = typeof projectsTable.$inferSelect;

export const insertProjectUserSchema = createInsertSchema(projectUsersTable).omit({ id: true, assignedAt: true });
export type InsertProjectUser = z.infer<typeof insertProjectUserSchema>;
export type ProjectUser = typeof projectUsersTable.$inferSelect;
