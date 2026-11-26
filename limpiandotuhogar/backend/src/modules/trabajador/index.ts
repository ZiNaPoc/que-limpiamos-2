import { Router } from "express";

import { trabajadorAuthRouter } from "./auth/routes";
import { trabajadorReportesRouter } from "./reportes/routes";
import { trabajadorResenasRouter } from "./resenas/routes";
import { trabajadorSolicitudesRouter } from "./solicitudes/routes";

/**
 * Audiencia TRABAJADOR, montada en /api/trabajador. Autenticación con `Authorization: Bearer`.
 * No importa nada de modules/cliente ni de modules/admin.
 */
export const trabajadorRouter = Router();

trabajadorRouter.use("/auth", trabajadorAuthRouter);
// Fase 3a: reseñas y reportes (cada ruta exige el token de trabajador).
trabajadorRouter.use(trabajadorResenasRouter);
trabajadorRouter.use(trabajadorReportesRouter);
// Fase 3b: historial e invitaciones; doc 25: ciclo de las solicitudes sin dinero y avisos.
trabajadorRouter.use(trabajadorSolicitudesRouter);
