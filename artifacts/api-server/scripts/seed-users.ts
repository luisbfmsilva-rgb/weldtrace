/**
 * Seed script — creates default test users in Supabase.
 * Run with: pnpm --filter @workspace/api-server exec tsx scripts/seed-users.ts
 */
import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env["SUPABASE_URL"];
const supabaseServiceKey = process.env["SUPABASE_SERVICE_ROLE_KEY"];

if (!supabaseUrl || !supabaseServiceKey) {
  console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const TEST_USERS = [
  {
    email: "admin@weldtrace.dev",
    password: "WeldTrace2024!",
    role: "manager" as const,
    firstName: "Admin",
    lastName: "WeldTrace",
    companyId: null as string | null,
  },
  {
    email: "welder@weldtrace.dev",
    password: "WeldTrace2024!",
    role: "welder" as const,
    firstName: "João",
    lastName: "Silva",
    companyId: null as string | null,
  },
  {
    email: "inspector@weldtrace.dev",
    password: "WeldTrace2024!",
    role: "inspector" as const,
    firstName: "Maria",
    lastName: "Santos",
    companyId: null as string | null,
  },
];

async function ensureCompany(): Promise<string> {
  const { data: existing } = await supabase
    .from("companies")
    .select("id")
    .eq("name", "WeldTrace Demo")
    .single();

  if (existing) return existing.id;

  const { data, error } = await supabase
    .from("companies")
    .insert({ name: "WeldTrace Demo", country: "PT" })
    .select("id")
    .single();

  if (error || !data) throw new Error("Failed to create company: " + error?.message);
  return data.id;
}

async function createUser(
  companyId: string,
  user: typeof TEST_USERS[number],
): Promise<void> {
  // Check if auth user already exists
  const { data: listData } = await supabase.auth.admin.listUsers();
  const exists = listData?.users?.find((u) => u.email === user.email);

  let userId: string;

  if (exists) {
    console.log(`  ↳ auth user already exists: ${user.email}`);
    userId = exists.id;
  } else {
    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email: user.email,
      password: user.password,
      email_confirm: true,
    });

    if (authError || !authData.user) {
      throw new Error(`Auth create failed for ${user.email}: ${authError?.message}`);
    }
    userId = authData.user.id;
    console.log(`  ↳ auth user created: ${user.email} (${userId})`);
  }

  // Upsert profile row
  const { error: profileError } = await supabase.from("users").upsert(
    {
      id: userId,
      company_id: companyId,
      role: user.role,
      first_name: user.firstName,
      last_name: user.lastName,
      email: user.email,
      is_active: true,
    },
    { onConflict: "id" },
  );

  if (profileError) {
    throw new Error(`Profile upsert failed for ${user.email}: ${profileError.message}`);
  }
  console.log(`  ↳ profile upserted: ${user.role}`);
}

async function main() {
  console.log("🔧 WeldTrace seed starting...\n");

  const companyId = await ensureCompany();
  console.log(`✓ Company ID: ${companyId}\n`);

  for (const user of TEST_USERS) {
    console.log(`Creating user: ${user.email}`);
    user.companyId = companyId;
    await createUser(companyId, user);
  }

  console.log("\n✅ Seed complete!");
  console.log("\nTest credentials:");
  for (const u of TEST_USERS) {
    console.log(`  [${u.role.padEnd(9)}]  ${u.email}  /  ${u.password}`);
  }
}

main().catch((err) => {
  console.error("Seed failed:", err.message);
  process.exit(1);
});
