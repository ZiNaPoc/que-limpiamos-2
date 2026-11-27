import type { usuarios } from "../../../../generated/prisma/client";
import { authConfig } from "../../../config/auth";
import { firmarToken, verificarToken } from "../../../shared/auth/jwt";
import { versionDePassword } from "../../../shared/auth/password";

/** Tokens de la audiencia CLIENTE: secreto propio y aud = "cliente". */
const opciones = {
  secreto: authConfig.secretos.cliente,
  audiencia: "cliente",
  emisor: authConfig.emisor,
};

export function emitirTokenCliente(u: usuarios): string {
  return firmarToken(
    { sub: String(u.id), pwv: versionDePassword(u.password_hash) },
    { ...opciones, expiraEnSegundos: authConfig.expiracionSegundos.cliente },
  );
}

export function verificarTokenCliente(token: string) {
  return verificarToken(token, opciones);
}
