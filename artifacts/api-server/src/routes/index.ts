import { Router, type IRouter } from "express";
import healthRouter from "./health.js";
import authRouter from "./auth.js";
import projectsRouter from "./projects.js";
import machinesRouter from "./machines.js";
import weldsRouter from "./welds.js";
import sensorLogsRouter from "./sensor_logs.js";
import standardsRouter from "./standards.js";
import syncRouter from "./sync.js";
import usersRouter from "./users.js";

const router: IRouter = Router();

router.use(healthRouter);
router.use(authRouter);
router.use(usersRouter);
router.use(projectsRouter);
router.use(machinesRouter);
router.use(weldsRouter);
router.use(sensorLogsRouter);
router.use(standardsRouter);
router.use(syncRouter);

export default router;
