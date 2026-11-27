import { Router, type RequestHandler } from "express";

import { prisma } from "../../../config/prisma";
import { GESTIONAR_INCIDENCIAS_FINANZAS, puedeSupervisar } from "../../../dominio/permisos";
import { resolverServicio } from "../../../dominio/resoluciones";
import { detalleParaSupervision, leerFiltros, listarParaSupervision, urlFotoParaSupervision } from "../../../dominio/supervision";
import { AppError } from "../../../shared/errors/AppError";
import { idDeRuta } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { adminActual, requireAdmin } from "../auth/guard";
import { requierePermiso } from "../moderacion/routes";

export const solicitudesAdminRouter = Router();

/** Ver solicitudes: SUPERVISAR_SOLICITUDES vigente o el propietario (implícito). */
const requiereSupervision: RequestHandler = async (_req, res, next) => {
  if (!(await puedeSupervisar(prisma, adminActual(res).id))) throw new AppError(403, "No tienes permiso para ver las solicitudes", "PERMISO_REQUERIDO");
  next();
};

const supervisar = [requireAdmin, requiereSupervision];

solicitudesAdminRouter.get("/solicitudes", ...supervisar, async (req, res) => {
  res.json(await listarParaSupervision(leerFiltros(req.query as Record<string, unknown>)));
});

solicitudesAdminRouter.get("/solicitudes/:id", ...supervisar, async (req, res) => {
  res.json({ solicitud: await detalleParaSupervision(adminActual(res).id, idDeRuta(req)) });
});

solicitudesAdminRouter.get("/solicitudes/:id/evidencias/:evidenciaId", ...supervisar, async (req, res) => {
  res.json(await urlFotoParaSupervision(adminActual(res).id, idDeRuta(req), idDeRuta(req, "evidenciaId")));
});

// El permiso se vuelve a exigir (bloqueado) dentro de la transacción de la resolución.
solicitudesAdminRouter.post("/solicitudes/:id/resolucion", requireAdmin, requierePermiso(GESTIONAR_INCIDENCIAS_FINANZAS), async (req, res) => {
  res.status(201).json({ resolucion: await resolverServicio(adminActual(res).id, idDeRuta(req), leerCuerpo(req.body)) });
});
