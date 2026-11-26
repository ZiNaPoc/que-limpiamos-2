/**
 * Entorno de las pruebas de integración. DEBE ser el primer import de cada archivo de prueba:
 * apunta la app (y su cliente Prisma) a la BD LOCAL de pruebas (TiDB en Docker, 127.0.0.1:4000)
 * ANTES de que se cargue src/config/env.ts. Ninguna prueba se conecta al clúster remoto.
 */
import { randomBytes } from "node:crypto";

import { config } from "dotenv";

import { BD_LOCAL_PRUEBAS, usarBdLocal } from "../../src/scripts/lib/bd-local";

config({ quiet: true });

/** BD de pruebas LOCAL (se crea sola; doc 22). */
export const BD_PRUEBAS = BD_LOCAL_PRUEBAS;
usarBdLocal(BD_PRUEBAS);

process.env.NODE_ENV = "test";
process.env.CORS_ORIGINS = "http://localhost:5173";
// Secretos aleatorios por ejecución: las pruebas no dependen de .env ni de secretos reales.
for (const audiencia of ["CLIENTE", "TRABAJADOR", "ADMIN"]) {
  process.env[`JWT_SECRET_${audiencia}`] = randomBytes(48).toString("base64url");
}
process.env.BCRYPT_ROUNDS = "4";
// Límites por IP altos para que no interfieran (todas las pruebas salen de 127.0.0.1). Una
// prueba que quiera límites bajos los define ANTES de importar este archivo.
process.env.LIMITE_LOGIN_POR_IP ??= "1000";
process.env.LIMITE_REGISTRO_POR_IP ??= "1000";
process.env.LIMITE_PASSWORD_POR_IP ??= "1000";
// Almacenamiento de archivos de las pruebas: carpeta temporal propia (no la de la demo).
process.env.ALMACENAMIENTO_LOCAL_DIR ??= `${process.env.TEMP ?? process.env.TMPDIR ?? "/tmp"}/quelimpiamos-pruebas-${process.pid}`;
process.env.ALMACENAMIENTO_FIRMA_SECRETO ??= randomBytes(48).toString("base64url");

export const ORIGEN_PANEL = "http://localhost:5173";
