import { Router, type RequestHandler } from "express";

import { prisma } from "../../../config/prisma";
import { puedeSupervisar } from "../../../dominio/permisos";
import {
  catalogoAdmin,
  crearArea,
  crearExtra,
  crearServicio,
  editarArea,
  editarExtra,
  editarServicio,
  listarClientes,
  listarTrabajadores,
  resumen,
} from "../../../dominio/plataforma";
import { AppError } from "../../../shared/errors/AppError";
import { idDeRuta } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { adminActual, requireAdmin } from "../auth/guard";

export const plataformaRouter = Router();

const requiereSupervision: RequestHandler = async (_req, res, next) => {
  if (!(await puedeSupervisar(prisma, adminActual(res).id))) throw new AppError(403, "No tienes permiso para ver esta sección", "PERMISO_REQUERIDO");
  next();
};

plataformaRouter.get("/resumen", requireAdmin, async (_req, res) => {
  res.json(await resumen());
});

plataformaRouter.get("/clientes", requireAdmin, requiereSupervision, async (req, res) => {
  res.json(await listarClientes(req.query as Record<string, unknown>));
});

plataformaRouter.get("/trabajadores", requireAdmin, requiereSupervision, async (req, res) => {
  res.json(await listarTrabajadores(req.query as Record<string, unknown>));
});

plataformaRouter.get("/catalogo", requireAdmin, async (_req, res) => {
  res.json(await catalogoAdmin());
});

plataformaRouter.post("/catalogo/servicios", requireAdmin, async (req, res) => {
  res.status(201).json(await crearServicio(leerCuerpo(req.body)));
});
plataformaRouter.patch("/catalogo/servicios/:id", requireAdmin, async (req, res) => {
  res.json(await editarServicio(idDeRuta(req), leerCuerpo(req.body)));
});
plataformaRouter.post("/catalogo/extras", requireAdmin, async (req, res) => {
  res.status(201).json(await crearExtra(leerCuerpo(req.body)));
});
plataformaRouter.patch("/catalogo/extras/:id", requireAdmin, async (req, res) => {
  res.json(await editarExtra(idDeRuta(req), leerCuerpo(req.body)));
});
plataformaRouter.post("/catalogo/areas", requireAdmin, async (req, res) => {
  res.status(201).json(await crearArea(leerCuerpo(req.body)));
});
plataformaRouter.patch("/catalogo/areas/:id", requireAdmin, async (req, res) => {
  res.json(await editarArea(idDeRuta(req), leerCuerpo(req.body)));
});
