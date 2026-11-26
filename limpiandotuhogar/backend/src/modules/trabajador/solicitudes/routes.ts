import { Router } from "express";

import {
  aceptar,
  cancelarPorTrabajador,
  detalleParaTrabajador,
  disponiblesParaTrabajador,
  iniciar,
  LIMITES_FOTOS,
  rechazar,
  terminar,
  urlFotoTerminado,
} from "../../../dominio/ciclo-solicitudes";
import { marcarLeida, marcarTodasLeidas, misNotificaciones } from "../../../dominio/notificaciones";
import { solicitudesDelTrabajador } from "../../../dominio/solicitudes";
import { fotosRecibidas, recibirFotos } from "../../../shared/http/multipart";
import { idDeRuta } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { requireTrabajador, trabajadorActual } from "../auth/guard";

/**
 * Solicitudes — audiencia TRABAJADOR (Fase 3b, doc 23; ciclo sin dinero, doc 25 v2).
 *   GET  /api/trabajador/solicitudes/disponibles         invitaciones pendientes + bolsa elegible
 *   GET  /api/trabajador/solicitudes                     asignadas e invitaciones vigentes (historial)
 *   GET  /api/trabajador/solicitudes/:id                 detalle (asignada, invitado o en la bolsa)
 *   POST /api/trabajador/solicitudes/:id/aceptar
 *   POST /api/trabajador/solicitudes/:id/rechazar
 *   POST /api/trabajador/solicitudes/:id/cancelar        CONFIRMADO con 24 h o más { motivo? }
 *   POST /api/trabajador/solicitudes/:id/iniciar         de 30 min antes a 30 min después
 *   POST /api/trabajador/solicitudes/:id/terminar        multipart, campo "fotos" (1 a 5)
 *   GET  /api/trabajador/solicitudes/:id/evidencias/:evidenciaId   URL temporal de una foto suya
 *   GET  /api/trabajador/notificaciones · POST /notificaciones/:id/leida · POST /notificaciones/leidas
 */
export const trabajadorSolicitudesRouter = Router();
const protegido = [requireTrabajador];

trabajadorSolicitudesRouter.get("/solicitudes/disponibles", ...protegido, async (_req, res) => {
  res.json(await disponiblesParaTrabajador(trabajadorActual(res).id));
});

trabajadorSolicitudesRouter.get("/solicitudes", ...protegido, async (_req, res) => {
  res.json({ solicitudes: await solicitudesDelTrabajador(trabajadorActual(res).id) });
});

trabajadorSolicitudesRouter.get("/solicitudes/:id", ...protegido, async (req, res) => {
  res.json({ solicitud: await detalleParaTrabajador(trabajadorActual(res).id, idDeRuta(req)) });
});

trabajadorSolicitudesRouter.post("/solicitudes/:id/aceptar", ...protegido, async (req, res) => {
  res.json({ solicitud: await aceptar(trabajadorActual(res).id, idDeRuta(req)) });
});

trabajadorSolicitudesRouter.post("/solicitudes/:id/rechazar", ...protegido, async (req, res) => {
  res.json(await rechazar(trabajadorActual(res).id, idDeRuta(req)));
});

trabajadorSolicitudesRouter.post("/solicitudes/:id/cancelar", ...protegido, async (req, res) => {
  res.json(await cancelarPorTrabajador(trabajadorActual(res).id, idDeRuta(req), leerCuerpo(req.body ?? {})));
});

trabajadorSolicitudesRouter.post("/solicitudes/:id/iniciar", ...protegido, async (req, res) => {
  res.json({ solicitud: await iniciar(trabajadorActual(res).id, idDeRuta(req)) });
});

trabajadorSolicitudesRouter.post(
  "/solicitudes/:id/terminar",
  ...protegido,
  recibirFotos({ cantidad: LIMITES_FOTOS.cantidad, bytesPorArchivo: LIMITES_FOTOS.bytesPorFoto }),
  async (req, res) => {
    res.json({ solicitud: await terminar(trabajadorActual(res).id, idDeRuta(req), fotosRecibidas(req)) });
  },
);

trabajadorSolicitudesRouter.get("/solicitudes/:id/evidencias/:evidenciaId", ...protegido, async (req, res) => {
  res.json(await urlFotoTerminado({ rol: "TRABAJADOR", id: trabajadorActual(res).id }, idDeRuta(req), idDeRuta(req, "evidenciaId")));
});

trabajadorSolicitudesRouter.get("/notificaciones", ...protegido, async (_req, res) => {
  res.json(await misNotificaciones({ rol: "TRABAJADOR", id: trabajadorActual(res).id }));
});

trabajadorSolicitudesRouter.post("/notificaciones/leidas", ...protegido, async (_req, res) => {
  res.json(await marcarTodasLeidas({ rol: "TRABAJADOR", id: trabajadorActual(res).id }));
});

trabajadorSolicitudesRouter.post("/notificaciones/:id/leida", ...protegido, async (req, res) => {
  res.json(await marcarLeida({ rol: "TRABAJADOR", id: trabajadorActual(res).id }, idDeRuta(req)));
});
