import { Response } from "express";
import { sendError, NotFoundError, ApiError } from "../lib/errors.js";
import { SensorLogBatchBody, SensorLogsQuery } from "../lib/validation.js";
import type { AuthenticatedRequest } from "../middlewares/auth.js";

// ── Batch upload sensor logs ───────────────────────────────────────────────────
// Sensor data is recorded at 1 Hz on the mobile device during active welding.
// The Sync Service batches up to 200 records per HTTP request.
// Logs are immutable once inserted — no UPDATE/DELETE policies exist in RLS.

export async function batchUploadSensorLogs(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const body = SensorLogBatchBody.parse(req.body);
    const { weldId, records } = body;

    // Verify weld exists and is in progress
    const { data: weld, error: weldError } = await req.supabaseClient!
      .from("welds")
      .select("id, status, project_id")
      .eq("id", weldId)
      .single();

    if (weldError || !weld) throw new NotFoundError("Weld");

    if (weld.status !== "in_progress") {
      throw new ApiError(
        400,
        `Sensor logs can only be uploaded for in-progress welds (current status: '${weld.status}')`,
        "WELD_NOT_ACTIVE",
      );
    }

    const dbRecords = records.map((r) => ({
      weld_id: weldId,
      weld_step_id: r.weldStepId ?? null,
      recorded_at: r.recordedAt,
      pressure_bar: r.pressureBar ?? null,
      temperature_celsius: r.temperatureCelsius ?? null,
      phase_name: r.phaseName ?? null,
    }));

    const { data, error } = await req.supabaseClient!
      .from("sensor_logs")
      .insert(dbRecords)
      .select("id, recorded_at, pressure_bar, temperature_celsius, phase_name");

    if (error) throw new ApiError(500, error.message, "DB_ERROR");

    res.status(201).json({
      inserted: data?.length ?? 0,
      weldId,
      batchSize: records.length,
    });
  } catch (err) {
    sendError(res, err);
  }
}

// ── Retrieve sensor logs for a weld ───────────────────────────────────────────
// Returns the full time-series dataset used for pressure vs time graph rendering.
// The Fusion Cloud dashboard uses this to draw nominal + actual curves.

export async function getSensorLogs(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { weldId } = req.params;
    const query = SensorLogsQuery.parse(req.query);

    // Verify weld exists and user can access it
    const { data: weld } = await req.supabaseClient!
      .from("welds")
      .select("id, status, started_at, completed_at")
      .eq("id", weldId)
      .single();

    if (!weld) throw new NotFoundError("Weld");

    let q = req.supabaseClient!
      .from("sensor_logs")
      .select("id, recorded_at, pressure_bar, temperature_celsius, phase_name, weld_step_id")
      .eq("weld_id", weldId)
      .order("recorded_at", { ascending: true })
      .limit(query.limit);

    if (query.phaseName) q = q.eq("phase_name", query.phaseName);

    const { data, error } = await q;
    if (error) throw new ApiError(500, error.message, "DB_ERROR");

    res.json({
      weldId,
      weldStatus: weld.status,
      startedAt: weld.started_at,
      completedAt: weld.completed_at,
      totalRecords: data?.length ?? 0,
      records: data ?? [],
    });
  } catch (err) {
    sendError(res, err);
  }
}
