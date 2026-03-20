import { Response } from "express";
import { z } from "zod";

import { supabaseAdmin } from "../lib/supabase.js";
import { sendError, ApiError } from "../lib/errors.js";
import type { AuthenticatedRequest } from "../middlewares/auth.js";

const UpdateUserBody = z.object({
  firstName:                  z.string().min(1).optional(),
  lastName:                   z.string().min(1).optional(),
  role:                       z.enum(["manager", "supervisor", "welder", "auditor"]).optional(),
  isActive:                   z.boolean().optional(),
  welderCertificationNumber:  z.string().nullable().optional(),
  certificationExpiry:        z.string().nullable().optional(),
});

export async function listUsers(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const companyId = req.user?.companyId;
    if (!companyId) {
      throw new ApiError(400, "Company ID not found on token", "NO_COMPANY");
    }

    const { data, error } = await supabaseAdmin
      .from("users")
      .select(
        "id, email, role, first_name, last_name, is_active, " +
        "welder_certification_number, certification_expiry"
      )
      .eq("company_id", companyId)
      .order("last_name");

    if (error) throw new ApiError(500, error.message, "DB_ERROR");

    res.json({
      users: (data ?? []).map((u) => ({
        id:                        u.id,
        email:                     u.email,
        role:                      u.role,
        firstName:                 u.first_name,
        lastName:                  u.last_name,
        isActive:                  u.is_active,
        welderCertificationNumber: u.welder_certification_number,
        certificationExpiry:       u.certification_expiry,
      })),
    });
  } catch (err) {
    sendError(res, err);
  }
}

export async function updateUser(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const body = UpdateUserBody.parse(req.body);

    const update: Record<string, unknown> = {};
    if (body.firstName                 !== undefined) update["first_name"]                  = body.firstName;
    if (body.lastName                  !== undefined) update["last_name"]                   = body.lastName;
    if (body.role                      !== undefined) update["role"]                        = body.role;
    if (body.isActive                  !== undefined) update["is_active"]                   = body.isActive;
    if (body.welderCertificationNumber !== undefined) update["welder_certification_number"] = body.welderCertificationNumber;
    if (body.certificationExpiry       !== undefined) update["certification_expiry"]        = body.certificationExpiry;

    if (Object.keys(update).length === 0) {
      throw new ApiError(400, "No fields to update", "EMPTY_UPDATE");
    }

    const { data, error } = await supabaseAdmin
      .from("users")
      .update(update)
      .eq("id", id)
      .select("id, email, role, first_name, last_name, is_active, welder_certification_number, certification_expiry")
      .single();

    if (error) throw new ApiError(500, error.message, "DB_ERROR");
    if (!data)  throw new ApiError(404, "User not found", "NOT_FOUND");

    res.json({
      user: {
        id:                        data.id,
        email:                     data.email,
        role:                      data.role,
        firstName:                 data.first_name,
        lastName:                  data.last_name,
        isActive:                  data.is_active,
        welderCertificationNumber: data.welder_certification_number,
        certificationExpiry:       data.certification_expiry,
      },
    });
  } catch (err) {
    sendError(res, err);
  }
}

export async function deleteUser(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;

    if (req.user?.id === id) {
      throw new ApiError(400, "You cannot delete your own account", "SELF_DELETE");
    }

    const { error } = await supabaseAdmin.auth.admin.deleteUser(id);
    if (error) throw new ApiError(500, error.message, "AUTH_DELETE_FAILED");

    res.status(204).send();
  } catch (err) {
    sendError(res, err);
  }
}
