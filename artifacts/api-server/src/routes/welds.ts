import { Router, type IRouter } from "express";
import { requireAuth, requireRole } from "../middlewares/auth.js";
import * as weldsController from "../controllers/welds.controller.js";
import * as sensorLogsController from "../controllers/sensor_logs.controller.js";

const router: IRouter = Router();

router.use(requireAuth);

// Weld lifecycle
router.get("/welds", weldsController.listWelds);
router.post("/welds/start", requireRole("manager", "supervisor", "welder"), weldsController.startWeld);
router.get("/welds/:id", weldsController.getWeld);
router.post("/welds/:id/step", requireRole("manager", "supervisor", "welder"), weldsController.recordStep);
router.post("/welds/:id/error", requireRole("manager", "supervisor", "welder"), weldsController.recordError);
router.post("/welds/:id/complete", requireRole("manager", "supervisor", "welder"), weldsController.completeWeld);
router.post("/welds/:id/cancel", requireRole("manager", "supervisor", "welder"), weldsController.cancelWeld);

// Sensor logs scoped to a weld
router.post("/welds/:weldId/sensor-logs/batch", requireRole("manager", "supervisor", "welder"), sensorLogsController.batchUploadSensorLogs);
router.get("/welds/:weldId/sensor-logs", sensorLogsController.getSensorLogs);

export default router;
