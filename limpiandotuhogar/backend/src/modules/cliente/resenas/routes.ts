import { Router } from "express";

import { crearResena, leerDatosResena, reputacion, reputacionesDeTrabajadores, resenasEscritas, resenasRecibidasPublicas } from "../../../dominio/resenas";
import { AppError } from "../../../shared/errors/AppError";
import { idDeRuta } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { clienteActual, requireCliente } from "../auth/guard";

/**
 * Reseñas — audiencia CLIENTE (doc 20 §1–§2). La identidad sale SIEMPRE del token.
 *   POST /api/cliente/solicitudes/:id/resena          califica al trabajador de ESE servicio
 *   GET  /api/cliente/resenas                          su historial (las que escribió)
 *   GET  /api/cliente/trabajadores/:id/resenas         reseñas del trabajador, ANÓNIMAS + promedio
 *   GET  /api/cliente/trabajadores/:id/reputacion      promedio y cantidad (perfil)
 *   GET  /api/cliente/trabajadores/reputacion?ids=1,2  estrellas para la selección manual
 * No hay PATCH/DELETE: el usuario no edita ni borra reseñas (R10).
 */
export const clienteResenasRouter = Router();
const protegido = [requireCliente];

clienteResenasRouter.post("/solicitudes/:id/resena", ...protegido, async (req, res) => {
  if (req.is("multipart/form-data")) throw new AppError(415, "Las reseñas no admiten fotografías", "FOTOS_NO_PERMITIDAS");
  const datos = leerDatosResena(leerCuerpo(req.body));
  const resena = await crearResena({ solicitudId: idDeRuta(req), autorRol: "CLIENTE", autorId: clienteActual(res).id, ...datos });
  res.status(201).json({ resena });
});

clienteResenasRouter.get("/resenas", ...protegido, async (_req, res) => {
  res.json({ resenas: await resenasEscritas("CLIENTE", clienteActual(res).id) });
});

clienteResenasRouter.get("/trabajadores/reputacion", ...protegido, async (req, res) => {
  const crudo = typeof req.query.ids === "string" ? req.query.ids : "";
  const ids = [...new Set(crudo.split(",").map((x) => Number(x.trim())).filter((n) => Number.isSafeInteger(n) && n > 0))].slice(0, 100);
  res.json({ reputaciones: await reputacionesDeTrabajadores(ids) });
});

clienteResenasRouter.get("/trabajadores/:id/reputacion", ...protegido, async (req, res) => {
  res.json({ reputacion: await reputacion({ rol: "TRABAJADOR", id: idDeRuta(req) }) });
});

clienteResenasRouter.get("/trabajadores/:id/resenas", ...protegido, async (req, res) => {
  const calificado = { rol: "TRABAJADOR" as const, id: idDeRuta(req) };
  res.json({ reputacion: await reputacion(calificado), resenas: await resenasRecibidasPublicas(calificado) });
});
