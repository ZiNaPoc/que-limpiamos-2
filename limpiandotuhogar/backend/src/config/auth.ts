import "dotenv/config";

import { env } from "./env";

/**
 * Configuración de autenticación (Fase 2). Está separada de env.ts a propósito: los scripts
 * de BD (respaldo, verificación, ensayo) no la importan y siguen funcionando sin secretos JWT.
 * El servidor sí la importa al montar los módulos, así que falla al arrancar si falta algo.
 */

export type Audiencia = "cliente" | "trabajador" | "admin";

function secreto(nombre: string): string {
  const valor = process.env[nombre]?.trim();
  if (!valor) throw new Error(`Falta la variable de entorno ${nombre}`);
  if (valor.length < 32) throw new Error(`${nombre} debe tener al menos 32 caracteres`);
  return valor;
}

function segundos(nombre: string, porDefecto: number): number {
  const crudo = process.env[nombre]?.trim();
  if (!crudo) return porDefecto;
  const valor = Number(crudo);
  if (!Number.isInteger(valor) || valor < 60) {
    throw new Error(`${nombre} debe ser un número entero de segundos (mínimo 60)`);
  }
  return valor;
}

function rondasBcrypt(): number {
  const crudo = process.env.BCRYPT_ROUNDS?.trim();
  const valor = crudo ? Number(crudo) : 12;
  // Solo las pruebas automatizadas pueden bajar el costo (para que corran rápido).
  const minimo = env.nodeEnv === "test" ? 4 : 10;
  if (!Number.isInteger(valor) || valor < minimo || valor > 15) {
    throw new Error(`BCRYPT_ROUNDS debe ser un entero entre ${minimo} y 15`);
  }
  return valor;
}

const secretos: Record<Audiencia, string> = {
  cliente: secreto("JWT_SECRET_CLIENTE"),
  trabajador: secreto("JWT_SECRET_TRABAJADOR"),
  admin: secreto("JWT_SECRET_ADMIN"),
};
// Un token de una audiencia nunca debe validar en otra: los secretos tienen que ser distintos.
if (new Set(Object.values(secretos)).size !== 3) {
  throw new Error("JWT_SECRET_CLIENTE, JWT_SECRET_TRABAJADOR y JWT_SECRET_ADMIN deben ser distintos");
}

function enteroPositivo(nombre: string, porDefecto: number): number {
  const crudo = process.env[nombre]?.trim();
  if (!crudo) return porDefecto;
  const valor = Number(crudo);
  if (!Number.isInteger(valor) || valor < 1) throw new Error(`${nombre} debe ser un entero positivo`);
  return valor;
}

export const authConfig = {
  /**
   * Límite de intentos (decisión del usuario 2026-11-24, diseño en docs/backend/14 §5).
   * Por IP: abuso general. Por cuenta/identificador: bloqueo temporal progresivo, nunca permanente.
   */
  limites: {
    loginPorIp: { limite: enteroPositivo("LIMITE_LOGIN_POR_IP", 30), ventanaMin: 15 },
    registroPorIp: { limite: enteroPositivo("LIMITE_REGISTRO_POR_IP", 10), ventanaMin: 60 },
    passwordPorIp: { limite: enteroPositivo("LIMITE_PASSWORD_POR_IP", 10), ventanaMin: 15 },
    /** Fallos permitidos antes del primer bloqueo. */
    intentosGratis: 5,
    intentosGratisAdmin: 3,
    /** Bloqueos sucesivos en minutos; el último es el tope (nunca permanente). */
    escalonesMin: [1, 5, 15, 30, 60],
    /** Sin fallos durante este tiempo, el contador vuelve a cero. */
    olvidoHoras: 24,
  },

  emisor: "que-limpiamos",
  secretos,
  /** Vigencia de cada sesión. Apps móviles: 7 días; panel admin: 8 horas. */
  expiracionSegundos: {
    cliente: segundos("JWT_EXPIRACION_CLIENTE_SEG", 7 * 24 * 3600),
    trabajador: segundos("JWT_EXPIRACION_TRABAJADOR_SEG", 7 * 24 * 3600),
    admin: segundos("JWT_EXPIRACION_ADMIN_SEG", 8 * 3600),
  } satisfies Record<Audiencia, number>,
  rondasBcrypt: rondasBcrypt(),
  cookieAdmin: {
    nombre: "ql_admin",
    // En producción el panel está en otro dominio: la cookie necesita SameSite=None + Secure.
    secure: env.esProduccion,
    sameSite: env.esProduccion ? ("none" as const) : ("lax" as const),
  },
};
