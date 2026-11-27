import type { resenas, resenas_autor_rol } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { AppError } from "../shared/errors/AppError";
import { campoDuplicado } from "../shared/errors/duplicados";
import type { Cuerpo } from "../shared/validation/campos";
import { relojDominio } from "./reloj";

/**
 * RESEÑAS bidireccionales (doc 20 §1–§2).
 *  - El cliente califica al trabajador (autor_rol CLIENTE) y el trabajador al cliente (TRABAJADOR).
 *  - 1–5 estrellas obligatorias; comentario opcional de hasta 500 caracteres (X1); sin fotos.
 *  - Solo con la solicitud REALIZADO y dentro de 168 h exactas desde realizado_en (X7, X8: UTC).
 *  - Una por (solicitud, rol del autor); la eliminada lógicamente sigue ocupando su lugar (X4).
 *  - Se publican al instante. No bloquean pagos, cierres ni solicitudes: este módulo no toca
 *    ninguna otra tabla.
 *  - PRIVACIDAD: el autor se guarda (cliente_id/trabajador_id + autor_rol) para la moderación,
 *    pero NINGÚN DTO de cliente o trabajador lo incluye (ni ids, ni servicio, ni fecha exacta).
 */

export type RolAutor = resenas_autor_rol;
export const PUNTUACION_MIN = 1;
export const PUNTUACION_MAX = 5;
export const MAX_COMENTARIO = 500;
export const PLAZO_HORAS = 168;
const PLAZO_MS = PLAZO_HORAS * 60 * 60 * 1000;
const CAMPOS_DE_FOTO = ["foto", "fotos", "imagen", "imagenes", "evidencia", "evidencias", "archivo", "archivos"];

/** Valida puntuación y comentario. Lanza 400 con un código por cada regla. */
export function leerDatosResena(cuerpo: Cuerpo): { puntuacion: number; comentario: string | null } {
  if (CAMPOS_DE_FOTO.some((campo) => campo in cuerpo)) {
    throw new AppError(400, "Las reseñas no admiten fotografías", "FOTOS_NO_PERMITIDAS");
  }
  const puntuacion = cuerpo.puntuacion;
  if (typeof puntuacion !== "number" || !Number.isInteger(puntuacion) || puntuacion < PUNTUACION_MIN || puntuacion > PUNTUACION_MAX) {
    throw new AppError(400, "La calificación debe ser un número entero de 1 a 5 estrellas", "PUNTUACION_INVALIDA");
  }
  const crudo = cuerpo.comentario;
  if (crudo !== undefined && crudo !== null && typeof crudo !== "string") {
    throw new AppError(400, "El comentario debe ser texto", "COMENTARIO_INVALIDO");
  }
  const comentario = typeof crudo === "string" ? crudo.trim() : "";
  if ([...comentario].length > MAX_COMENTARIO) {
    throw new AppError(400, `El comentario admite como máximo ${MAX_COMENTARIO} caracteres`, "COMENTARIO_LARGO");
  }
  return { puntuacion, comentario: comentario || null };
}

/** La reseña tal como la ve SU AUTOR en su historial (R11). */
export function dtoResenaPropia(r: resenas) {
  return {
    id: r.id,
    solicitudId: r.solicitud_id,
    calificaA: r.autor_rol === "CLIENTE" ? "TRABAJADOR" : "CLIENTE",
    puntuacion: r.puntuacion,
    comentario: r.comentario,
    fecha: r.created_at.toISOString(),
    editadaPorModeracion: r.editada_en !== null,
    eliminadaPorModeracion: r.eliminada_en !== null,
  };
}

/** Reseña PÚBLICA (V1–V2): solo calificación, comentario y mes/año (UTC). Sin autor, id ni servicio. */
export function dtoResenaPublica(r: Pick<resenas, "puntuacion" | "comentario" | "created_at">) {
  return { puntuacion: r.puntuacion, comentario: r.comentario, mes: r.created_at.getUTCMonth() + 1, anio: r.created_at.getUTCFullYear() };
}

/** Crea la reseña del autor indicado. La identidad sale del token, nunca del cuerpo. */
export async function crearResena(datos: { solicitudId: number; autorRol: RolAutor; autorId: number; puntuacion: number; comentario: string | null }) {
  const solicitud = await prisma.solicitudes.findUnique({
    where: { id: datos.solicitudId },
    select: { id: true, cliente_id: true, trabajador_id: true, estado: true, realizado_en: true },
  });
  if (!solicitud) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  const esParte = datos.autorRol === "CLIENTE" ? solicitud.cliente_id === datos.autorId : solicitud.trabajador_id === datos.autorId;
  if (!esParte) throw new AppError(403, "Solo las partes del servicio pueden calificarlo", "NO_ES_PARTE");
  if (solicitud.estado !== "REALIZADO" || !solicitud.realizado_en || solicitud.trabajador_id === null) {
    throw new AppError(409, "Solo puedes calificar un servicio finalizado", "SERVICIO_NO_FINALIZADO");
  }
  if (relojDominio.ahora().getTime() > solicitud.realizado_en.getTime() + PLAZO_MS) {
    throw new AppError(409, `El plazo para calificar (${PLAZO_HORAS} horas desde que finalizó el servicio) ya venció`, "PLAZO_VENCIDO");
  }
  try {
    const creada = await prisma.resenas.create({
      data: {
        solicitud_id: solicitud.id,
        autor_rol: datos.autorRol,
        cliente_id: solicitud.cliente_id,
        trabajador_id: solicitud.trabajador_id,
        puntuacion: datos.puntuacion,
        comentario: datos.comentario,
        created_at: relojDominio.ahora(),
      },
    });
    return dtoResenaPropia(creada);
  } catch (error) {
    if (campoDuplicado(error, ["solicitud_id"]) !== null) {
      throw new AppError(409, "Ya calificaste este servicio", "RESENA_DUPLICADA");
    }
    throw error;
  }
}

/** Reseñas que escribió el usuario (su historial). */
export async function resenasEscritas(autorRol: RolAutor, autorId: number) {
  const filas = await prisma.resenas.findMany({
    where: autorRol === "CLIENTE" ? { autor_rol: "CLIENTE", cliente_id: autorId } : { autor_rol: "TRABAJADOR", trabajador_id: autorId },
    orderBy: { id: "desc" },
  });
  return filas.map(dtoResenaPropia);
}

/** Reseñas VÁLIDAS recibidas por una parte, anónimas (V1–V2), de la más reciente a la más antigua. */
export async function resenasRecibidasPublicas(calificado: { rol: RolAutor; id: number }) {
  const filas = await prisma.resenas.findMany({
    where: calificado.rol === "TRABAJADOR"
      ? { autor_rol: "CLIENTE", trabajador_id: calificado.id, eliminada_en: null }
      : { autor_rol: "TRABAJADOR", cliente_id: calificado.id, eliminada_en: null },
    select: { puntuacion: true, comentario: true, created_at: true },
    orderBy: { created_at: "desc" },
  });
  return filas.map(dtoResenaPublica);
}

export type Reputacion = { promedio: number | null; cantidad: number };

function redondear(valor: number | null): number | null {
  return valor === null ? null : Math.round(valor * 100) / 100;
}

/** Promedio de las reseñas VÁLIDAS recibidas (null si no hay; nunca 0 estrellas). */
export async function reputacion(calificado: { rol: RolAutor; id: number }): Promise<Reputacion> {
  const r = await prisma.resenas.aggregate({
    where: calificado.rol === "TRABAJADOR"
      ? { autor_rol: "CLIENTE", trabajador_id: calificado.id, eliminada_en: null }
      : { autor_rol: "TRABAJADOR", cliente_id: calificado.id, eliminada_en: null },
    _avg: { puntuacion: true },
    _count: { _all: true },
  });
  return { promedio: redondear(r._avg.puntuacion), cantidad: r._count._all };
}

/** Reputación de varios trabajadores a la vez (selección manual, V4). */
export async function reputacionesDeTrabajadores(ids: number[]): Promise<Record<string, Reputacion>> {
  const grupos = ids.length
    ? await prisma.resenas.groupBy({
        by: ["trabajador_id"],
        where: { autor_rol: "CLIENTE", trabajador_id: { in: ids }, eliminada_en: null },
        _avg: { puntuacion: true },
        _count: { _all: true },
      })
    : [];
  const resultado: Record<string, Reputacion> = {};
  for (const id of ids) resultado[id] = { promedio: null, cantidad: 0 };
  for (const g of grupos) resultado[g.trabajador_id] = { promedio: redondear(g._avg.puntuacion), cantidad: g._count._all };
  return resultado;
}

/**
 * V5: la reputación del cliente solo la ve el trabajador ASIGNADO a una solicitud de ese
 * cliente o INVITADO a ella con la invitación vigente (PENDIENTE o ACEPTADA).
 */
export async function reputacionDelClienteParaTrabajador(trabajadorId: number, solicitudId: number): Promise<Reputacion> {
  const solicitud = await prisma.solicitudes.findUnique({ where: { id: solicitudId }, select: { cliente_id: true, trabajador_id: true } });
  if (!solicitud) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  let autorizado = solicitud.trabajador_id === trabajadorId;
  if (!autorizado) {
    const invitacion = await prisma.solicitud_trabajadores.findFirst({
      where: { solicitud_id: solicitudId, trabajador_id: trabajadorId, estado: { in: ["PENDIENTE", "ACEPTADA"] } },
      select: { id: true },
    });
    autorizado = invitacion !== null;
  }
  if (!autorizado) throw new AppError(403, "Solo el trabajador invitado o asignado puede ver la reputación del cliente", "REPUTACION_NO_AUTORIZADA");
  return reputacion({ rol: "CLIENTE", id: solicitud.cliente_id });
}
