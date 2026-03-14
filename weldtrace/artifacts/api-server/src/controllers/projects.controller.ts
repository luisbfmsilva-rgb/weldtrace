import { Response } from "express";
import { sendError, NotFoundError, ApiError } from "../lib/errors.js";
import {
  CreateProjectBody,
  UpdateProjectBody,
  AssignUserBody,
  AssignMachineBody,
  ProjectsQuery,
} from "../lib/validation.js";
import type { AuthenticatedRequest } from "../middlewares/auth.js";

export async function listProjects(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const query = ProjectsQuery.parse(req.query);

    let q = req.supabaseClient!
      .from("projects")
      .select(
        `
        id, name, description, location, status, gps_lat, gps_lng,
        start_date, end_date, client_name, contract_number,
        created_at, updated_at,
        company:companies(id, name),
        created_by_user:users!projects_created_by_fkey(id, first_name, last_name)
      `,
        { count: "exact" },
      )
      .order("created_at", { ascending: false })
      .range(query.offset, query.offset + query.limit - 1);

    if (query.status) q = q.eq("status", query.status);

    const { data, error, count } = await q;
    if (error) throw new ApiError(500, error.message, "DB_ERROR");

    res.json({ data: data ?? [], total: count ?? 0, limit: query.limit, offset: query.offset });
  } catch (err) {
    sendError(res, err);
  }
}

export async function getProject(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const { data, error } = await req.supabaseClient!
      .from("projects")
      .select(`
        id, name, description, location, status, gps_lat, gps_lng,
        start_date, end_date, client_name, contract_number, created_at, updated_at,
        company:companies(id, name),
        project_users(
          id, role_in_project, assigned_at,
          user:users(id, first_name, last_name, role, email, welder_certification_number)
        ),
        project_machines(
          id, assigned_at,
          machine:machines(
            id, serial_number, model, manufacturer, type, is_approved,
            last_calibration_date, next_calibration_date
          )
        )
      `)
      .eq("id", id)
      .single();

    if (error || !data) throw new NotFoundError("Project");
    res.json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function createProject(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const body = CreateProjectBody.parse(req.body);

    const { data, error } = await req.supabaseClient!
      .from("projects")
      .insert({
        name: body.name,
        description: body.description ?? null,
        location: body.location ?? null,
        gps_lat: body.gpsLat ?? null,
        gps_lng: body.gpsLng ?? null,
        start_date: body.startDate ?? null,
        end_date: body.endDate ?? null,
        client_name: body.clientName ?? null,
        contract_number: body.contractNumber ?? null,
        company_id: req.user!.companyId,
        created_by: req.user!.id,
      })
      .select()
      .single();

    if (error) throw new ApiError(500, error.message, "DB_ERROR");
    res.status(201).json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function updateProject(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const body = UpdateProjectBody.parse(req.body);

    const patch: Record<string, unknown> = {};
    if (body.name !== undefined) patch["name"] = body.name;
    if (body.description !== undefined) patch["description"] = body.description;
    if (body.location !== undefined) patch["location"] = body.location;
    if (body.status !== undefined) patch["status"] = body.status;
    if (body.startDate !== undefined) patch["start_date"] = body.startDate;
    if (body.endDate !== undefined) patch["end_date"] = body.endDate;
    if (body.clientName !== undefined) patch["client_name"] = body.clientName;
    if (body.contractNumber !== undefined) patch["contract_number"] = body.contractNumber;
    if (body.gpsLat !== undefined) patch["gps_lat"] = body.gpsLat;
    if (body.gpsLng !== undefined) patch["gps_lng"] = body.gpsLng;

    if (Object.keys(patch).length === 0) {
      throw new ApiError(400, "No fields to update", "VALIDATION_ERROR");
    }

    const { data, error } = await req.supabaseClient!
      .from("projects")
      .update(patch)
      .eq("id", id)
      .select()
      .single();

    if (error || !data) throw new NotFoundError("Project");
    res.json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function assignUser(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const body = AssignUserBody.parse(req.body);

    const { data, error } = await req.supabaseClient!
      .from("project_users")
      .insert({
        project_id: id,
        user_id: body.userId,
        role_in_project: body.roleInProject,
        assigned_by: req.user!.id,
      })
      .select(`
        id, role_in_project, assigned_at,
        user:users(id, first_name, last_name, email, role)
      `)
      .single();

    if (error) {
      if ((error as unknown as { code: string }).code === "23505") {
        throw new ApiError(409, "User is already assigned to this project", "CONFLICT");
      }
      throw new ApiError(500, error.message, "DB_ERROR");
    }

    res.status(201).json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function removeUser(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id, userId } = req.params;
    const { error } = await req.supabaseClient!
      .from("project_users")
      .delete()
      .eq("project_id", id)
      .eq("user_id", userId);

    if (error) throw new ApiError(500, error.message, "DB_ERROR");
    res.sendStatus(204);
  } catch (err) {
    sendError(res, err);
  }
}

export async function assignMachine(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const body = AssignMachineBody.parse(req.body);

    const { data: machine } = await req.supabaseClient!
      .from("machines")
      .select("id, is_approved")
      .eq("id", body.machineId)
      .single();

    if (!machine) throw new NotFoundError("Machine");
    if (!machine.is_approved) {
      throw new ApiError(400, "Machine must be approved before assignment to a project", "MACHINE_NOT_APPROVED");
    }

    const { data, error } = await req.supabaseClient!
      .from("project_machines")
      .insert({
        project_id: id,
        machine_id: body.machineId,
        assigned_by: req.user!.id,
      })
      .select(`
        id, assigned_at,
        machine:machines(id, serial_number, model, manufacturer, type)
      `)
      .single();

    if (error) {
      if ((error as unknown as { code: string }).code === "23505") {
        throw new ApiError(409, "Machine is already assigned to this project", "CONFLICT");
      }
      throw new ApiError(500, error.message, "DB_ERROR");
    }

    res.status(201).json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function removeMachine(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id, machineId } = req.params;
    const { error } = await req.supabaseClient!
      .from("project_machines")
      .delete()
      .eq("project_id", id)
      .eq("machine_id", machineId);

    if (error) throw new ApiError(500, error.message, "DB_ERROR");
    res.sendStatus(204);
  } catch (err) {
    sendError(res, err);
  }
}
