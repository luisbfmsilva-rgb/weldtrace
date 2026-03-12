import { Router, type IRouter } from "express";
import { requireAuth, requireRole } from "../middlewares/auth.js";
import * as syncController from "../controllers/sync.controller.js";

const router: IRouter = Router();

router.use(requireAuth);

// Push pending local records to the cloud.
// Called by the Flutter Sync Service when connectivity is restored.
// Returns HTTP 207 (Multi-Status) if any entity had partial errors.
router.post("/sync/upload", requireRole("manager", "supervisor", "welder"), syncController.upload);

// Pull updates from the cloud since a given timestamp.
// Returns: projects, project_users, machines, sensor_calibrations,
//          welding_standards, welding_parameters
// Query params: since (required ISO timestamp), projectId (optional scope)
router.get("/sync/updates", syncController.getUpdates);

export default router;
