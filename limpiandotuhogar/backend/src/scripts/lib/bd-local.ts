/**
 * BD LOCAL de desarrollo y pruebas (doc 22): TiDB v8.5.3 en Docker, solo en 127.0.0.1:4000.
 * Es la ÚNICA base de datos que modifican las pruebas, la demo y las migraciones de la Fase 3a.
 * El clúster remoto (producción y queLimpiamos_proyecto) no se toca.
 *
 * El esquema se construye SOLO con archivos del repositorio, sin leer el clúster remoto:
 *   000_estructura_produccion.sql (DDL de producción, sin datos) → 002 v10 → 003 v2 → 004 (doc 25).
 */
import { readFile } from "node:fs/promises";
import path from "node:path";

import { dividirSentencias } from "./sql";

export const BD_LOCAL = {
  host: "127.0.0.1",
  port: 4000,
  user: "root",
  contenedor: "quelimpiamos-tidb",
  imagen: "pingcap/tidb:v8.5.3",
} as const;

/** Nombres permitidos para las BD locales. Cualquier otro se rechaza. */
export const BD_LOCAL_DESARROLLO = "quelimpiamos_dev";
export const BD_LOCAL_PRUEBAS = "quelimpiamos_pruebas";
export const BD_LOCAL_DEMO = "quelimpiamos_demo";
const NOMBRES_LOCALES = new Set<string>([BD_LOCAL_DESARROLLO, BD_LOCAL_PRUEBAS, BD_LOCAL_DEMO]);

const CARPETA_SQL = path.resolve(__dirname, "../../../../../docs/backend/sql");
export const ARCHIVOS_ESQUEMA = [
  "000_estructura_produccion.sql",
  "002_detalle_solicitud_especialidades_invitaciones.sql",
  "003_v2_notificaciones_permisos_resenas_reportes.sql",
  "004_ciclo_solicitudes.sql",
] as const;

/** Migraciones que se aplican POR ENCIMA de una BD local que ya existe (con datos), en orden. */
export const MIGRACIONES_LOCALES = ["004_ciclo_solicitudes.sql"] as const;

/**
 * Apunta ESTE proceso a la BD local indicada. Debe llamarse ANTES de importar src/config/env
 * (y por lo tanto antes de la app o de Prisma). No modifica .env ni DATABASE_URL del archivo.
 */
export function usarBdLocal(nombre: string): void {
  if (!NOMBRES_LOCALES.has(nombre)) throw new Error(`"${nombre}" no es una BD local permitida`);
  process.env.DATABASE_HOST = BD_LOCAL.host;
  process.env.DATABASE_PORT = String(BD_LOCAL.port);
  process.env.DATABASE_USER = BD_LOCAL.user;
  process.env.DATABASE_PASSWORD = "";
  process.env.DATABASE_NAME = nombre;
  process.env.DATABASE_TLS = "false";
  // Solo para la CLI de Prisma de este proceso (db pull / generate). No se escribe en .env.
  process.env.DATABASE_URL = `mysql://${BD_LOCAL.user}@${BD_LOCAL.host}:${BD_LOCAL.port}/${nombre}`;
}

type Q = (sql: string, params?: unknown[]) => Promise<Record<string, unknown>[]>;

/** Comprueba que la conexión es el TiDB LOCAL (no el Serverless remoto). Lanza si no lo es. */
export async function verificarQueEsLocal(q: Q, host: string): Promise<string> {
  if (!["127.0.0.1", "localhost", "::1"].includes(host)) throw new Error(`El host ${host} no es local`);
  const [fila] = await q("SELECT VERSION() AS v");
  const version = String(fila?.v ?? "");
  if (!version.includes("TiDB")) throw new Error(`El servidor local no es TiDB (${version})`);
  if (version.includes("serverless")) throw new Error("La conexión es al TiDB Serverless remoto: se aborta");
  return version;
}

/**
 * Activa los CHECK en el TiDB LOCAL (variable global, persistente en el contenedor). Las
 * conexiones abiertas DESPUÉS ya los aplican; la que la ejecuta, no.
 */
export async function activarChecksLocales(ejecutar: (sql: string) => Promise<void>): Promise<void> {
  await ejecutar("SET GLOBAL tidb_enable_check_constraint = ON");
}

/** Sentencias de un archivo de docs/backend/sql. */
export async function sentenciasDeArchivo(archivo: string): Promise<string[]> {
  return dividirSentencias(await readFile(path.join(CARPETA_SQL, archivo), "utf8"));
}

/** Sentencias del esquema completo (o de los archivos indicados), en orden (000 → 002 → 003 v2 → 004). */
export async function sentenciasDelEsquema(archivos: readonly string[] = ARCHIVOS_ESQUEMA): Promise<{ archivo: string; sentencias: string[] }[]> {
  const resultado = [];
  for (const archivo of archivos) {
    const texto = await readFile(path.join(CARPETA_SQL, archivo), "utf8");
    resultado.push({ archivo, sentencias: dividirSentencias(texto) });
  }
  return resultado;
}

/**
 * Crea (vacía) la BD local y le aplica el esquema completo. Rechaza nombres no locales y BD con
 * tablas (salvo recrear = true, que la borra primero: solo para BD LOCALES).
 */
export async function construirBdLocal(
  q: Q,
  ejecutar: (sql: string) => Promise<void>,
  nombre: string,
  opciones: { recrear?: boolean; archivos?: readonly string[] } = {},
): Promise<{ sentencias: number }> {
  if (!NOMBRES_LOCALES.has(nombre)) throw new Error(`"${nombre}" no es una BD local permitida`);
  // Igual que producción: los CHECK deben aplicarse. En TiDB la variable es solo GLOBAL y cada
  // conexión la lee al abrirse: un CHECK creado con ella apagada se DESCARTA en silencio. Por eso
  // se exige que ESTA conexión ya la tenga activa (activarChecksLocales + conexión nueva).
  const [sesion] = await q("SELECT @@tidb_enable_check_constraint AS v");
  if (Number(sesion?.v) !== 1) {
    throw new Error("Esta conexión no tiene los CHECK activos: llama a activarChecksLocales() y abre una conexión nueva");
  }
  const existentes = await q("SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = ?", [nombre]);
  if (Number(existentes[0]?.n ?? 0) > 0) {
    if (!opciones.recrear) throw new Error(`La BD local ${nombre} ya tiene tablas (usa --recrear para rehacerla)`);
    await ejecutar(`DROP DATABASE \`${nombre}\``);
  }
  await ejecutar(`CREATE DATABASE IF NOT EXISTS \`${nombre}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`);
  await ejecutar(`USE \`${nombre}\``);
  let total = 0;
  for (const { archivo, sentencias } of await sentenciasDelEsquema(opciones.archivos)) {
    for (const [i, sentencia] of sentencias.entries()) {
      try {
        await ejecutar(sentencia);
        total++;
      } catch (error) {
        throw new Error(`${archivo}, sentencia ${i + 1}: ${(error as Error).message}\n${sentencia.slice(0, 300)}`);
      }
    }
  }
  return { sentencias: total };
}
