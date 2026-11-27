import { Router } from "express";

import { authConfig } from "../../../config/auth";
import { limitePorIp } from "../../../shared/http/limites";

import { cambiarPassword, login, logout, registro, yo } from "./controller";
import { requireTrabajador } from "./guard";

/** /api/trabajador/auth */
export const trabajadorAuthRouter = Router();

trabajadorAuthRouter.post("/registro", limitePorIp(authConfig.limites.registroPorIp), registro);
trabajadorAuthRouter.post("/login", limitePorIp(authConfig.limites.loginPorIp), login);
trabajadorAuthRouter.get("/me", requireTrabajador, yo);
trabajadorAuthRouter.post("/logout", requireTrabajador, logout);
trabajadorAuthRouter.post("/cambiar-password", limitePorIp(authConfig.limites.passwordPorIp), requireTrabajador, cambiarPassword);
