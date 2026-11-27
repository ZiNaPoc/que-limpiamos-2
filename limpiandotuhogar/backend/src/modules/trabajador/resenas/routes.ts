import { Router } from "express";

import {
  crearResena,
  leerDatosResena,
  reputacion,
  reputacionDelClienteParaTrabajador,
  resenasEscritas,
  resenasRecibidasPublicas,
} from "../../../dominio/resenas";
import { AppError } from "../../../shared/errors/AppError";
import { idDeRuta } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { requireTrabajador, trabajadorActual } from "../auth/guard";

/**
 * Reseñas — audiencia TRABAJADOR (doc 20 §1–§2). La identidad sale SIEMPRE del token.
 *   POST /api/trabajador/solicitudes/:id/resena               califica al cliente de ESE servicio
 *   GET  /api/trabajador/resenas                               su historial (las que escribió)
 *   GET  /api/trabajador/resenas/recibidas                     las que recibió, ANÓNIMAS + su promedio
 *   GET  /api/trabajador/solicitudes/:id/reputacion-cliente    solo si está invitado o asignado (V5)
 */
export const trabajadorResenasRouter = Router();
const protegido = [requireTrabajador];

trabajadorResenasRouter.post("/solicitudes/:id/resena", ...protegido, async (req, res) => {
  if (req.is("multipart/form-data")) throw new AppError(415, "Las reseñas no admiten fotografías", "FOTOS_NO_PERMITIDAS");
  const datos = leerDatosResena(leerCuerpo(req.body));
  const resena = await crearResena({ solicitudId: idDeRuta(req), autorRol: "TRABAJADOR", autorId: trabajadorActual(res).id, ...datos });
  res.status(201).json({ resena });
});

trabajadorResenasRouter.get("/resenas", ...protegido, async (_req, res) => {
  res.json({ resenas: await resenasEscritas("TRABAJADOR", trabajadorActual(res).id) });
});

trabajadorResenasRouter.get("/resenas/recibidas", ...protegido, async (_req, res) => {
  const calificado = { rol: "TRABAJADOR" as const, id: trabajadorActual(res).id };
  res.json({ reputacion: await reputacion(calificado), resenas: await resenasRecibidasPublicas(calificado) });
});

trabajadorResenasRouter.get("/solicitudes/:id/reputacion-cliente", ...protegido, async (req, res) => {
  res.json({ reputacion: await reputacionDelClienteParaTrabajador(trabajadorActual(res).id, idDeRuta(req)) });
});
