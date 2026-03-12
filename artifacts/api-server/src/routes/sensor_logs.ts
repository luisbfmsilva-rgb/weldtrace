import { Router, type IRouter } from "express";
import { requireAuth, requireRole } from "../middlewares/auth.js";
import * as sensorLogsController from "../controllers/sensor_logs.controller.js";

const router: IRouter = Router();

router.use(requireAuth);

// Top-level batch upload endpoint — used by the mobile Sync Service
// when uploading accumulated sensor logs after a completed weld phase.
// Payload: { weldId, records: [...] } — max 200 records per request.
router.post("/sensor-logs/batch", requireRole("manager", "supervisor", "welder"), sensorLogsController.batchUploadSensorLogs);

export default router;
