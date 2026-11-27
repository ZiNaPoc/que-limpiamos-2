import type { CookieOptions } from "express";

import type { usuarios } from "../../../../generated/prisma/client";
import { authConfig } from "../../../config/auth";
import { firmarToken, verificarToken } from "../../../shared/auth/jwt";
import { versionDePassword } from "../../../shared/auth/password";

/** Tokens de la audiencia ADMIN: secreto propio y aud = "admin". Viajan solo en cookie httpOnly. */
const opciones = {
  secreto: authConfig.secretos.admin,
  audiencia: "admin",
  emisor: authConfig.emisor,
};

export const NOMBRE_COOKIE_ADMIN = authConfig.cookieAdmin.nombre;

export function emitirTokenAdmin(u: usuarios): string {
  return firmarToken(
    { sub: String(u.id), pwv: versionDePassword(u.password_hash) },
    { ...opciones, expiraEnSegundos: authConfig.expiracionSegundos.admin },
  );
}

export function verificarTokenAdmin(token: string) {
  return verificarToken(token, opciones);
}

/** Opciones de la cookie de sesión. clearCookie necesita las mismas (salvo maxAge). */
export function opcionesCookieAdmin(): CookieOptions {
  return {
    httpOnly: true,
    secure: authConfig.cookieAdmin.secure,
    sameSite: authConfig.cookieAdmin.sameSite,
    path: "/",
  };
}

export function duracionCookieAdminMs(): number {
  return authConfig.expiracionSegundos.admin * 1000;
}
