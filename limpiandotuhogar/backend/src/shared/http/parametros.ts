import type { Request } from "express";

import { AppError } from "../errors/AppError";

/** Id numérico positivo de la ruta (p. ej. :id). Si no lo es, 404 (como una ruta que no existe). */
export function idDeRuta(req: Request, nombre = "id"): number {
  const crudo = req.params[nombre];
  const id = Number(crudo);
  if (typeof crudo !== "string" || !/^\d+$/.test(crudo) || !Number.isSafeInteger(id) || id <= 0) {
    throw new AppError(404, "No existe ese recurso", "NO_ENCONTRADO");
  }
  return id;
}

/** Entero positivo opcional de la query string (filtros). */
export function enteroDeQuery(req: Request, nombre: string): number | undefined {
  const crudo = req.query[nombre];
  if (crudo === undefined || crudo === "") return undefined;
  const id = Number(crudo);
  if (typeof crudo !== "string" || !Number.isSafeInteger(id) || id <= 0) {
    throw new AppError(400, `El filtro ${nombre} no es válido`, "FILTRO_INVALIDO");
  }
  return id;
}

/** Texto opcional de la query string restringido a una lista de valores. */
export function opcionDeQuery<T extends string>(req: Request, nombre: string, opciones: readonly T[]): T | undefined {
  const crudo = req.query[nombre];
  if (crudo === undefined || crudo === "") return undefined;
  if (typeof crudo !== "string" || !opciones.includes(crudo as T)) {
    throw new AppError(400, `El filtro ${nombre} no es válido`, "FILTRO_INVALIDO");
  }
  return crudo as T;
}
