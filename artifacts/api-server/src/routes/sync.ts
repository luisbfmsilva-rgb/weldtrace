import { Router, type IRouter } from "express";
import { requireAuth, requireRole, type AuthenticatedRequest } from "../middlewares/auth.js";

const router: IRouter = Router();

router.use(requireAuth);

// Sync endpoint: mobile app calls this to push pending records and
// receive any updates since its last sync timestamp.
// Architecture note: designed to support offline-first mobile workflow.
router.post("/sync/upload", requireRole("manager", "supervisor", "welder"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const {
    welds = [],
    weldSteps = [],
    weldErrors = [],
    sensorLogBatches = [],
  } = req.body as {
    welds?: Array<Record<string, unknown>>;
    weldSteps?: Array<Record<string, unknown>>;
    weldErrors?: Array<Record<string, unknown>>;
    sensorLogBatches?: Array<{ weldId: string; logs: Array<Record<string, unknown>> }>;
  };

  const results: Record<string, { inserted: number; errors: string[] }> = {
    welds: { inserted: 0, errors: [] },
    weldSteps: { inserted: 0, errors: [] },
    weldErrors: { inserted: 0, errors: [] },
    sensorLogs: { inserted: 0, errors: [] },
  };

  // Upload welds
  if (welds.length > 0) {
    const { data, error } = await req.supabaseClient!
      .from("welds")
      .upsert(welds, { onConflict: "id", ignoreDuplicates: false })
      .select("id");
    results.welds.inserted = data?.length ?? 0;
    if (error) results.welds.errors.push(error.message);
  }

  // Upload weld steps
  if (weldSteps.length > 0) {
    const { data, error } = await req.supabaseClient!
      .from("weld_steps")
      .upsert(weldSteps, { onConflict: "id", ignoreDuplicates: false })
      .select("id");
    results.weldSteps.inserted = data?.length ?? 0;
    if (error) results.weldSteps.errors.push(error.message);
  }

  // Upload weld errors
  if (weldErrors.length > 0) {
    const { data, error } = await req.supabaseClient!
      .from("weld_errors")
      .upsert(weldErrors, { onConflict: "id", ignoreDuplicates: false })
      .select("id");
    results.weldErrors.inserted = data?.length ?? 0;
    if (error) results.weldErrors.errors.push(error.message);
  }

  // Upload sensor log batches (100–200 records per sub-batch)
  for (const batch of sensorLogBatches) {
    const records = batch.logs.map(log => ({
      ...log,
      weld_id: batch.weldId,
    }));

    if (records.length > 500) {
      results.sensorLogs.errors.push(`Batch for weld ${batch.weldId} exceeds 500 records`);
      continue;
    }

    const { data, error } = await req.supabaseClient!
      .from("sensor_logs")
      .insert(records)
      .select("id");
    results.sensorLogs.inserted += data?.length ?? 0;
    if (error) results.sensorLogs.errors.push(error.message);
  }

  res.json({ results, syncedAt: new Date().toISOString() });
});

// Download updates since last sync
router.get("/sync/download", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { since, projectId } = req.query as Record<string, string>;

  if (!since) {
    res.status(400).json({ error: "since (ISO timestamp) is required" });
    return;
  }

  const sinceDate = new Date(since);
  if (isNaN(sinceDate.getTime())) {
    res.status(400).json({ error: "Invalid since timestamp" });
    return;
  }

  let projectsQuery = req.supabaseClient!
    .from("projects")
    .select("*")
    .gt("updated_at", since);

  if (projectId) projectsQuery = projectsQuery.eq("id", projectId);

  const [projectsResult, machinesResult, standardsResult] = await Promise.all([
    projectsQuery,
    req.supabaseClient!
      .from("machines")
      .select("*")
      .gt("updated_at", since),
    req.supabaseClient!
      .from("welding_standards")
      .select("*, welding_parameters(*)")
      .eq("is_active", true),
  ]);

  res.json({
    projects: projectsResult.data ?? [],
    machines: machinesResult.data ?? [],
    weldingStandards: standardsResult.data ?? [],
    downloadedAt: new Date().toISOString(),
  });
});

export default router;
