import { Router, type RequestHandler } from "express";

import { leerMotivo } from "../../../dominio/auditoria";
import {
  cambiarEstadoReporte,
  detalleReporte,
  editarResena,
  editarReporte,
  eliminarFotoDeReporte,
  eliminarReporte,
  eliminarResena,
  listarEventos,
  listarReportes,
  listarResenas,
  notaDeSeguimiento,
  resolverReporte,
} from "../../../dominio/moderacion";
import { ADMINISTRAR_PERMISOS, MODERAR_CONTENIDO, permisoVigente, type Permiso } from "../../../dominio/permisos";
import { leerDescripcion, leerTipo } from "../../../dominio/reportes";
import { prisma } from "../../../config/prisma";
import { AppError } from "../../../shared/errors/AppError";
import { enteroDeQuery, idDeRuta, opcionDeQuery } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { adminActual, requireAdmin } from "../auth/guard";

/** Exige un permiso VIGENTE en el backend (no basta ocultar la página en el panel). */
export function requierePermiso(permiso: Permiso): RequestHandler {
  return async (_req, res, next) => {
    if ((await permisoVigente(prisma, adminActual(res).id, permiso)) === null) {
      throw new AppError(403, "No tienes permiso para esta sección", "PERMISO_REQUERIDO");
    }
    next();
  };
}

/**
 * Moderación — audiencia ADMIN con MODERAR_CONTENIDO (doc 20 §4–§5). Sin el permiso → 403 en
 * todas las rutas, incluida GET /api/admin/resenas (X0). Toda modificación exige `motivo` y
 * deja su evento de auditoría.
 */
export const moderacionRouter = Router();
const protegido = [requireAdmin, requierePermiso(MODERAR_CONTENIDO)];

// ── Reseñas ──
moderacionRouter.get("/resenas", ...protegido, async (req, res) => {
  const resenas = await listarResenas({
    puntuacion: enteroDeQuery(req, "puntuacion"),
    autorRol: opcionDeQuery(req, "autorRol", ["CLIENTE", "TRABAJADOR"] as const),
    trabajadorId: enteroDeQuery(req, "trabajadorId"),
    clienteId: enteroDeQuery(req, "clienteId"),
    incluirEliminadas: req.query.incluirEliminadas === "1" || req.query.incluirEliminadas === "true",
  });
  res.json({ total: resenas.length, resenas });
});

moderacionRouter.patch("/resenas/:id", ...protegido, async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const motivo = leerMotivo(cuerpo);
  res.json({ resena: await editarResena(adminActual(res).id, idDeRuta(req), { puntuacion: cuerpo.puntuacion, comentario: cuerpo.comentario }, motivo) });
});

moderacionRouter.delete("/resenas/:id", ...protegido, async (req, res) => {
  const motivo = leerMotivo(leerCuerpo(req.body ?? {}));
  res.json({ resena: await eliminarResena(adminActual(res).id, idDeRuta(req), motivo) });
});

// ── Reportes ──
const ESTADOS = ["ABIERTO", "EN_REVISION", "RESUELTO"] as const;
const TIPOS = ["NO_SE_PUDO_COMPLETAR", "INASISTENCIA", "PROBLEMA_UBICACION", "UBICACION_FALSA", "PAGO_EN_DISPUTA", "OTRO"] as const;

moderacionRouter.get("/reportes", ...protegido, async (req, res) => {
  const reportes = await listarReportes({
    estado: opcionDeQuery(req, "estado", ESTADOS),
    tipo: opcionDeQuery(req, "tipo", TIPOS),
    incluirEliminados: req.query.incluirEliminados === "1" || req.query.incluirEliminados === "true",
  });
  res.json({ total: reportes.length, reportes });
});

moderacionRouter.get("/reportes/:id", ...protegido, async (req, res) => {
  res.json({ reporte: await detalleReporte(idDeRuta(req)) });
});

moderacionRouter.patch("/reportes/:id", ...protegido, async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const motivo = leerMotivo(cuerpo);
  const cambios = {
    tipo: leerTipo(cuerpo.tipo, true),
    ...("descripcion" in cuerpo ? { descripcion: leerDescripcion(cuerpo.descripcion) } : {}),
  };
  res.json({ reporte: await editarReporte(adminActual(res).id, idDeRuta(req), cambios, motivo) });
});

moderacionRouter.post("/reportes/:id/estado", ...protegido, async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const motivo = leerMotivo(cuerpo);
  if (cuerpo.estado !== "ABIERTO" && cuerpo.estado !== "EN_REVISION") {
    throw new AppError(400, "El estado debe ser ABIERTO o EN_REVISION (para resolver usa /resolucion)", "ESTADO_INVALIDO");
  }
  res.json({ reporte: await cambiarEstadoReporte(adminActual(res).id, idDeRuta(req), cuerpo.estado, motivo) });
});

moderacionRouter.post("/reportes/:id/seguimiento", ...protegido, async (req, res) => {
  const nota = leerMotivo(leerCuerpo(req.body), "nota");
  res.status(201).json(await notaDeSeguimiento(adminActual(res).id, idDeRuta(req), nota));
});

moderacionRouter.post("/reportes/:id/resolucion", ...protegido, async (req, res) => {
  const resolucion = leerMotivo(leerCuerpo(req.body), "resolucion");
  res.json({ reporte: await resolverReporte(adminActual(res).id, idDeRuta(req), resolucion) });
});

moderacionRouter.delete("/reportes/:id", ...protegido, async (req, res) => {
  const motivo = leerMotivo(leerCuerpo(req.body ?? {}));
  res.json({ reporte: await eliminarReporte(adminActual(res).id, idDeRuta(req), motivo) });
});

moderacionRouter.delete("/reportes/:id/fotos/:fotoId", ...protegido, async (req, res) => {
  const motivo = leerMotivo(leerCuerpo(req.body ?? {}));
  res.json({ foto: await eliminarFotoDeReporte(adminActual(res).id, idDeRuta(req), idDeRuta(req, "fotoId"), motivo) });
});

// ── Historial de auditoría (solo lectura) ──
moderacionRouter.get("/moderacion/eventos", ...protegido, async (req, res) => {
  const entidad = opcionDeQuery(req, "entidad", ["RESENA", "REPORTE", "PERMISO"] as const);
  if (entidad === "PERMISO" && (await permisoVigente(prisma, adminActual(res).id, ADMINISTRAR_PERMISOS)) === null) {
    throw new AppError(403, "El historial de permisos solo lo consulta el propietario", "PERMISO_REQUERIDO");
  }
  const eventos = await listarEventos({ entidad: entidad ?? undefined, id: enteroDeQuery(req, "id") });
  const visibles = entidad ? eventos : eventos.filter((e) => e.entidad !== "PERMISO");
  res.json({ total: visibles.length, eventos: visibles });
});
