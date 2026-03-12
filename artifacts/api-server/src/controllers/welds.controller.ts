import { Response } from "express";
import { sendError, NotFoundError, ApiError } from "../lib/errors.js";
import {
  StartWeldBody,
  RecordStepBody,
  RecordErrorBody,
  CancelWeldBody,
  WeldsQuery,
} from "../lib/validation.js";
import type { AuthenticatedRequest } from "../middlewares/auth.js";

// ── List welds ────────────────────────────────────────────────────────────────

export async function listWelds(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const query = WeldsQuery.parse(req.query);

    let q = req.supabaseClient!
      .from("welds")
      .select(
        `
        id, weld_type, status, pipe_material, pipe_diameter, pipe_sdr,
        ambient_temperature, gps_lat, gps_lng, standard_used,
        is_cancelled, cancel_reason, started_at, completed_at, created_at,
        project:projects(id, name, location),
        machine:machines(id, serial_number, model),
        operator:users!welds_operator_id_fkey(id, first_name, last_name),
        standard:welding_standards(id, standard_code, weld_type, pipe_material)
      `,
        { count: "exact" },
      )
      .order("started_at", { ascending: false })
      .range(query.offset, query.offset + query.limit - 1);

    if (query.projectId) q = q.eq("project_id", query.projectId);
    if (query.status) q = q.eq("status", query.status);
    if (query.operatorId) q = q.eq("operator_id", query.operatorId);
    if (query.weldType) q = q.eq("weld_type", query.weldType);
    if (query.fromDate) q = q.gte("started_at", query.fromDate);
    if (query.toDate) q = q.lte("started_at", query.toDate);

    const { data, error, count } = await q;
    if (error) throw new ApiError(500, error.message, "DB_ERROR");

    res.json({ data: data ?? [], total: count ?? 0, limit: query.limit, offset: query.offset });
  } catch (err) {
    sendError(res, err);
  }
}

// ── Get single weld ───────────────────────────────────────────────────────────

export async function getWeld(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const { data, error } = await req.supabaseClient!
      .from("welds")
      .select(`
        *,
        project:projects(id, name, location, status),
        machine:machines(id, serial_number, model, manufacturer, type),
        operator:users!welds_operator_id_fkey(
          id, first_name, last_name, welder_certification_number, certification_expiry
        ),
        standard:welding_standards(id, standard_code, weld_type, pipe_material, version),
        weld_steps(
          id, phase_name, phase_order, started_at, completed_at,
          nominal_value, actual_value, unit, validation_passed, notes
        ),
        weld_photos(id, storage_path, photo_type, caption, taken_at),
        weld_errors(
          id, error_type, error_message, phase_name, parameter_name,
          actual_value, allowed_min, allowed_max, recorded_at
        )
      `)
      .eq("id", id)
      .single();

    if (error || !data) throw new NotFoundError("Weld");
    res.json(data);
  } catch (err) {
    sendError(res, err);
  }
}

// ── Start a new weld ──────────────────────────────────────────────────────────

export async function startWeld(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const body = StartWeldBody.parse(req.body);

    // Machine must be approved
    const { data: machine, error: machineError } = await req.supabaseClient!
      .from("machines")
      .select("id, is_approved, is_active, type")
      .eq("id", body.machineId)
      .single();

    if (machineError || !machine) throw new NotFoundError("Machine");
    if (!machine.is_active) {
      throw new ApiError(400, "Machine is deactivated and cannot be used for welding", "MACHINE_INACTIVE");
    }
    if (!machine.is_approved) {
      throw new ApiError(400, "Machine must be approved before use in welding operations", "MACHINE_NOT_APPROVED");
    }

    // Operator must be assigned to the project
    const { data: membership } = await req.supabaseClient!
      .from("project_users")
      .select("id")
      .eq("project_id", body.projectId)
      .eq("user_id", req.user!.id)
      .single();

    if (!membership) {
      throw new ApiError(403, "You are not assigned to this project", "NOT_ASSIGNED");
    }

    const { data, error } = await req.supabaseClient!
      .from("welds")
      .insert({
        project_id: body.projectId,
        machine_id: body.machineId,
        operator_id: req.user!.id,
        weld_type: body.weldType,
        pipe_material: body.pipeMaterial,
        pipe_diameter: body.pipeDiameter,
        pipe_sdr: body.pipeSdr ?? null,
        pipe_wall_thickness: body.pipeWallThickness ?? null,
        ambient_temperature: body.ambientTemperature ?? null,
        gps_lat: body.gpsLat ?? null,
        gps_lng: body.gpsLng ?? null,
        standard_used: body.standardUsed ?? null,
        standard_id: body.standardId ?? null,
        notes: body.notes ?? null,
        status: "in_progress",
      })
      .select(`
        *,
        project:projects(id, name),
        machine:machines(id, serial_number, model),
        operator:users!welds_operator_id_fkey(id, first_name, last_name),
        standard:welding_standards(id, standard_code, version)
      `)
      .single();

    if (error) throw new ApiError(500, error.message, "DB_ERROR");
    res.status(201).json(data);
  } catch (err) {
    sendError(res, err);
  }
}

// ── Record a phase step ───────────────────────────────────────────────────────

export async function recordStep(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const body = RecordStepBody.parse(req.body);

    // Verify weld is in progress
    const { data: weld } = await req.supabaseClient!
      .from("welds")
      .select("id, status, operator_id")
      .eq("id", id)
      .single();

    if (!weld) throw new NotFoundError("Weld");
    if (weld.status !== "in_progress") {
      throw new ApiError(400, `Cannot record a step on a weld with status '${weld.status}'`, "WELD_NOT_ACTIVE");
    }

    const { data, error } = await req.supabaseClient!
      .from("weld_steps")
      .insert({
        weld_id: id,
        phase_name: body.phaseName,
        phase_order: body.phaseOrder,
        started_at: body.startedAt ?? null,
        completed_at: body.completedAt ?? null,
        nominal_value: body.nominalValue ?? null,
        actual_value: body.actualValue ?? null,
        unit: body.unit ?? null,
        validation_passed: body.validationPassed ?? null,
        notes: body.notes ?? null,
      })
      .select()
      .single();

    if (error) throw new ApiError(500, error.message, "DB_ERROR");
    res.status(201).json(data);
  } catch (err) {
    sendError(res, err);
  }
}

// ── Record a parameter violation / error ──────────────────────────────────────

export async function recordError(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const body = RecordErrorBody.parse(req.body);

    const { data: weld } = await req.supabaseClient!
      .from("welds")
      .select("id, status")
      .eq("id", id)
      .single();

    if (!weld) throw new NotFoundError("Weld");
    if (weld.status !== "in_progress") {
      throw new ApiError(400, "Cannot record an error on a completed or cancelled weld", "WELD_NOT_ACTIVE");
    }

    const { data, error } = await req.supabaseClient!
      .from("weld_errors")
      .insert({
        weld_id: id,
        error_type: body.errorType,
        error_message: body.errorMessage,
        phase_name: body.phaseName ?? null,
        parameter_name: body.parameterName ?? null,
        actual_value: body.actualValue ?? null,
        allowed_min: body.allowedMin ?? null,
        allowed_max: body.allowedMax ?? null,
      })
      .select()
      .single();

    if (error) throw new ApiError(500, error.message, "DB_ERROR");
    res.status(201).json(data);
  } catch (err) {
    sendError(res, err);
  }
}

// ── Complete a weld ───────────────────────────────────────────────────────────

export async function completeWeld(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;

    const { data: weld } = await req.supabaseClient!
      .from("welds")
      .select("id, status, operator_id")
      .eq("id", id)
      .single();

    if (!weld) throw new NotFoundError("Weld");
    if (weld.status !== "in_progress") {
      throw new ApiError(400, `Weld cannot be completed — current status is '${weld.status}'`, "INVALID_STATUS");
    }

    // Check no unresolved validation failures
    const { data: errors } = await req.supabaseClient!
      .from("weld_errors")
      .select("id")
      .eq("weld_id", id)
      .limit(1);

    if (errors && errors.length > 0) {
      throw new ApiError(
        400,
        "Weld has recorded parameter violations. Review errors before completing.",
        "HAS_ERRORS",
      );
    }

    const { data, error } = await req.supabaseClient!
      .from("welds")
      .update({ status: "completed", completed_at: new Date().toISOString() })
      .eq("id", id)
      .eq("status", "in_progress")
      .select(`
        *,
        project:projects(id, name),
        machine:machines(id, serial_number, model),
        operator:users!welds_operator_id_fkey(id, first_name, last_name)
      `)
      .single();

    if (error || !data) throw new ApiError(500, "Failed to complete weld", "DB_ERROR");
    res.json(data);
  } catch (err) {
    sendError(res, err);
  }
}

// ── Cancel a weld ─────────────────────────────────────────────────────────────

export async function cancelWeld(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const { cancelReason } = CancelWeldBody.parse(req.body);

    const { data: weld } = await req.supabaseClient!
      .from("welds")
      .select("id, status")
      .eq("id", id)
      .single();

    if (!weld) throw new NotFoundError("Weld");
    if (weld.status !== "in_progress") {
      throw new ApiError(400, `Weld cannot be cancelled — current status is '${weld.status}'`, "INVALID_STATUS");
    }

    const { data, error } = await req.supabaseClient!
      .from("welds")
      .update({
        status: "cancelled",
        is_cancelled: true,
        cancel_reason: cancelReason,
        cancel_timestamp: new Date().toISOString(),
      })
      .eq("id", id)
      .eq("status", "in_progress")
      .select()
      .single();

    if (error || !data) throw new ApiError(500, "Failed to cancel weld", "DB_ERROR");
    res.json(data);
  } catch (err) {
    sendError(res, err);
  }
}
