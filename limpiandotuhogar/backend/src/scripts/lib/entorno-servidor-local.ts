/**
 * Entorno del SERVIDOR LOCAL para probar las apps en un teléfono (doc 24). DEBE ser el PRIMER
 * import de servidor-local.ts y datos-prueba-local.ts: fija todo ANTES de que se cargue
 * src/config/env.ts, así nunca se usa la conexión remota de .env.
 *
 *  - BD: quelimpiamos_dev en el TiDB LOCAL (Docker, 127.0.0.1:4000, sin TLS). Nunca el clúster remoto.
 *  - Se niega a correr con NODE_ENV=production.
 *  - Secretos JWT y de firma de archivos: si .env no los trae, se generan UNA vez y se guardan en
 *    backend/.local/secretos-servidor-local.json (ignorado por git), para que las sesiones del
 *    teléfono sobrevivan a los reinicios del servidor.
 *  - Fotos de reportes: la carpeta por defecto del backend, fuera del repositorio.
 */
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import { config } from "dotenv";

import { BD_LOCAL_DESARROLLO, usarBdLocal } from "./bd-local";

config({ quiet: true });

if (process.env.NODE_ENV?.trim() === "production") {
  throw new Error("El servidor local de pruebas no se ejecuta con NODE_ENV=production");
}
usarBdLocal(BD_LOCAL_DESARROLLO);
process.env.NODE_ENV = "development";

export const DIRECTORIO_LOCAL = path.resolve(process.cwd(), ".local");
export const ARCHIVO_SECRETOS = path.join(DIRECTORIO_LOCAL, "secretos-servidor-local.json");
const NOMBRES = ["JWT_SECRET_CLIENTE", "JWT_SECRET_TRABAJADOR", "JWT_SECRET_ADMIN", "ALMACENAMIENTO_FIRMA_SECRETO"] as const;

mkdirSync(DIRECTORIO_LOCAL, { recursive: true });
const guardados: Record<string, string> = existsSync(ARCHIVO_SECRETOS) ? JSON.parse(readFileSync(ARCHIVO_SECRETOS, "utf8")) : {};
let cambiaron = false;
for (const nombre of NOMBRES) {
  if (process.env[nombre]?.trim()) continue; // .env manda si ya lo define.
  if (!guardados[nombre]) {
    guardados[nombre] = randomBytes(48).toString("base64url");
    cambiaron = true;
  }
  process.env[nombre] = guardados[nombre];
}
if (cambiaron) writeFileSync(ARCHIVO_SECRETOS, JSON.stringify(guardados, null, 2), { encoding: "utf8", mode: 0o600 });
// Fotos de reportes: la carpeta por defecto del backend (FUERA del repositorio; el backend rechaza
// a propósito una carpeta dentro de git). Se imprime al arrancar.
