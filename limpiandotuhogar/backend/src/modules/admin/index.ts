import cookieParser from "cookie-parser";
import { Router } from "express";

import { exigirOrigenPermitido } from "./auth/origen";
import { adminAuthRouter } from "./auth/routes";
import { moderacionRouter } from "./moderacion/routes";
import { permisosRouter } from "./permisos/routes";
import { solicitudesAdminRouter } from "./solicitudes/routes";

/**
 * Audiencia ADMIN, montada en /api/admin. Sesión en cookie httpOnly (no Bearer) y comprobación
 * de Origin en todo lo que cambia datos. Las rutas de negocio (Fase 5) irán detrás de requireAdmin.
 * No importa nada de modules/cliente ni de modules/trabajador.
 */
export const adminRouter = Router();

adminRouter.use(cookieParser());
adminRouter.use(exigirOrigenPermitido);
adminRouter.use("/auth", adminAuthRouter);
// Fase 3a: permisos (propietario) y moderación (MODERAR_CONTENIDO), con requireAdmin por ruta.
adminRouter.use("/permisos", permisosRouter);
adminRouter.use(moderacionRouter);
// Doc 25: supervisión de solicitudes (SUPERVISAR_SOLICITUDES) y resolución del servicio (incidencias).
adminRouter.use(solicitudesAdminRouter);
