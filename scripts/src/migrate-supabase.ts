/**
 * WeldTrace: Supabase Migration Runner
 * 
 * Executes SQL migration files against the Supabase database
 * using the service role key for full admin access.
 * 
 * Usage: pnpm --filter @workspace/scripts run migrate
 */

import { readFileSync } from "fs";
import { join } from "path";

const SUPABASE_URL = process.env["SUPABASE_URL"];
const SERVICE_KEY = process.env["SUPABASE_SERVICE_ROLE_KEY"];

if (!SUPABASE_URL) throw new Error("SUPABASE_URL is required");
if (!SERVICE_KEY) throw new Error("SUPABASE_SERVICE_ROLE_KEY is required");

const MIGRATIONS_DIR = join(process.cwd(), "..", "..", "supabase", "migrations");

async function executeSqlViaRpc(sql: string): Promise<{ success: boolean; error?: string }> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/exec_migration`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_KEY!,
      Authorization: `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify({ sql_text: sql }),
  });

  if (!response.ok) {
    const text = await response.text();
    return { success: false, error: text };
  }

  return { success: true };
}

async function checkTablesExist(): Promise<boolean> {
  const resp = await fetch(
    `${SUPABASE_URL}/rest/v1/welding_standards?select=id&limit=1`,
    {
      headers: {
        apikey: SERVICE_KEY!,
        Authorization: `Bearer ${SERVICE_KEY}`,
      },
    }
  );
  return resp.status !== 404;
}

async function main() {
  console.log("WeldTrace: Supabase Migration Runner");
  console.log("=====================================");
  console.log(`Target: ${SUPABASE_URL}`);

  const alreadyMigrated = await checkTablesExist();
  if (alreadyMigrated) {
    console.log("\n✅ Tables already exist. Checking seed data...");
    
    // Check if seed data exists
    const seedResp = await fetch(
      `${SUPABASE_URL}/rest/v1/welding_standards?select=id&limit=1`,
      {
        headers: {
          apikey: SERVICE_KEY!,
          Authorization: `Bearer ${SERVICE_KEY}`,
        },
      }
    );
    const seedData = await seedResp.json() as unknown[];
    
    if (seedData.length > 0) {
      console.log("✅ Seed data already present.");
    } else {
      console.log("⚠️  No seed data found. Please apply migrations manually.");
    }
    
    return;
  }

  console.log("\n📋 Migration files to apply:");
  const migrations = [
    "001_initial_schema.sql",
    "002_rls_policies.sql",
    "003_seed_welding_standards.sql",
  ];

  for (const migration of migrations) {
    console.log(`  - ${migration}`);
  }

  console.log("\n⚠️  IMPORTANT: Supabase does not support running raw SQL migrations");
  console.log("   via the public REST API. Please apply these migrations manually:");
  console.log("\n   Option 1 — Supabase Dashboard:");
  console.log("   1. Go to your Supabase project → SQL Editor");
  console.log("   2. Paste and run each migration file in order:");
  for (const migration of migrations) {
    console.log(`      supabase/migrations/${migration}`);
  }
  console.log("\n   Option 2 — Supabase CLI (if installed locally):");
  console.log("   supabase db push --project-ref <your-project-ref>");
  console.log("\n   Option 3 — psql direct connection:");
  console.log("   Get DB connection string from: Supabase → Settings → Database");
  console.log("   psql <connection-string> -f supabase/migrations/001_initial_schema.sql");
  console.log("   psql <connection-string> -f supabase/migrations/002_rls_policies.sql");
  console.log("   psql <connection-string> -f supabase/migrations/003_seed_welding_standards.sql");
}

main().catch(console.error);
