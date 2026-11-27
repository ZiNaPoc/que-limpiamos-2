/**
 * Entorno de los scripts de DATOS DE PRUEBA (datos:local y su variante --nube). DEBE ser el PRIMER
 * import: fija la BD antes de cargar src/config/env.ts.
 *
 *  - Por defecto: quelimpiamos_dev en el TiDB LOCAL (Docker, 127.0.0.1:4000).
 *  - Con --nube: la BD de DEMOSTRACIÓN en TiDB Cloud, `queLimpiamos_proyecto` (vacía y autorizada por el
 *    usuario como BD de pruebas el 2026-11-24; la cuenta de la nube no puede crear bases nuevas). Usa el
 *    host, usuario y contraseña de .env, con TLS obligatorio. NUNCA la histórica `queLimpiamos`.
 *  - Se niega a correr con NODE_ENV=production.
 *  - Si .env no trae los secretos JWT (hashPassword carga la configuración de auth), se ponen unos
 *    aleatorios SOLO para este proceso: sembrar datos no emite tokens.
 */
import { randomBytes } from "node:crypto";
import path from "node:path";

import { config } from "dotenv";

import { BD_LOCAL_DESARROLLO, usarBdLocal } from "./bd-local";

config({ quiet: true });

export const BD_DEMO_NUBE = "queLimpiamos_proyecto";
export const DESTINO: "local" | "nube" = process.argv.includes("--nube") ? "nube" : "local";

if (process.env.NODE_ENV?.trim() === "production") throw new Error("Los scripts de datos de prueba no se ejecutan con NODE_ENV=production");

if (DESTINO === "local") {
  usarBdLocal(BD_LOCAL_DESARROLLO);
} else {
  const host = process.env.DATABASE_HOST?.trim() ?? "";
  if (!host || ["127.0.0.1", "localhost", "::1"].includes(host)) throw new Error("--nube: DATABASE_HOST de .env no es la nube");
  process.env.DATABASE_NAME = BD_DEMO_NUBE;
  process.env.DATABASE_TLS = "true";
}
process.env.NODE_ENV = "development";
for (const nombre of ["JWT_SECRET_CLIENTE", "JWT_SECRET_TRABAJADOR", "JWT_SECRET_ADMIN"]) {
  if (!process.env[nombre]?.trim()) process.env[nombre] = randomBytes(48).toString("base64url");
}

export const DIRECTORIO_LOCAL = path.resolve(process.cwd(), ".local");
