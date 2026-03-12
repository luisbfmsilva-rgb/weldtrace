import { Router, type IRouter } from "express";
import { requireAuth, requireRole, type AuthenticatedRequest } from "../middlewares/auth.js";

const router: IRouter = Router();

router.use(requireAuth);

router.get("/welds", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { projectId, status, limit = "50", offset = "0" } = req.query as Record<string, string>;

  let query = req.supabaseClient!
    .from("welds")
    .select(`
      *,
      project:projects(id, name),
      machine:machines(id, serial_number, model),
      operator:users!welds_operator_id_fkey(id, first_name, last_name),
      standard:welding_standards(id, standard_code, weld_type, pipe_material)
    `, { count: "exact" })
    .order("started_at", { ascending: false })
    .range(parseInt(offset), parseInt(offset) + parseInt(limit) - 1);

  if (projectId) query = query.eq("project_id", projectId);
  if (status) query = query.eq("status", status);

  const { data, error, count } = await query;

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.json({ data, total: count, limit: parseInt(limit), offset: parseInt(offset) });
});

router.get("/welds/:id", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;

  const { data, error } = await req.supabaseClient!
    .from("welds")
    .select(`
      *,
      project:projects(id, name, location),
      machine:machines(id, serial_number, model, manufacturer),
      operator:users!welds_operator_id_fkey(id, first_name, last_name, welder_certification_number),
      standard:welding_standards(id, standard_code, weld_type, pipe_material, version),
      weld_steps(id, phase_name, phase_order, started_at, completed_at, nominal_value, actual_value, unit, validation_passed, notes),
      weld_photos(id, storage_path, photo_type, caption, taken_at),
      weld_errors(id, error_type, error_message, phase_name, parameter_name, actual_value, allowed_min, allowed_max, recorded_at)
    `)
    .eq("id", id)
    .single();

  if (error || !data) {
    res.status(404).json({ error: "Weld not found" });
    return;
  }

  res.json(data);
});

router.post("/welds", requireRole("manager", "supervisor", "welder"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const {
    projectId, machineId, weldType, pipeMaterial, pipeDiameter,
    pipeSdr, pipeWallThickness, ambientTemperature, gpsLat, gpsLng,
    standardUsed, standardId, notes
  } = req.body;

  if (!projectId || !machineId || !weldType || !pipeMaterial || !pipeDiameter) {
    res.status(400).json({ error: "projectId, machineId, weldType, pipeMaterial, and pipeDiameter are required" });
    return;
  }

  const { data: machine } = await req.supabaseClient!
    .from("machines")
    .select("is_approved")
    .eq("id", machineId)
    .single();

  if (!machine?.is_approved) {
    res.status(400).json({ error: "Machine must be approved before use in welding operations" });
    return;
  }

  const { data, error } = await req.supabaseClient!
    .from("welds")
    .insert({
      project_id: projectId,
      machine_id: machineId,
      operator_id: req.user!.id,
      weld_type: weldType,
      pipe_material: pipeMaterial,
      pipe_diameter: pipeDiameter,
      pipe_sdr: pipeSdr,
      pipe_wall_thickness: pipeWallThickness,
      ambient_temperature: ambientTemperature,
      gps_lat: gpsLat,
      gps_lng: gpsLng,
      standard_used: standardUsed,
      standard_id: standardId,
      notes,
      status: "in_progress",
    })
    .select()
    .single();

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.status(201).json(data);
});

router.patch("/welds/:id/complete", requireRole("manager", "supervisor", "welder"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;

  const { data: weld } = await req.supabaseClient!
    .from("welds")
    .select("status, operator_id")
    .eq("id", id)
    .single();

  if (!weld) {
    res.status(404).json({ error: "Weld not found" });
    return;
  }

  if (weld.status !== "in_progress") {
    res.status(400).json({ error: "Only in-progress welds can be completed" });
    return;
  }

  const { data, error } = await req.supabaseClient!
    .from("welds")
    .update({ status: "completed", completed_at: new Date().toISOString() })
    .eq("id", id)
    .eq("status", "in_progress")
    .select()
    .single();

  if (error || !data) {
    res.status(500).json({ error: "Failed to complete weld" });
    return;
  }

  res.json(data);
});

router.patch("/welds/:id/cancel", requireRole("manager", "supervisor", "welder"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;
  const { cancelReason } = req.body;

  if (!cancelReason) {
    res.status(400).json({ error: "cancelReason is required" });
    return;
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

  if (error || !data) {
    res.status(400).json({ error: "Weld not found or already completed/cancelled" });
    return;
  }

  res.json(data);
});

router.post("/welds/:id/steps", requireRole("manager", "supervisor", "welder"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;
  const { phaseName, phaseOrder, startedAt, completedAt, nominalValue, actualValue, unit, validationPassed, notes } = req.body;

  if (!phaseName || phaseOrder === undefined) {
    res.status(400).json({ error: "phaseName and phaseOrder are required" });
    return;
  }

  const { data, error } = await req.supabaseClient!
    .from("weld_steps")
    .insert({
      weld_id: id,
      phase_name: phaseName,
      phase_order: phaseOrder,
      started_at: startedAt,
      completed_at: completedAt,
      nominal_value: nominalValue,
      actual_value: actualValue,
      unit,
      validation_passed: validationPassed,
      notes,
    })
    .select()
    .single();

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.status(201).json(data);
});

router.post("/welds/:id/errors", requireRole("manager", "supervisor", "welder"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;
  const { errorType, errorMessage, phaseName, parameterName, actualValue, allowedMin, allowedMax } = req.body;

  if (!errorType || !errorMessage) {
    res.status(400).json({ error: "errorType and errorMessage are required" });
    return;
  }

  const { data, error } = await req.supabaseClient!
    .from("weld_errors")
    .insert({
      weld_id: id,
      error_type: errorType,
      error_message: errorMessage,
      phase_name: phaseName,
      parameter_name: parameterName,
      actual_value: actualValue,
      allowed_min: allowedMin,
      allowed_max: allowedMax,
    })
    .select()
    .single();

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.status(201).json(data);
});

export default router;
