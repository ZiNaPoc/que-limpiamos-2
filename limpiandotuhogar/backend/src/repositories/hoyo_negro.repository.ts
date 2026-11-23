import { prisma } from "../config/prisma";
import { Prisma } from "../../generated/prisma/client";

export const ESTADO = {
  DISPONIBLE: "DISPONIBLE",
  ACEPTADA: "ACEPTADA",
} as const;

export interface CreateHoyoNegroData {
  cliente_id: number;
  fecha?: string;
  seleccion: Prisma.InputJsonValue;
  total: number;
  id_galaxias: number;
}

const incluir = {
  galaxias: true,
  estrellas: {
    select: { id: true, name: true, email: true, phone_number: true },
  },
};

const seleccionTrabajador = {
  id: true,
  name: true,
  phone_number: true,
} as const;

async function conTrabajador<T extends { trabajador_id: number | null }>(
  items: T[],
) {
  const ids = [
    ...new Set(
      items
        .map((i) => i.trabajador_id)
        .filter((id): id is number => id !== null),
    ),
  ];
  const trabajadores = ids.length
    ? await prisma.estrellas.findMany({
        where: { id: { in: ids } },
        select: seleccionTrabajador,
      })
    : [];
  const porId = new Map(trabajadores.map((t) => [t.id, t]));
  return items.map((i) => ({
    ...i,
    trabajador:
      i.trabajador_id !== null ? (porId.get(i.trabajador_id) ?? null) : null,
  }));
}

async function conTrabajadorUno<T extends { trabajador_id: number | null }>(
  item: T | null,
) {
  if (!item) return null;
  const [conNombre] = await conTrabajador([item]);
  return conNombre;
}

export const getAll = async () =>
  conTrabajador(
    await prisma.hoyo_negro.findMany({
      include: incluir,
      orderBy: { id: "desc" },
    }),
  );

export const getById = async (id: number) =>
  conTrabajadorUno(
    await prisma.hoyo_negro.findUnique({ where: { id }, include: incluir }),
  );

export const getByCliente = async (cliente_id: number) =>
  conTrabajador(
    await prisma.hoyo_negro.findMany({
      where: { cliente_id },
      include: incluir,
      orderBy: { id: "desc" },
    }),
  );

export const getByTrabajador = async (trabajador_id: number) =>
  conTrabajador(
    await prisma.hoyo_negro.findMany({
      where: { trabajador_id },
      include: incluir,
      orderBy: { id: "desc" },
    }),
  );

export const getDisponibles = async () =>
  conTrabajador(
    await prisma.hoyo_negro.findMany({
      where: { estado: ESTADO.DISPONIBLE },
      include: incluir,
      orderBy: { id: "desc" },
    }),
  );

export const create = async ({
  cliente_id,
  fecha,
  seleccion,
  total,
  id_galaxias,
}: CreateHoyoNegroData) =>
  conTrabajadorUno(
    await prisma.hoyo_negro.create({
      data: {
        cliente_id,
        fecha: fecha ? new Date(fecha) : new Date(),
        seleccion,
        total,
        id_galaxias,
      },
      include: incluir,
    }),
  );

export const esTrabajador = async (id: number) =>
  (await prisma.estrellas.count({ where: { id, rol: "TRABAJADOR" } })) > 0;

export const aceptar = async (id: number, trabajador_id: number) => {
  const { count } = await prisma.hoyo_negro.updateMany({
    where: { id, estado: ESTADO.DISPONIBLE },
    data: { estado: ESTADO.ACEPTADA, trabajador_id },
  });
  if (count === 0) return null;
  return getById(id);
};