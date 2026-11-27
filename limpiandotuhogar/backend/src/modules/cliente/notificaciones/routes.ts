import { Router } from "express";

import { marcarLeida, marcarTodasLeidas, misNotificaciones } from "../../../dominio/notificaciones";
import { idDeRuta } from "../../../shared/http/parametros";
import { clienteActual, requireCliente } from "../auth/guard";

/**
 * Avisos — audiencia CLIENTE (D60; doc 25 v2).
 *   GET  /api/cliente/notificaciones             los 100 más recientes y cuántos sin leer
 *   POST /api/cliente/notificaciones/:id/leida   marcar uno (otro → 404)
 *   POST /api/cliente/notificaciones/leidas      marcar todos
 */
export const clienteNotificacionesRouter = Router();
const protegido = [requireCliente];

clienteNotificacionesRouter.get("/notificaciones", ...protegido, async (_req, res) => {
  res.json(await misNotificaciones({ rol: "CLIENTE", id: clienteActual(res).id }));
});

clienteNotificacionesRouter.post("/notificaciones/leidas", ...protegido, async (_req, res) => {
  res.json(await marcarTodasLeidas({ rol: "CLIENTE", id: clienteActual(res).id }));
});

clienteNotificacionesRouter.post("/notificaciones/:id/leida", ...protegido, async (req, res) => {
  res.json(await marcarLeida({ rol: "CLIENTE", id: clienteActual(res).id }, idDeRuta(req)));
});
