import { Router, type IRouter } from "express";
import { requireAuth, requireRole } from "../middlewares/auth.js";
import * as authController from "../controllers/auth.controller.js";

const router: IRouter = Router();

router.post("/auth/login", authController.login);
router.post("/auth/register", requireAuth, requireRole("manager"), authController.register);
router.post("/auth/refresh", authController.refresh);
router.get("/auth/me", requireAuth, authController.me);
router.post("/auth/logout", requireAuth, authController.logout);

export default router;
