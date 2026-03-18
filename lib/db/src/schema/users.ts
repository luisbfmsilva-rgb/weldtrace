import { pgTable, text, boolean, timestamp, uuid, date, pgEnum } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { companiesTable } from "./companies";

export const userRoleEnum = pgEnum("user_role", ["manager", "supervisor", "welder", "auditor"]);

export const usersTable = pgTable("users", {
  id: uuid("id").primaryKey(),
  companyId: uuid("company_id").notNull().references(() => companiesTable.id),
  role: userRoleEnum("role").notNull(),
  firstName: text("first_name").notNull(),
  lastName: text("last_name").notNull(),
  email: text("email").notNull(),
  welderCertificationNumber: text("welder_certification_number"),
  certificationExpiry: date("certification_expiry"),
  isActive: boolean("is_active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
});

export const insertUserSchema = createInsertSchema(usersTable).omit({ createdAt: true, updatedAt: true });
export type InsertUser = z.infer<typeof insertUserSchema>;
export type User = typeof usersTable.$inferSelect;
