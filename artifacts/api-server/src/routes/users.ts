import { Router, type IRouter } from "express";
import { requireAuth, requireRole } from "../middlewares/auth.js";
import * as usersController from "../controllers/users.controller.js";

const router: IRouter = Router();

router.get("/users",        requireAuth, requireRole("manager"), usersController.listUsers);
router.put("/users/:id",    requireAuth, requireRole("manager"), usersController.updateUser);
router.delete("/users/:id", requireAuth, requireRole("manager"), usersController.deleteUser);

export default router;
