import { Router, type IRouter } from "express";
import { supabaseAdmin } from "../lib/supabase.js";
import { requireAuth, type AuthenticatedRequest } from "../middlewares/auth.js";

const router: IRouter = Router();

router.post("/auth/register", async (req, res): Promise<void> => {
  const { email, password, firstName, lastName, role, companyId, welderCertificationNumber } = req.body;

  if (!email || !password || !firstName || !lastName || !role || !companyId) {
    res.status(400).json({ error: "email, password, firstName, lastName, role, and companyId are required" });
    return;
  }

  const validRoles = ["manager", "supervisor", "welder", "auditor"];
  if (!validRoles.includes(role)) {
    res.status(400).json({ error: `Invalid role. Must be one of: ${validRoles.join(", ")}` });
    return;
  }

  const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });

  if (authError || !authData.user) {
    res.status(400).json({ error: authError?.message ?? "Failed to create auth user" });
    return;
  }

  const { data: profile, error: profileError } = await supabaseAdmin
    .from("users")
    .insert({
      id: authData.user.id,
      company_id: companyId,
      role,
      first_name: firstName,
      last_name: lastName,
      email,
      welder_certification_number: welderCertificationNumber ?? null,
    })
    .select()
    .single();

  if (profileError) {
    await supabaseAdmin.auth.admin.deleteUser(authData.user.id);
    res.status(500).json({ error: "Failed to create user profile: " + profileError.message });
    return;
  }

  res.status(201).json({
    message: "User created successfully",
    user: {
      id: profile.id,
      email: profile.email,
      role: profile.role,
      firstName: profile.first_name,
      lastName: profile.last_name,
    },
  });
});

router.post("/auth/login", async (req, res): Promise<void> => {
  const { email, password } = req.body;

  if (!email || !password) {
    res.status(400).json({ error: "email and password are required" });
    return;
  }

  const supabaseUrl = process.env["SUPABASE_URL"]!;
  const supabaseAnonKey = process.env["SUPABASE_ANON_KEY"]!;

  const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: supabaseAnonKey,
    },
    body: JSON.stringify({ email, password }),
  });

  const data = await response.json() as Record<string, unknown>;

  if (!response.ok) {
    res.status(401).json({ error: (data as { error_description?: string }).error_description ?? "Invalid credentials" });
    return;
  }

  const userId = (data.user as { id?: string } | undefined)?.id;
  if (!userId) {
    res.status(500).json({ error: "User ID not found in auth response" });
    return;
  }

  const { data: profile } = await supabaseAdmin
    .from("users")
    .select("id, role, company_id, first_name, last_name, email, is_active")
    .eq("id", userId)
    .single();

  if (!profile || !profile.is_active) {
    res.status(403).json({ error: "User account is inactive. Contact your administrator." });
    return;
  }

  res.json({
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresIn: data.expires_in,
    user: {
      id: profile.id,
      email: profile.email,
      role: profile.role,
      companyId: profile.company_id,
      firstName: profile.first_name,
      lastName: profile.last_name,
    },
  });
});

router.post("/auth/refresh", async (req, res): Promise<void> => {
  const { refreshToken } = req.body;
  if (!refreshToken) {
    res.status(400).json({ error: "refreshToken is required" });
    return;
  }

  const supabaseUrl = process.env["SUPABASE_URL"]!;
  const supabaseAnonKey = process.env["SUPABASE_ANON_KEY"]!;

  const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: supabaseAnonKey,
    },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });

  const data = await response.json() as Record<string, unknown>;

  if (!response.ok) {
    res.status(401).json({ error: "Refresh token is invalid or expired" });
    return;
  }

  res.json({
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresIn: data.expires_in,
  });
});

router.get("/auth/me", requireAuth, async (req: AuthenticatedRequest, res): Promise<void> => {
  res.json({ user: req.user });
});

router.post("/auth/logout", requireAuth, async (req: AuthenticatedRequest, res): Promise<void> => {
  await req.supabaseClient?.auth.signOut();
  res.json({ message: "Logged out successfully" });
});

export default router;
