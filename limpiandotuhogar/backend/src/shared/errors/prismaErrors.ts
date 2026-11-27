import { Prisma } from "../../../generated/prisma/client";
import { AppError } from "./AppError";

/**
 * Traduce errores conocidos de Prisma a AppError genéricos.
 * Los módulos pueden capturar antes P2002 para dar mensajes más específicos.
 */
export function traducirErrorPrisma(error: unknown): unknown {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError)) return error;

  switch (error.code) {
    case "P2002": // unique
      return new AppError(409, "Ya existe un registro con esos datos", "DUPLICADO");
    case "P2003": // llave foránea
      return new AppError(400, "Un registro relacionado no existe o está en uso", "RELACION_INVALIDA");
    case "P2025": // no encontrado en update/delete
      return new AppError(404, "No se encontró el registro", "NO_ENCONTRADO");
    default:
      return error;
  }
}
