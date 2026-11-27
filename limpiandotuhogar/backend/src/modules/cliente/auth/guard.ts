import type { RequestHandler, Response } from "express";

import type { usuarios } from "../../../../generated/prisma/client";
import { leerBearer } from "../../../shared/auth/jwt";
import { versionDePassword } from "../../../shared/auth/password";
import { AppError } from "../../../shared/errors/AppError";
import { clienteAuthRepository } from "./repository";
import { verificarTokenCliente } from "./token";

/**
 * Exige un token Bearer de la audiencia CLIENTE. En cada petición comprueba en la BD que la
 * cuenta exista, siga siendo CLIENTE, no esté suspendida y no haya cambiado de contraseña.
 * Deja la cuenta en res.locals (leerla con clienteActual).
 */
export const requireCliente: RequestHandler = async (req, res, next) => {
  const token = leerBearer(req.headers.authorization);
  if (!token) throw new AppError(401, "Inicia sesión para continuar", "NO_AUTENTICADO");

  const verificado = verificarTokenCliente(token);
  if (!verificado.ok) {
    throw verificado.motivo === "EXPIRADO"
      ? new AppError(401, "Tu sesión expiró, vuelve a iniciar sesión", "SESION_EXPIRADA")
      : new AppError(401, "Sesión no válida", "TOKEN_INVALIDO");
  }

  const id = Number(verificado.datos.sub);
  const cuenta = Number.isSafeInteger(id) && id > 0 ? await clienteAuthRepository.buscarPorId(id) : null;
  if (!cuenta || cuenta.rol !== "CLIENTE") throw new AppError(401, "Sesión no válida", "TOKEN_INVALIDO");
  if (versionDePassword(cuenta.password_hash) !== verificado.datos.pwv) {
    throw new AppError(401, "Tu contraseña cambió, vuelve a iniciar sesión", "SESION_EXPIRADA");
  }
  if (cuenta.estado_cuenta !== "ACTIVA") throw new AppError(403, "Tu cuenta está suspendida", "CUENTA_SUSPENDIDA");

  res.locals.cliente = cuenta;
  next();
};

/** La cuenta del cliente autenticado (solo en rutas protegidas por requireCliente). */
export function clienteActual(res: Response): usuarios {
  const cuenta = res.locals.cliente as usuarios | undefined;
  if (!cuenta) throw new Error("clienteActual() usado en una ruta sin requireCliente");
  return cuenta;
}
