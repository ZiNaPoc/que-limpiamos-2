import { Request, Response } from 'express';
import { galaxias_tipo } from '../../generated/prisma/client';
import * as galaxiasRepository from '../repositories/galaxy.repository';

export const getAll = async (req: Request, res: Response) => {
  try {
    const galaxias = await galaxiasRepository.getAll();
    res.json(galaxias);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al obtener las casas' });
  }
};

export const getById = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'id inválido' });
    }

    const galaxia = await galaxiasRepository.getById(id);
    if (!galaxia) {
      return res.status(404).json({ error: 'Casa no encontrada' });
    }
    res.json(galaxia);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al obtener la casa' });
  }
};

export const create = async (req: Request, res: Response) => {
  try {
    const { tipo, habitaciones, banos, medios_banos, pisos } = req.body;

    if (tipo !== undefined && !Object.values(galaxias_tipo).includes(tipo)) {
      return res.status(400).json({
        error: `tipo inválido. Valores permitidos: ${Object.values(galaxias_tipo).join(', ')}`,
      });
    }

    const numeros = { habitaciones, banos, medios_banos, pisos };
    for (const [campo, valor] of Object.entries(numeros)) {
      if (!Number.isInteger(valor) || (valor as number) < 0) {
        return res
          .status(400)
          .json({ error: `${campo} es requerido y debe ser un entero >= 0` });
      }
    }

    const nueva = await galaxiasRepository.create({
      tipo,
      habitaciones,
      banos,
      medios_banos,
      pisos,
    });
    res.status(201).json(nueva);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Error al crear la casa' });
  }
};