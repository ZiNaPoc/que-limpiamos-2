import "dotenv/config";

import { randomBytes } from "node:crypto";
import os from "node:os";
import path from "node:path";

import { env } from "./env";

/**
 * Configuración del almacenamiento de archivos (D5, versión gratuita para desarrollo).
 *
 * ALMACENAMIENTO_DRIVER       "local" (única opción por ahora; "s3" queda preparado en la interfaz)
 * ALMACENAMIENTO_LOCAL_DIR    carpeta PRIVADA fuera del repositorio y de cualquier carpeta pública.
 *                             Por defecto: <home>/.quelimpiamos/almacenamiento
 * ALMACENAMIENTO_FIRMA_SECRETO secreto (32+ caracteres) para firmar las URLs temporales. Si falta,
 *                             se genera uno al arrancar (las URLs dejan de valer al reiniciar).
 * ALMACENAMIENTO_MAX_MB       tamaño máximo por archivo (por defecto 5).
 *
 * ⚠ En Render el disco del servicio NO es persistente: se borra en cada deploy o reinicio.
 *   El driver local sirve para desarrollo y demostraciones, NO para producción.
 */

function entero(nombre: string, porDefecto: number, minimo: number, maximo: number): number {
  const crudo = process.env[nombre]?.trim();
  if (!crudo) return porDefecto;
  const valor = Number(crudo);
  if (!Number.isInteger(valor) || valor < minimo || valor > maximo) {
    throw new Error(`${nombre} debe ser un entero entre ${minimo} y ${maximo}`);
  }
  return valor;
}

const driver = process.env.ALMACENAMIENTO_DRIVER?.trim() || "local";
if (driver !== "local") {
  throw new Error(`ALMACENAMIENTO_DRIVER="${driver}" no está implementado (solo "local" por ahora)`);
}

const secretoConfigurado = process.env.ALMACENAMIENTO_FIRMA_SECRETO?.trim();
if (secretoConfigurado && secretoConfigurado.length < 32) {
  throw new Error("ALMACENAMIENTO_FIRMA_SECRETO debe tener al menos 32 caracteres");
}
// En producción los secretos deben ser ESTABLES: nunca se generan solos (si cambiaran en cada
// reinicio, las URLs temporales emitidas dejarían de valer de golpe).
if (!secretoConfigurado && env.esProduccion) {
  throw new Error("ALMACENAMIENTO_FIRMA_SECRETO es obligatorio en producción (32+ caracteres y estable); no se genera automáticamente");
}

export const almacenamientoConfig = {
  driver: "local" as const,
  directorioLocal: path.resolve(process.env.ALMACENAMIENTO_LOCAL_DIR?.trim() || path.join(os.homedir(), ".quelimpiamos", "almacenamiento")),
  secretoFirma: secretoConfigurado || randomBytes(48).toString("base64url"),
  secretoGenerado: !secretoConfigurado,
  maxBytes: entero("ALMACENAMIENTO_MAX_MB", 5, 1, 20) * 1024 * 1024,
  /** Vigencia de las URLs temporales (segundos). */
  segundosUrl: { identidad: 60, otros: 300, maximo: 900 },
};

if (env.esProduccion) {
  console.warn(
    "⚠ ALMACENAMIENTO LOCAL en producción: en Render el disco NO es persistente (se pierde en cada deploy o reinicio). " +
      "Úsalo solo para demostraciones; para producción hay que migrar a un almacenamiento compatible con S3.",
  );
}
