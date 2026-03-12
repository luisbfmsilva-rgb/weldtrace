import { Router, type IRouter } from "express";
import { requireAuth, requireRole } from "../middlewares/auth.js";
import * as projectsController from "../controllers/projects.controller.js";

const router: IRouter = Router();

router.use(requireAuth);

router.get("/projects", projectsController.listProjects);
router.post("/projects", requireRole("manager", "supervisor"), projectsController.createProject);
router.get("/projects/:id", projectsController.getProject);
router.patch("/projects/:id", requireRole("manager", "supervisor"), projectsController.updateProject);

router.post("/projects/:id/users", requireRole("manager", "supervisor"), projectsController.assignUser);
router.delete("/projects/:id/users/:userId", requireRole("manager", "supervisor"), projectsController.removeUser);

router.post("/projects/:id/machines", requireRole("manager", "supervisor"), projectsController.assignMachine);
router.delete("/projects/:id/machines/:machineId", requireRole("manager", "supervisor"), projectsController.removeMachine);

export default router;
