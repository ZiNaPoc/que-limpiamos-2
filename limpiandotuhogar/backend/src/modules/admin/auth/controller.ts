import type { RequestHandler } from "express";

import { authConfig } from "../../../config/auth";
import { clavesDeIntento } from "../../../shared/auth/intentos";
import { verificarPassword } from "../../../shared/auth/password";
import { crearControlDeIntentos, exigirSinBloqueo } from "../../../shared/http/limites";
import { AppError } from "../../../shared/errors/AppError";
import { correo, leerCuerpo, passwordIngresada } from "../../../shared/validation/campos";
import { aAdminDto } from "./dto";
import { adminActual } from "./guard";
import { adminAuthRepository as repo } from "./repository";
import { duracionCookieAdminMs, emitirTokenAdmin, NOMBRE_COOKIE_ADMIN, opcionesCookieAdmin } from "./token";

/** Bloqueo progresivo del panel: más estricto (3 fallos gratis). */
export const intentosAdmin = crearControlDeIntentos(authConfig.limites.intentosGratisAdmin);

/**
 * POST /api/admin/auth/login (alias /api/auth/admin/login, el que usa hoy el panel).
 * Responde { usuario } y deja la sesión en una cookie httpOnly: el token nunca va en el body.
 */
export const login: RequestHandler = async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const email = correo(cuerpo);
  const password = passwordIngresada(cuerpo);

  const cuenta = await repo.buscarPorCorreo(email);
  const esAdmin = cuenta?.rol === "ADMIN";
  const claves = clavesDeIntento("admin", { correo: email }, esAdmin ? cuenta.id : undefined);
  exigirSinBloqueo(intentosAdmin, claves, res);
  const passwordOk = await verificarPassword(password, esAdmin ? cuenta.password_hash : null);
  // Mismo mensaje si no existe, no es admin o la contraseña no coincide.
  if (!cuenta || !esAdmin || !passwordOk) {
    intentosAdmin.registrarFallo(claves);
    throw new AppError(401, "Correo o contraseña incorrectos", "CREDENCIALES_INVALIDAS");
  }
  intentosAdmin.registrarExito(claves);
  if (cuenta.estado_cuenta !== "ACTIVA") throw new AppError(403, "Tu cuenta está suspendida", "CUENTA_SUSPENDIDA");

  res.cookie(NOMBRE_COOKIE_ADMIN, emitirTokenAdmin(cuenta), { ...opcionesCookieAdmin(), maxAge: duracionCookieAdminMs() });
  res.json({ usuario: aAdminDto(cuenta) });
};

/** GET /api/admin/auth/session (y /me): comprueba la cookie y devuelve el admin. */
export const sesion: RequestHandler = (_req, res) => {
  res.json({ usuario: aAdminDto(adminActual(res)) });
};

/** POST /api/admin/auth/logout: borra la cookie (aunque ya no sea válida). */
export const logout: RequestHandler = (_req, res) => {
  res.clearCookie(NOMBRE_COOKIE_ADMIN, opcionesCookieAdmin());
  res.status(204).end();
};
