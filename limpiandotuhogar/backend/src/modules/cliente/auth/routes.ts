import { Router } from "express";

import { authConfig } from "../../../config/auth";
import { limitePorIp } from "../../../shared/http/limites";

import { cambiarPassword, login, logout, registro, yo } from "./controller";
import { requireCliente } from "./guard";

/** /api/cliente/auth */
export const clienteAuthRouter = Router();

clienteAuthRouter.post("/registro", limitePorIp(authConfig.limites.registroPorIp), registro);
clienteAuthRouter.post("/login", limitePorIp(authConfig.limites.loginPorIp), login);
clienteAuthRouter.get("/me", requireCliente, yo);
clienteAuthRouter.post("/logout", requireCliente, logout);
clienteAuthRouter.post("/cambiar-password", limitePorIp(authConfig.limites.passwordPorIp), requireCliente, cambiarPassword);
