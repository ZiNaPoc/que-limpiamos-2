import { Router } from "express";

import { archivarInmueble, crearInmueble, editarInmueble, leerDatosInmueble, leerNombreInmueble, listarInmuebles } from "../../../dominio/inmuebles";
import { idDeRuta } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { clienteActual, requireCliente } from "../auth/guard";

/**
 * «Mis inmuebles» — audiencia CLIENTE (doc 25 v2 §3). Solo los suyos (otro → 404).
 *   GET    /api/cliente/inmuebles        sus inmuebles guardados (sin los eliminados)
 *   POST   /api/cliente/inmuebles        { nombre, tipo, direccion, habitaciones, banos, mediosBanos, pisos }
 *   PATCH  /api/cliente/inmuebles/:id    edición parcial (no cambia solicitudes anteriores)
 *   DELETE /api/cliente/inmuebles/:id    eliminar = archivar (las solicitudes conservan su copia)
 */
export const clienteInmueblesRouter = Router();
const protegido = [requireCliente];

clienteInmueblesRouter.get("/inmuebles", ...protegido, async (_req, res) => {
  res.json({ inmuebles: await listarInmuebles(clienteActual(res).id) });
});

clienteInmueblesRouter.post("/inmuebles", ...protegido, async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  res.status(201).json({ inmueble: await crearInmueble(clienteActual(res).id, leerNombreInmueble(cuerpo.nombre), leerDatosInmueble(cuerpo)) });
});

clienteInmueblesRouter.patch("/inmuebles/:id", ...protegido, async (req, res) => {
  res.json({ inmueble: await editarInmueble(clienteActual(res).id, idDeRuta(req), leerCuerpo(req.body)) });
});

clienteInmueblesRouter.delete("/inmuebles/:id", ...protegido, async (req, res) => {
  res.json(await archivarInmueble(clienteActual(res).id, idDeRuta(req)));
});
