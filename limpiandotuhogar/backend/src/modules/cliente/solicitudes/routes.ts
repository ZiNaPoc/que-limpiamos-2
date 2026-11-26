import { Router } from "express";

import {
  cancelarPorCliente,
  catalogo,
  confirmarPorCliente,
  cotizar,
  crearSolicitud,
  detalleParaCliente,
  enviarABolsa,
  invitarOtro,
  urlFotoTerminado,
} from "../../../dominio/ciclo-solicitudes";
import { solicitudesDelCliente, trabajadoresParaSeleccion } from "../../../dominio/solicitudes";
import { AppError } from "../../../shared/errors/AppError";
import { enteroDeQuery, idDeRuta } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { clienteActual, requireCliente } from "../auth/guard";

/**
 * Solicitudes — audiencia CLIENTE (Fase 3b, doc 23; ciclo sin dinero, doc 25 v2).
 *   GET  /api/cliente/catalogo                         servicios, áreas y extras activos
 *   POST /api/cliente/cotizaciones                     precio y duración del servidor (no crea nada)
 *   GET  /api/cliente/trabajadores?servicioId=&fecha=  selección manual (con fecha: sin traslapes)
 *   POST /api/cliente/solicitudes                      crear (INE verificada; invitación o bolsa)
 *   GET  /api/cliente/solicitudes                      sus solicitudes (historial + estado del ciclo)
 *   GET  /api/cliente/solicitudes/:id                  detalle con las acciones permitidas
 *   POST /api/cliente/solicitudes/:id/bolsa            tras un rechazo: enviar a la bolsa
 *   POST /api/cliente/solicitudes/:id/invitaciones     tras un rechazo: invitar a otro { trabajadorId }
 *   POST /api/cliente/solicitudes/:id/cancelar         sin cargo { motivo? }
 *   POST /api/cliente/solicitudes/:id/confirmar        confirmar que se realizó
 *   GET  /api/cliente/solicitudes/:id/evidencias/:evidenciaId   URL temporal de una foto de «terminado»
 */
export const clienteSolicitudesRouter = Router();
const protegido = [requireCliente];

clienteSolicitudesRouter.get("/catalogo", ...protegido, async (_req, res) => {
  res.json(await catalogo());
});

clienteSolicitudesRouter.post("/cotizaciones", ...protegido, async (req, res) => {
  res.json({ cotizacion: await cotizar(clienteActual(res).id, leerCuerpo(req.body)) });
});

clienteSolicitudesRouter.get("/trabajadores", ...protegido, async (req, res) => {
  const crudo = req.query.fecha;
  let fecha: Date | undefined;
  if (typeof crudo === "string" && crudo !== "") {
    fecha = new Date(crudo);
    if (Number.isNaN(fecha.getTime())) throw new AppError(400, "El filtro fecha no es válido", "FILTRO_INVALIDO");
  }
  res.json({ trabajadores: await trabajadoresParaSeleccion(enteroDeQuery(req, "servicioId"), fecha) });
});

clienteSolicitudesRouter.post("/solicitudes", ...protegido, async (req, res) => {
  res.status(201).json({ solicitud: await crearSolicitud(clienteActual(res).id, leerCuerpo(req.body)) });
});

clienteSolicitudesRouter.get("/solicitudes", ...protegido, async (_req, res) => {
  res.json({ solicitudes: await solicitudesDelCliente(clienteActual(res).id) });
});

clienteSolicitudesRouter.get("/solicitudes/:id", ...protegido, async (req, res) => {
  res.json({ solicitud: await detalleParaCliente(clienteActual(res).id, idDeRuta(req)) });
});

clienteSolicitudesRouter.post("/solicitudes/:id/bolsa", ...protegido, async (req, res) => {
  res.json({ solicitud: await enviarABolsa(clienteActual(res).id, idDeRuta(req)) });
});

clienteSolicitudesRouter.post("/solicitudes/:id/invitaciones", ...protegido, async (req, res) => {
  res.json({ solicitud: await invitarOtro(clienteActual(res).id, idDeRuta(req), leerCuerpo(req.body)) });
});

clienteSolicitudesRouter.post("/solicitudes/:id/cancelar", ...protegido, async (req, res) => {
  res.json({ solicitud: await cancelarPorCliente(clienteActual(res).id, idDeRuta(req), leerCuerpo(req.body ?? {})) });
});

clienteSolicitudesRouter.post("/solicitudes/:id/confirmar", ...protegido, async (req, res) => {
  res.json({ solicitud: await confirmarPorCliente(clienteActual(res).id, idDeRuta(req)) });
});

clienteSolicitudesRouter.get("/solicitudes/:id/evidencias/:evidenciaId", ...protegido, async (req, res) => {
  res.json(await urlFotoTerminado({ rol: "CLIENTE", id: clienteActual(res).id }, idDeRuta(req), idDeRuta(req, "evidenciaId")));
});
