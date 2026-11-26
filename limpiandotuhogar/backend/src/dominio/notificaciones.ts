import type { notificaciones_tipo, notificaciones_trabajador_tipo } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { AppError } from "../shared/errors/AppError";
import type { Tx } from "./auditoria";
import { relojDominio } from "./reloj";

/**
 * Avisos a clientes (notificaciones) y a trabajadores (notificaciones_trabajador) — D60.
 *  - Cada aviso lleva una `clave_evento` ÚNICA por destinatario (UNIQUE en la BD): repetir la misma
 *    operación o la tarea periódica NO duplica el aviso (INSERT IGNORE vía skipDuplicates).
 *  - Se crean dentro de la MISMA transacción que el cambio que los origina.
 *  - Convención de la clave: `<TIPO>:sol:<id>[:<detalle>]` (doc 13).
 */

const MAX_TITULO = 100;
const MAX_MENSAJE = 255;
const recortar = (texto: string, max: number) => ([...texto].length > max ? [...texto].slice(0, max - 1).join("") + "…" : texto);

export type Aviso<T> = { tipo: T; clave: string; titulo: string; mensaje: string; solicitudId: number | null };

export async function avisarCliente(tx: Tx, usuarioId: number, aviso: Aviso<notificaciones_tipo>): Promise<void> {
  await tx.notificaciones.createMany({
    data: [
      {
        usuario_id: usuarioId,
        solicitud_id: aviso.solicitudId,
        tipo: aviso.tipo,
        clave_evento: aviso.clave,
        titulo: recortar(aviso.titulo, MAX_TITULO),
        mensaje: recortar(aviso.mensaje, MAX_MENSAJE),
        created_at: relojDominio.ahora(),
      },
    ],
    skipDuplicates: true,
  });
}

export async function avisarTrabajador(tx: Tx, trabajadorId: number, aviso: Aviso<notificaciones_trabajador_tipo>): Promise<void> {
  await tx.notificaciones_trabajador.createMany({
    data: [
      {
        trabajador_id: trabajadorId,
        solicitud_id: aviso.solicitudId,
        tipo: aviso.tipo,
        clave_evento: aviso.clave,
        titulo: recortar(aviso.titulo, MAX_TITULO),
        mensaje: recortar(aviso.mensaje, MAX_MENSAJE),
        created_at: relojDominio.ahora(),
      },
    ],
    skipDuplicates: true,
  });
}

export type Destinatario = { rol: "CLIENTE"; id: number } | { rol: "TRABAJADOR"; id: number };

function dto(n: { id: number; solicitud_id: number | null; tipo: string; titulo: string; mensaje: string; leida_en: Date | null; created_at: Date }) {
  return { id: n.id, solicitudId: n.solicitud_id, tipo: n.tipo, titulo: n.titulo, mensaje: n.mensaje, leida: n.leida_en !== null, fecha: n.created_at.toISOString() };
}

/** Los avisos del usuario (los 100 más recientes) y cuántos no ha leído. */
export async function misNotificaciones(d: Destinatario) {
  if (d.rol === "CLIENTE") {
    const [filas, noLeidas] = await Promise.all([
      prisma.notificaciones.findMany({ where: { usuario_id: d.id }, orderBy: [{ created_at: "desc" }, { id: "desc" }], take: 100 }),
      prisma.notificaciones.count({ where: { usuario_id: d.id, leida_en: null } }),
    ]);
    return { noLeidas, notificaciones: filas.map(dto) };
  }
  const [filas, noLeidas] = await Promise.all([
    prisma.notificaciones_trabajador.findMany({ where: { trabajador_id: d.id }, orderBy: [{ created_at: "desc" }, { id: "desc" }], take: 100 }),
    prisma.notificaciones_trabajador.count({ where: { trabajador_id: d.id, leida_en: null } }),
  ]);
  return { noLeidas, notificaciones: filas.map(dto) };
}

/** Marca UN aviso propio como leído (otro → 404). Repetirlo no cambia la fecha. */
export async function marcarLeida(d: Destinatario, id: number) {
  const ahora = relojDominio.ahora();
  if (d.rol === "CLIENTE") {
    const n = await prisma.notificaciones.findFirst({ where: { id, usuario_id: d.id }, select: { id: true } });
    if (!n) throw new AppError(404, "No existe ese aviso", "AVISO_NO_ENCONTRADO");
    await prisma.notificaciones.updateMany({ where: { id, usuario_id: d.id, leida_en: null }, data: { leida_en: ahora } });
  } else {
    const n = await prisma.notificaciones_trabajador.findFirst({ where: { id, trabajador_id: d.id }, select: { id: true } });
    if (!n) throw new AppError(404, "No existe ese aviso", "AVISO_NO_ENCONTRADO");
    await prisma.notificaciones_trabajador.updateMany({ where: { id, trabajador_id: d.id, leida_en: null }, data: { leida_en: ahora } });
  }
  return { id, leida: true };
}

/** Marca como leídos todos los avisos propios. */
export async function marcarTodasLeidas(d: Destinatario) {
  const ahora = relojDominio.ahora();
  const r =
    d.rol === "CLIENTE"
      ? await prisma.notificaciones.updateMany({ where: { usuario_id: d.id, leida_en: null }, data: { leida_en: ahora } })
      : await prisma.notificaciones_trabajador.updateMany({ where: { trabajador_id: d.id, leida_en: null }, data: { leida_en: ahora } });
  return { marcadas: r.count };
}
