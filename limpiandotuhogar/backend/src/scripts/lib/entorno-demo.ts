/**
 * Entorno de la demo local. DEBE ser el primer import de demo-local.ts: apunta la app a la BD
 * LOCAL de la demo (TiDB en Docker, 127.0.0.1:4000, quelimpiamos_demo) ANTES de que se cargue
 * src/config/env.ts. Nunca usa el clúster remoto (producción ni queLimpiamos_proyecto).
 */
import { randomBytes } from "node:crypto";

import { config } from "dotenv";

import { BD_LOCAL_DEMO, usarBdLocal } from "./bd-local";

config({ quiet: true });

export const BD_DEMO = BD_LOCAL_DEMO;
const EN_PRODUCCION = process.env.NODE_ENV?.trim() === "production";
if (EN_PRODUCCION) {
  // Misma garantía que antes: en producción los secretos JWT nunca se generan.
  for (const audiencia of ["CLIENTE", "TRABAJADOR", "ADMIN"]) {
    const nombre = `JWT_SECRET_${audiencia}`;
    if (!process.env[nombre]?.trim()) {
      throw new Error(`Falta ${nombre}: en producción los secretos deben ser estables y venir de la configuración; no se generan`);
    }
  }
  throw new Error("La demo local no se ejecuta con NODE_ENV=production");
}
usarBdLocal(BD_DEMO);
process.env.NODE_ENV ||= "development";

/**
 * Secretos JWT que no estaban en .env y se generaron SOLO para esta sesión de demo: al
 * reiniciar se generan otros y las sesiones anteriores dejan de valer.
 */
export const secretosTemporales: string[] = [];
for (const audiencia of ["CLIENTE", "TRABAJADOR", "ADMIN"]) {
  const nombre = `JWT_SECRET_${audiencia}`;
  if (!process.env[nombre]?.trim()) {
    process.env[nombre] = randomBytes(48).toString("base64url");
    secretosTemporales.push(nombre);
  }
}
