import { Router, type IRouter } from "express";
import { requireAuth, type AuthenticatedRequest } from "../middlewares/auth.js";
import { sendError, ApiError } from "../lib/errors.js";
import { WeldingStandardsQuery, WeldingParametersQuery } from "../lib/validation.js";

const router: IRouter = Router();

router.use(requireAuth);

router.get("/welding-standards", async (req: AuthenticatedRequest, res): Promise<void> => {
  try {
    const query = WeldingStandardsQuery.parse(req.query);

    let q = req.supabaseClient!
      .from("welding_standards")
      .select("id, standard_code, weld_type, pipe_material, version, description, is_active, created_at")
      .eq("is_active", true)
      .order("standard_code");

    if (query.weldType) q = q.eq("weld_type", query.weldType);
    if (query.pipeMaterial) q = q.ilike("pipe_material", query.pipeMaterial);
    if (query.standardCode) q = q.eq("standard_code", query.standardCode);

    const { data, error } = await q;
    if (error) throw new ApiError(500, error.message, "DB_ERROR");

    res.json(data ?? []);
  } catch (err) {
    sendError(res, err);
  }
});

router.get("/welding-standards/:id/parameters", async (req: AuthenticatedRequest, res): Promise<void> => {
  try {
    const { id } = req.params;
    const query = WeldingParametersQuery.parse(req.query);

    // Verify the standard exists
    const { data: standard } = await req.supabaseClient!
      .from("welding_standards")
      .select("id, standard_code, weld_type, pipe_material, version")
      .eq("id", id)
      .single();

    if (!standard) {
      res.status(404).json({ error: "Welding standard not found", code: "NOT_FOUND" });
      return;
    }

    let q = req.supabaseClient!
      .from("welding_parameters")
      .select("*")
      .eq("standard_id", id)
      .order("phase_order");

    if (query.phaseName) q = q.eq("phase_name", query.phaseName);
    if (query.pipeSdr) q = q.eq("pipe_sdr", query.pipeSdr);
    if (query.pipeDiameter !== undefined) {
      q = q
        .lte("pipe_diameter_min", query.pipeDiameter)
        .gte("pipe_diameter_max", query.pipeDiameter);
    }

    const { data, error } = await q;
    if (error) throw new ApiError(500, error.message, "DB_ERROR");

    res.json({
      standard,
      parameters: data ?? [],
    });
  } catch (err) {
    sendError(res, err);
  }
});

export default router;
