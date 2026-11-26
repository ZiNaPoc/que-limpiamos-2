import { createHash } from "node:crypto";

import bcrypt from "bcryptjs";

import { authConfig } from "../../config/auth";

/**
 * Contraseñas con bcrypt (librería bcryptjs, JS puro: no necesita compilación nativa en
 * Render, decisión D8). Es compatible con los hashes $2a$/$2b$ que generó la librería nativa.
 */

export const PASSWORD_MIN_CARACTERES = 8;
/** bcrypt solo usa los primeros 72 bytes: se rechaza lo que pase de ahí en vez de truncar. */
export const PASSWORD_MAX_BYTES = 72;

export function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, authConfig.rondasBcrypt);
}

let hashFicticio: Promise<string> | undefined;

/**
 * Compara la contraseña con el hash. Si la cuenta no existe o no tiene contraseña, compara
 * igual contra un hash ficticio: así tarda lo mismo y no revela qué cuentas existen.
 */
export async function verificarPassword(password: string, hash: string | null | undefined): Promise<boolean> {
  if (!hash) {
    hashFicticio ??= bcrypt.hash("cuenta-inexistente", authConfig.rondasBcrypt);
    await bcrypt.compare(password, await hashFicticio);
    return false;
  }
  try {
    return await bcrypt.compare(password, hash);
  } catch {
    return false;
  }
}

/**
 * Huella corta del hash guardado. Va dentro del token: al cambiar la contraseña cambia la
 * huella y todos los tokens anteriores dejan de valer (sin tabla de sesiones).
 */
export function versionDePassword(hash: string): string {
  return createHash("sha256").update(hash).digest("base64url").slice(0, 16);
}
