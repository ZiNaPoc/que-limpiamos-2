import { Router } from "express";

import { leerMotivo } from "../../../dominio/auditoria";
import { ADMINISTRAR_PERMISOS, listarAdministradores, otorgarPermiso, permisosEfectivos, revocarPermiso, type Permiso } from "../../../dominio/permisos";
import { AppError } from "../../../shared/errors/AppError";
import { idDeRuta } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { adminActual, requireAdmin } from "../auth/guard";
import { requierePermiso } from "../moderacion/routes";

/**
 * Permisos de admin (doc 20 §6).
 *   GET  /api/admin/permisos/mios               cualquier admin: sus permisos EFECTIVOS (el panel
 *                                                 muestra solo lo que el backend permite). El propietario
 *                                                 incluye SUPERVISAR_SOLICITUDES implícito (en `implicitos`)
 *   GET  /api/admin/permisos                     propietario: admins y permisos vigentes
 *   POST /api/admin/permisos                     propietario: { usuarioId, permiso, motivo }
 *   POST /api/admin/permisos/:id/revocar         propietario: { motivo }
 * Cada otorgamiento y revocación deja fila en admin_permisos y evento en moderacion_eventos.
 */
export const permisosRouter = Router();
permisosRouter.use(requireAdmin);

permisosRouter.get("/mios", async (_req, res) => {
  res.json(await permisosEfectivos(adminActual(res).id));
});

permisosRouter.get("/", requierePermiso(ADMINISTRAR_PERMISOS), async (_req, res) => {
  res.json({ administradores: await listarAdministradores() });
});

permisosRouter.post("/", requierePermiso(ADMINISTRAR_PERMISOS), async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const motivo = leerMotivo(cuerpo);
  const usuarioId = Number(cuerpo.usuarioId);
  if (!Number.isSafeInteger(usuarioId) || usuarioId <= 0) throw new AppError(400, "Indica el administrador (usuarioId)", "USUARIO_INVALIDO");
  if (typeof cuerpo.permiso !== "string") throw new AppError(400, "Indica el permiso", "PERMISO_INVALIDO");
  const permiso = await otorgarPermiso(adminActual(res).id, { usuarioId, permiso: cuerpo.permiso as Permiso, motivo });
  res.status(201).json({ permiso });
});

permisosRouter.post("/:id/revocar", requierePermiso(ADMINISTRAR_PERMISOS), async (req, res) => {
  const motivo = leerMotivo(leerCuerpo(req.body));
  res.json({ permiso: await revocarPermiso(adminActual(res).id, { permisoId: idDeRuta(req), motivo }) });
});
