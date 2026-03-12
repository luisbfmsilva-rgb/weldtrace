import { Router, type IRouter } from "express";
import { requireAuth, requireRole } from "../middlewares/auth.js";
import * as machinesController from "../controllers/machines.controller.js";

const router: IRouter = Router();

router.use(requireAuth);

router.get("/machines", machinesController.listMachines);
router.post("/machines", requireRole("manager", "supervisor"), machinesController.createMachine);
router.get("/machines/:id", machinesController.getMachine);
router.patch("/machines/:id", requireRole("manager", "supervisor"), machinesController.updateMachine);
router.patch("/machines/:id/approve", requireRole("manager", "supervisor"), machinesController.approveMachine);

router.post("/machines/:id/maintenance", requireRole("manager", "supervisor"), machinesController.createMaintenance);
router.post("/machines/:id/calibrations", requireRole("manager", "supervisor"), machinesController.createCalibration);
router.get("/machines/:id/calibrations", machinesController.listCalibrations);

export default router;
