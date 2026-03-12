import { Response } from "express";
import { supabaseAdmin } from "../lib/supabase.js";
import { sendError, ApiError, NotFoundError } from "../lib/errors.js";
import { LoginBody, RegisterBody, RefreshBody } from "../lib/validation.js";
import type { AuthenticatedRequest } from "../middlewares/auth.js";
import type { AssignedProject } from "../types/index.js";

const SUPABASE_URL = process.env["SUPABASE_URL"]!;
const SUPABASE_ANON_KEY = process.env["SUPABASE_ANON_KEY"]!;

// ── Internal helpers ──────────────────────────────────────────────────────────

async function fetchAssignedProjects(userId: string): Promise<AssignedProject[]> {
  const { data, error } = await supabaseAdmin
    .from("project_users")
    .select(`
      role_in_project,
      project:projects(id, name, status, location)
    `)
    .eq("user_id", userId);

  if (error || !data) return [];

  return data.map((row) => {
    const p = row.project as unknown as { id: string; name: string; status: string; location: string | null } | null;
    return {
      id: p?.id ?? "",
      name: p?.name ?? "",
      status: p?.status ?? "",
      location: p?.location ?? null,
      roleInProject: row.role_in_project,
    };
  });
}

async function supabaseAuthRequest(
  path: string,
  body: Record<string, unknown>,
): Promise<Response & { json: () => Promise<Record<string, unknown>> }> {
  return fetch(`${SUPABASE_URL}/auth/v1${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SUPABASE_ANON_KEY,
    },
    body: JSON.stringify(body),
  }) as unknown as Response & { json: () => Promise<Record<string, unknown>> };
}

// ── Controllers ───────────────────────────────────────────────────────────────

export async function login(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const body = LoginBody.parse(req.body);

    const response = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: SUPABASE_ANON_KEY },
      body: JSON.stringify({ email: body.email, password: body.password }),
    });

    const data = await response.json() as Record<string, unknown>;

    if (!response.ok) {
      const msg = (data as { error_description?: string }).error_description ?? "Invalid credentials";
      throw new ApiError(401, msg, "AUTH_FAILED");
    }

    const userId = (data.user as { id?: string } | undefined)?.id;
    if (!userId) throw new ApiError(500, "User ID missing from auth response", "AUTH_ERROR");

    const { data: profile, error: profileError } = await supabaseAdmin
      .from("users")
      .select("id, role, company_id, first_name, last_name, email, is_active, welder_certification_number, certification_expiry")
      .eq("id", userId)
      .single();

    if (profileError || !profile) {
      throw new ApiError(403, "User profile not found. Contact your administrator.", "PROFILE_NOT_FOUND");
    }

    if (!profile.is_active) {
      throw new ApiError(403, "Account is inactive. Contact your administrator.", "ACCOUNT_INACTIVE");
    }

    const assignedProjects = await fetchAssignedProjects(userId);

    res.json({
      accessToken: data["access_token"],
      refreshToken: data["refresh_token"],
      expiresIn: data["expires_in"],
      user: {
        id: profile.id,
        email: profile.email,
        role: profile.role,
        companyId: profile.company_id,
        firstName: profile.first_name,
        lastName: profile.last_name,
        assignedProjects,
      },
    });
  } catch (err) {
    sendError(res, err);
  }
}

export async function register(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const body = RegisterBody.parse(req.body);

    // Only managers can register new users; this route is guarded externally
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email: body.email,
      password: body.password,
      email_confirm: true,
    });

    if (authError || !authData.user) {
      throw new ApiError(400, authError?.message ?? "Failed to create auth user", "AUTH_CREATE_FAILED");
    }

    const { data: profile, error: profileError } = await supabaseAdmin
      .from("users")
      .insert({
        id: authData.user.id,
        company_id: body.companyId,
        role: body.role,
        first_name: body.firstName,
        last_name: body.lastName,
        email: body.email,
        welder_certification_number: body.welderCertificationNumber ?? null,
        certification_expiry: body.certificationExpiry ?? null,
      })
      .select("id, email, role, first_name, last_name, company_id")
      .single();

    if (profileError) {
      // Roll back the auth user if profile creation fails
      await supabaseAdmin.auth.admin.deleteUser(authData.user.id);
      throw new ApiError(500, "Failed to create user profile: " + profileError.message, "PROFILE_CREATE_FAILED");
    }

    res.status(201).json({
      message: "User created successfully",
      user: {
        id: profile.id,
        email: profile.email,
        role: profile.role,
        companyId: profile.company_id,
        firstName: profile.first_name,
        lastName: profile.last_name,
      },
    });
  } catch (err) {
    sendError(res, err);
  }
}

export async function refresh(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { refreshToken } = RefreshBody.parse(req.body);

    const response = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: SUPABASE_ANON_KEY },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });

    const data = await response.json() as Record<string, unknown>;

    if (!response.ok) {
      throw new ApiError(401, "Refresh token is invalid or expired", "TOKEN_EXPIRED");
    }

    res.json({
      accessToken: data["access_token"],
      refreshToken: data["refresh_token"],
      expiresIn: data["expires_in"],
    });
  } catch (err) {
    sendError(res, err);
  }
}

export async function me(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { data: profile, error } = await supabaseAdmin
      .from("users")
      .select("id, email, role, company_id, first_name, last_name, welder_certification_number, certification_expiry, is_active")
      .eq("id", req.user!.id)
      .single();

    if (error || !profile) {
      throw new NotFoundError("User profile");
    }

    const assignedProjects = await fetchAssignedProjects(req.user!.id);

    res.json({
      user: {
        id: profile.id,
        email: profile.email,
        role: profile.role,
        companyId: profile.company_id,
        firstName: profile.first_name,
        lastName: profile.last_name,
        welderCertificationNumber: profile.welder_certification_number,
        certificationExpiry: profile.certification_expiry,
        isActive: profile.is_active,
        assignedProjects,
      },
    });
  } catch (err) {
    sendError(res, err);
  }
}

export async function logout(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    await req.supabaseClient?.auth.signOut();
    res.json({ message: "Logged out successfully" });
  } catch (err) {
    sendError(res, err);
  }
}
