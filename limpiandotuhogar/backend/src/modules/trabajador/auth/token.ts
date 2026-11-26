import { authConfig } from "../../../config/auth";
import { firmarToken, verificarToken } from "../../../shared/auth/jwt";
import { versionDePassword } from "../../../shared/auth/password";

/** Tokens de la audiencia TRABAJADOR: secreto propio y aud = "trabajador". */
const opciones = {
  secreto: authConfig.secretos.trabajador,
  audiencia: "trabajador",
  emisor: authConfig.emisor,
};

/** Solo se emite para cuentas con contraseña (password_hash no NULL). */
export function emitirTokenTrabajador(t: { id: number; password_hash: string }): string {
  return firmarToken(
    { sub: String(t.id), pwv: versionDePassword(t.password_hash) },
    { ...opciones, expiraEnSegundos: authConfig.expiracionSegundos.trabajador },
  );
}

export function verificarTokenTrabajador(token: string) {
  return verificarToken(token, opciones);
}
