import { Request, Response, NextFunction } from "express";
import { createUserClient } from "../lib/supabase.js";

export interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    email: string;
    role: string;
    companyId: string;
  };
  supabaseClient?: ReturnType<typeof createUserClient>;
}

export async function requireAuth(
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "Missing or invalid Authorization header" });
    return;
  }

  const token = authHeader.slice(7);

  try {
    const client = createUserClient(token);
    const { data: { user }, error } = await client.auth.getUser();

    if (error || !user) {
      res.status(401).json({ error: "Invalid or expired token" });
      return;
    }

    const { data: profile, error: profileError } = await client
      .from("users")
      .select("id, role, company_id")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
      res.status(403).json({ error: "User profile not found. Contact your administrator." });
      return;
    }

    req.user = {
      id: user.id,
      email: user.email ?? "",
      role: profile.role,
      companyId: profile.company_id,
    };
    req.supabaseClient = client;

    next();
  } catch {
    res.status(401).json({ error: "Authentication failed" });
  }
}

export function requireRole(...roles: string[]) {
  return (req: AuthenticatedRequest, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({ error: "Not authenticated" });
      return;
    }
    if (!roles.includes(req.user.role)) {
      res.status(403).json({ error: `Access denied. Required role: ${roles.join(" or ")}` });
      return;
    }
    next();
  };
}
