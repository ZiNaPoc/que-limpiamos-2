import type { RequestHandler, Response } from "express";

import type { usuarios } from "../../../../generated/prisma/client";
import { versionDePassword } from "../../../shared/auth/password";
import { AppError } from "../../../shared/errors/AppError";
import { adminAuthRepository } from "./repository";
import { NOMBRE_COOKIE_ADMIN, verificarTokenAdmin } from "./token";

/**
 * Exige la cookie de sesión de la audiencia ADMIN. En cada petición comprueba en la BD que la
 * cuenta exista, tenga rol ADMIN, esté ACTIVA y no haya cambiado de contraseña. Es la única
 * puerta de las acciones de admin (p. ej. resolver reportes y ajustes, D62): el id del admin
 * siempre sale de aquí, nunca del body. Deja la cuenta en res.locals (leerla con adminActual).
 */
export const requireAdmin: RequestHandler = async (req, res, next) => {
  const cookies = (req as { cookies?: Record<string, unknown> }).cookies;
  const token = cookies?.[NOMBRE_COOKIE_ADMIN];
  if (typeof token !== "string" || !token) throw new AppError(401, "Inicia sesión para continuar", "NO_AUTENTICADO");

  const verificado = verificarTokenAdmin(token);
  if (!verificado.ok) {
    throw verificado.motivo === "EXPIRADO"
      ? new AppError(401, "Tu sesión expiró, vuelve a iniciar sesión", "SESION_EXPIRADA")
      : new AppError(401, "Sesión no válida", "TOKEN_INVALIDO");
  }

  const id = Number(verificado.datos.sub);
  const cuenta = Number.isSafeInteger(id) && id > 0 ? await adminAuthRepository.buscarPorId(id) : null;
  if (!cuenta || cuenta.rol !== "ADMIN") throw new AppError(401, "Sesión no válida", "TOKEN_INVALIDO");
  if (versionDePassword(cuenta.password_hash) !== verificado.datos.pwv) {
    throw new AppError(401, "Tu contraseña cambió, vuelve a iniciar sesión", "SESION_EXPIRADA");
  }
  if (cuenta.estado_cuenta !== "ACTIVA") throw new AppError(403, "Tu cuenta está suspendida", "CUENTA_SUSPENDIDA");

  res.locals.admin = cuenta;
  next();
};

/** La cuenta del admin autenticado (solo en rutas protegidas por requireAdmin). */
export function adminActual(res: Response): usuarios {
  const cuenta = res.locals.admin as usuarios | undefined;
  if (!cuenta) throw new Error("adminActual() usado en una ruta sin requireAdmin");
  return cuenta;
}
