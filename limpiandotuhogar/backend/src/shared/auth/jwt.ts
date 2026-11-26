import jwt from "jsonwebtoken";

/**
 * Firma y verificación de tokens. No conoce audiencias concretas: cada módulo le pasa su
 * secreto, su audiencia (`aud`) y el emisor (`iss`). Solo se acepta HS256.
 */

export type OpcionesToken = { secreto: string; audiencia: string; emisor: string };

export type DatosToken = {
  /** id de la cuenta (usuarios.id o trabajadores.id) como texto. */
  sub: string;
  /** Versión de la contraseña (ver password.ts): si cambia, el token deja de valer. */
  pwv: string;
};

export function firmarToken(datos: DatosToken, opciones: OpcionesToken & { expiraEnSegundos: number }): string {
  return jwt.sign({ pwv: datos.pwv }, opciones.secreto, {
    algorithm: "HS256",
    audience: opciones.audiencia,
    issuer: opciones.emisor,
    subject: datos.sub,
    expiresIn: opciones.expiraEnSegundos,
  });
}

export type TokenVerificado = { ok: true; datos: DatosToken } | { ok: false; motivo: "EXPIRADO" | "INVALIDO" };

export function verificarToken(token: string, opciones: OpcionesToken): TokenVerificado {
  try {
    const carga = jwt.verify(token, opciones.secreto, {
      algorithms: ["HS256"],
      audience: opciones.audiencia,
      issuer: opciones.emisor,
    });
    if (typeof carga !== "object" || typeof carga.sub !== "string" || typeof carga.pwv !== "string") {
      return { ok: false, motivo: "INVALIDO" };
    }
    return { ok: true, datos: { sub: carga.sub, pwv: carga.pwv } };
  } catch (error) {
    return { ok: false, motivo: error instanceof jwt.TokenExpiredError ? "EXPIRADO" : "INVALIDO" };
  }
}

/** Lee `Authorization: Bearer <token>`. Devuelve null si no viene o tiene otro formato. */
export function leerBearer(cabecera: string | undefined): string | null {
  if (!cabecera) return null;
  const [tipo, token, ...resto] = cabecera.trim().split(/\s+/);
  if (resto.length || !token || tipo?.toLowerCase() !== "bearer") return null;
  return token;
}
