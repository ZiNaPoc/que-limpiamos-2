import { Router } from "express";

import { clienteAuthRouter } from "./auth/routes";
import { clienteInmueblesRouter } from "./inmuebles/routes";
import { clienteNotificacionesRouter } from "./notificaciones/routes";
import { clienteReportesRouter } from "./reportes/routes";
import { clienteResenasRouter } from "./resenas/routes";
import { clienteSolicitudesRouter } from "./solicitudes/routes";

/**
 * Audiencia CLIENTE, montada en /api/cliente. Autenticación con `Authorization: Bearer`.
 * No importa nada de modules/trabajador ni de modules/admin.
 */
export const clienteRouter = Router();

clienteRouter.use("/auth", clienteAuthRouter);
// Fase 3a: reseñas y reportes (cada ruta exige el token de cliente).
clienteRouter.use(clienteResenasRouter);
clienteRouter.use(clienteReportesRouter);
// Fase 3b: historial y selección manual; doc 25: ciclo de las solicitudes sin dinero.
clienteRouter.use(clienteSolicitudesRouter);
// Doc 25: «Mis inmuebles» y avisos.
clienteRouter.use(clienteInmueblesRouter);
clienteRouter.use(clienteNotificacionesRouter);
