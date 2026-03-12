import { Router, type IRouter } from "express";
import { requireAuth, type AuthenticatedRequest } from "../middlewares/auth.js";

const router: IRouter = Router();

router.use(requireAuth);

router.get("/welding-standards", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { weldType, pipeMaterial, standardCode } = req.query as Record<string, string>;

  let query = req.supabaseClient!
    .from("welding_standards")
    .select("*")
    .eq("is_active", true)
    .order("standard_code");

  if (weldType) query = query.eq("weld_type", weldType);
  if (pipeMaterial) query = query.ilike("pipe_material", pipeMaterial);
  if (standardCode) query = query.eq("standard_code", standardCode);

  const { data, error } = await query;

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.json(data);
});

router.get("/welding-standards/:id/parameters", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;
  const { phaseName, pipeDiameter, pipeSdr } = req.query as Record<string, string>;

  let query = req.supabaseClient!
    .from("welding_parameters")
    .select("*")
    .eq("standard_id", id)
    .order("phase_order");

  if (phaseName) query = query.eq("phase_name", phaseName);

  if (pipeDiameter) {
    const diam = parseFloat(pipeDiameter);
    query = query
      .lte("pipe_diameter_min", diam)
      .gte("pipe_diameter_max", diam);
  }

  if (pipeSdr) query = query.eq("pipe_sdr", pipeSdr);

  const { data, error } = await query;

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.json(data);
});

export default router;
