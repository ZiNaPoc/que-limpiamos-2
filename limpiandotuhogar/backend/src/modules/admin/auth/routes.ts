import cookieParser from "cookie-parser";
import { Router } from "express";

import { authConfig } from "../../../config/auth";
import { limitePorIp } from "../../../shared/http/limites";

import { login, logout, sesion } from "./controller";
import { requireAdmin } from "./guard";
import { exigirOrigenPermitido } from "./origen";

/**
 * /api/admin/auth y su alias /api/auth/admin (D7: el panel usa hoy el alias; se quita
 * cuando el panel se actualice). Lleva su propio cookieParser y la comprobación de Origin,
 * para que el alias tenga las mismas protecciones.
 */
export const adminAuthRouter = Router();

adminAuthRouter.use(cookieParser());
adminAuthRouter.use(exigirOrigenPermitido);

adminAuthRouter.post("/login", limitePorIp(authConfig.limites.loginPorIp), login);
adminAuthRouter.get("/session", requireAdmin, sesion);
adminAuthRouter.get("/me", requireAdmin, sesion);
adminAuthRouter.post("/logout", logout);
