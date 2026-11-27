import type { RequestHandler, Response } from "express";

import type { trabajadores } from "../../../../generated/prisma/client";
import { leerBearer } from "../../../shared/auth/jwt";
import { versionDePassword } from "../../../shared/auth/password";
import { AppError } from "../../../shared/errors/AppError";
import { trabajadorAuthRepository } from "./repository";
import { verificarTokenTrabajador } from "./token";

/**
 * Exige un token Bearer de la audiencia TRABAJADOR. En cada petición comprueba en la BD que
 * la cuenta exista, tenga contraseña y no la haya cambiado. Un trabajador INACTIVO sí entra
 * (se desactivó él mismo y debe poder reactivarse); cuando se aplique el SQL 002, la baja
 * administrativa se bloqueará aquí.
 */
export const requireTrabajador: RequestHandler = async (req, res, next) => {
  const token = leerBearer(req.headers.authorization);
  if (!token) throw new AppError(401, "Inicia sesión para continuar", "NO_AUTENTICADO");

  const verificado = verificarTokenTrabajador(token);
  if (!verificado.ok) {
    throw verificado.motivo === "EXPIRADO"
      ? new AppError(401, "Tu sesión expiró, vuelve a iniciar sesión", "SESION_EXPIRADA")
      : new AppError(401, "Sesión no válida", "TOKEN_INVALIDO");
  }

  const id = Number(verificado.datos.sub);
  const cuenta = Number.isSafeInteger(id) && id > 0 ? await trabajadorAuthRepository.buscarPorId(id) : null;
  if (!cuenta?.password_hash) throw new AppError(401, "Sesión no válida", "TOKEN_INVALIDO");
  if (versionDePassword(cuenta.password_hash) !== verificado.datos.pwv) {
    throw new AppError(401, "Tu contraseña cambió, vuelve a iniciar sesión", "SESION_EXPIRADA");
  }

  res.locals.trabajador = cuenta;
  next();
};

/** La cuenta del trabajador autenticado (solo en rutas protegidas por requireTrabajador). */
export function trabajadorActual(res: Response): trabajadores & { password_hash: string } {
  const cuenta = res.locals.trabajador as (trabajadores & { password_hash: string }) | undefined;
  if (!cuenta) throw new Error("trabajadorActual() usado en una ruta sin requireTrabajador");
  return cuenta;
}
