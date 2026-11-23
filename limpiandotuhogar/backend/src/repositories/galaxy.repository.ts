import { prisma } from "../config/prisma";
import { galaxias_tipo } from "../../generated/prisma/client";

export interface CreateGalaxiaData {
  tipo?: galaxias_tipo;
  habitaciones: number;
  banos: number;
  medios_banos: number;
  pisos: number;
}

export const getAll = () => prisma.galaxias.findMany();

export const getById = (id: number) =>
  prisma.galaxias.findUnique({ where: { id } });

export const create = ({
  tipo,
  habitaciones,
  banos,
  medios_banos,
  pisos,
}: CreateGalaxiaData) =>
  prisma.galaxias.create({
    data: {
      habitaciones,
      banos,
      medios_banos,
      pisos,
      ...(tipo !== undefined && { tipo }), 
    },
  });