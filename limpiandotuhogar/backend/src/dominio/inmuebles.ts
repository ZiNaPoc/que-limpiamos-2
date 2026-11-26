import type { inmuebles, inmuebles_tipo } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { AppError } from "../shared/errors/AppError";
import type { Cuerpo } from "../shared/validation/campos";
import type { Tx } from "./auditoria";
import { relojDominio } from "./reloj";

/**
 * «Mis inmuebles» del cliente (doc 25 v2 §3, decisión del 2026-11-25).
 *  - Sin límite de cantidad. Cada uno con nombre (alias, 1–100).
 *  - "Eliminar" = ARCHIVAR (archivado_en): deja de listarse y de poder elegirse. La fila no se borra:
 *    fk_sol_inmueble es ON DELETE RESTRICT y protege las solicitudes que lo usaron.
 *  - Las solicitudes guardan su PROPIA copia (snapshot) de los datos: editar o archivar un inmueble
 *    nunca cambia solicitudes anteriores (ninguna ruta escribe esas columnas después de crearlas).
 *  - Un cliente solo ve y usa SUS inmuebles (otro → 404, sin confirmar que exista).
 */

export const TIPOS_INMUEBLE: readonly inmuebles_tipo[] = ["CASA", "OFICINA", "DEPARTAMENTO"];
export const LIMITES_INMUEBLE = {
  alias: { min: 1, max: 100 },
  direccion: { min: 5, max: 255 },
  habitaciones: { min: 0, max: 20 },
  banos: { min: 0, max: 20 },
  mediosBanos: { min: 0, max: 20 },
  pisos: { min: 1, max: 10 },
} as const;

export type DatosInmueble = { tipo: inmuebles_tipo; direccion: string; habitaciones: number; banos: number; mediosBanos: number; pisos: number };

function invalido(mensaje: string, codigo = "DATOS_INVALIDOS"): AppError {
  return new AppError(400, mensaje, codigo);
}

function entero(cuerpo: Cuerpo, campo: keyof typeof LIMITES_INMUEBLE, etiqueta: string): number {
  const valor = cuerpo[campo];
  const n = typeof valor === "string" && valor.trim() !== "" ? Number(valor) : valor;
  const { min, max } = LIMITES_INMUEBLE[campo];
  if (typeof n !== "number" || !Number.isInteger(n) || n < min || n > max) throw invalido(`${etiqueta} debe ser un número entero de ${min} a ${max}`);
  return n;
}

function textoLimpio(valor: unknown, etiqueta: string, limites: { min: number; max: number }): string {
  if (typeof valor !== "string") throw invalido(`${etiqueta} es obligatorio`);
  const limpio = valor.trim().replace(/\s+/g, " ");
  const largo = [...limpio].length;
  if (largo < limites.min || largo > limites.max) throw invalido(`${etiqueta} debe tener entre ${limites.min} y ${limites.max} caracteres`);
  return limpio;
}

/** Tipo, dirección y medidas (lo que se copia a la solicitud). */
export function leerDatosInmueble(cuerpo: Cuerpo): DatosInmueble {
  const tipo = cuerpo.tipo;
  if (typeof tipo !== "string" || !TIPOS_INMUEBLE.includes(tipo as inmuebles_tipo)) throw invalido(`El tipo de inmueble debe ser ${TIPOS_INMUEBLE.join(", ")}`);
  return {
    tipo: tipo as inmuebles_tipo,
    direccion: textoLimpio(cuerpo.direccion, "La dirección", LIMITES_INMUEBLE.direccion),
    habitaciones: entero(cuerpo, "habitaciones", "Las habitaciones"),
    banos: entero(cuerpo, "banos", "Los baños"),
    mediosBanos: entero(cuerpo, "mediosBanos", "Los medios baños"),
    pisos: entero(cuerpo, "pisos", "Los pisos"),
  };
}

export function leerNombreInmueble(valor: unknown): string {
  return textoLimpio(valor, "El nombre del inmueble", LIMITES_INMUEBLE.alias);
}

export function dtoInmueble(i: inmuebles) {
  return {
    id: i.id,
    nombre: i.alias ?? "",
    tipo: i.tipo,
    direccion: i.direccion,
    habitaciones: i.habitaciones,
    banos: i.banos,
    mediosBanos: i.medios_banos,
    pisos: i.pisos,
    actualizadoEn: i.updated_at.toISOString(),
  };
}

const datosDeFila = (d: DatosInmueble) => ({ tipo: d.tipo, direccion: d.direccion, habitaciones: d.habitaciones, banos: d.banos, medios_banos: d.mediosBanos, pisos: d.pisos });

export async function listarInmuebles(clienteId: number) {
  const filas = await prisma.inmuebles.findMany({ where: { usuario_id: clienteId, archivado_en: null }, orderBy: [{ alias: "asc" }, { id: "asc" }] });
  return filas.map(dtoInmueble);
}

/** Crea un inmueble guardado. Con `tx`, dentro de la transacción de otra operación (crear solicitud). */
export async function crearInmueble(clienteId: number, nombre: string, datos: DatosInmueble, tx: Tx = prisma) {
  const ahora = relojDominio.ahora();
  const fila = await tx.inmuebles.create({ data: { usuario_id: clienteId, alias: nombre, ...datosDeFila(datos), created_at: ahora, updated_at: ahora } });
  return dtoInmueble(fila);
}

/** Un inmueble PROPIO y no archivado, o 404. */
export async function inmueblePropio(clienteId: number, id: number, tx: Tx = prisma) {
  const fila = await tx.inmuebles.findFirst({ where: { id, usuario_id: clienteId, archivado_en: null } });
  if (!fila) throw new AppError(404, "No existe ese inmueble", "INMUEBLE_NO_ENCONTRADO");
  return fila;
}

/** Edición parcial: nombre y/o datos. Nunca toca las solicitudes que ya lo usaron. */
export async function editarInmueble(clienteId: number, id: number, cuerpo: Cuerpo) {
  const actual = await inmueblePropio(clienteId, id);
  const nombre = cuerpo.nombre === undefined ? actual.alias ?? "" : leerNombreInmueble(cuerpo.nombre);
  const mezcla: Cuerpo = {
    tipo: actual.tipo,
    direccion: actual.direccion,
    habitaciones: actual.habitaciones,
    banos: actual.banos,
    mediosBanos: actual.medios_banos,
    pisos: actual.pisos,
    ...Object.fromEntries(Object.entries(cuerpo).filter(([k]) => ["tipo", "direccion", "habitaciones", "banos", "mediosBanos", "pisos"].includes(k))),
  };
  const datos = leerDatosInmueble(mezcla);
  const fila = await prisma.inmuebles.update({ where: { id: actual.id }, data: { alias: nombre, ...datosDeFila(datos), updated_at: relojDominio.ahora() } });
  return dtoInmueble(fila);
}

/** "Eliminar" = archivar (ver arriba). Repetirlo sobre uno ya archivado → 404. */
export async function archivarInmueble(clienteId: number, id: number) {
  const actual = await inmueblePropio(clienteId, id);
  const ahora = relojDominio.ahora();
  await prisma.inmuebles.updateMany({ where: { id: actual.id, archivado_en: null }, data: { archivado_en: ahora, updated_at: ahora } });
  return { id: actual.id, eliminado: true };
}
