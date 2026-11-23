import { Request, Response } from "express";
import { Prisma } from "../../generated/prisma/client";
import * as hoyoNegroRepository from "../repositories/hoyo_negro.repository";

export const getAll = async (req: Request, res: Response) => {
  try {
    const { cliente_id, trabajador_id } = req.query;

    const servicios = cliente_id
      ? await hoyoNegroRepository.getByCliente(Number(cliente_id))
      : trabajador_id
        ? await hoyoNegroRepository.getByTrabajador(Number(trabajador_id))
        : await hoyoNegroRepository.getAll();

    res.json(servicios);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: "Error al obtener los servicios de limpieza" });
  }
};

export const getDisponibles = async (req: Request, res: Response) => {
  try {
    const servicios = await hoyoNegroRepository.getDisponibles();
    res.json(servicios);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: "Error al obtener las solicitudes disponibles" });
  }
};

export const getById = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: "id inválido" });
    }

    const servicio = await hoyoNegroRepository.getById(id);
    if (!servicio) {
      return res.status(404).json({ error: "Servicio no encontrado" });
    }
    res.json(servicio);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: "Error al obtener el servicio" });
  }
};

export const create = async (req: Request, res: Response) => {
  try {
    const { cliente_id, fecha, seleccion, total, id_galaxias } = req.body;

    if (!Number.isInteger(cliente_id) || !Number.isInteger(id_galaxias)) {
      return res
        .status(400)
        .json({ error: "cliente_id e id_galaxias son requeridos (enteros)" });
    }
    if (seleccion === undefined || seleccion === null) {
      return res.status(400).json({ error: "seleccion es requerida" });
    }
    if (typeof total !== "number" || total < 0) {
      return res.status(400).json({ error: "total es requerido y debe ser >= 0" });
    }
    if (fecha && isNaN(new Date(fecha).getTime())) {
      return res.status(400).json({ error: "fecha inválida" });
    }

    const nuevo = await hoyoNegroRepository.create({
      cliente_id,
      fecha,
      seleccion,
      total,
      id_galaxias,
    });
    res.status(201).json(nuevo);
  } catch (error) {
    // P2003 = falla de llave foránea (cliente o casa no existe)
    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2003"
    ) {
      return res.status(400).json({ error: "El cliente o la casa no existe" });
    }
    console.error(error);
    res.status(500).json({ error: "Error al crear el servicio" });
  }
};

export const aceptar = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    const { trabajador_id } = req.body;

    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: "id inválido" });
    }
    if (!Number.isInteger(trabajador_id)) {
      return res.status(400).json({ error: "trabajador_id es requerido (entero)" });
    }
    if (!(await hoyoNegroRepository.esTrabajador(trabajador_id))) {
      return res
        .status(403)
        .json({ error: "Solo un trabajador puede aceptar solicitudes" });
    }

    const existente = await hoyoNegroRepository.getById(id);
    if (!existente) {
      return res.status(404).json({ error: "Solicitud no encontrada" });
    }

    const aceptada = await hoyoNegroRepository.aceptar(id, trabajador_id);
    if (!aceptada) {
      return res
        .status(409)
        .json({ error: "Esta solicitud ya fue tomada por otro trabajador" });
    }
    res.json(aceptada);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: "Error al aceptar la solicitud" });
  }
};