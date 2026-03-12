import { Router, type IRouter } from "express";
import { requireAuth, requireRole, type AuthenticatedRequest } from "../middlewares/auth.js";

const router: IRouter = Router();

router.use(requireAuth);

// Batch upload sensor logs (100–200 records per request)
// Architecture note: sensor data is captured at 1 Hz during welding.
// The mobile Sync Service batches and uploads logs after each phase or
// at completion to avoid excessive network traffic during active welding.
router.post("/welds/:weldId/sensor-logs/batch", requireRole("manager", "supervisor", "welder"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { weldId } = req.params;
  const { logs } = req.body as { logs: Array<{
    recordedAt: string;
    pressureBar?: number;
    temperatureCelsius?: number;
    phaseName?: string;
    weldStepId?: string;
  }> };

  if (!Array.isArray(logs) || logs.length === 0) {
    res.status(400).json({ error: "logs must be a non-empty array" });
    return;
  }

  if (logs.length > 500) {
    res.status(400).json({ error: "Maximum 500 records per batch. Split into smaller batches." });
    return;
  }

  const { data: weld } = await req.supabaseClient!
    .from("welds")
    .select("status")
    .eq("id", weldId)
    .single();

  if (!weld) {
    res.status(404).json({ error: "Weld not found" });
    return;
  }

  if (weld.status !== "in_progress") {
    res.status(400).json({ error: "Sensor logs can only be added to in-progress welds" });
    return;
  }

  const records = logs.map(log => ({
    weld_id: weldId,
    weld_step_id: log.weldStepId ?? null,
    recorded_at: log.recordedAt,
    pressure_bar: log.pressureBar ?? null,
    temperature_celsius: log.temperatureCelsius ?? null,
    phase_name: log.phaseName ?? null,
  }));

  const { data, error } = await req.supabaseClient!
    .from("sensor_logs")
    .insert(records)
    .select("id, recorded_at, pressure_bar, temperature_celsius, phase_name");

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.status(201).json({
    inserted: data?.length ?? 0,
    weldId,
  });
});

// Retrieve sensor logs for a weld (for graph rendering)
router.get("/welds/:weldId/sensor-logs", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { weldId } = req.params;
  const { phaseName, limit = "3600" } = req.query as Record<string, string>;

  let query = req.supabaseClient!
    .from("sensor_logs")
    .select("id, recorded_at, pressure_bar, temperature_celsius, phase_name, weld_step_id")
    .eq("weld_id", weldId)
    .order("recorded_at", { ascending: true })
    .limit(parseInt(limit));

  if (phaseName) query = query.eq("phase_name", phaseName);

  const { data, error } = await query;

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.json(data);
});

export default router;
