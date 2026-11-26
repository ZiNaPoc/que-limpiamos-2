/**
 * Conexión directa (driver mariadb) con la misma configuración TLS que la app,
 * pudiendo elegir la base de datos. La usa el ensayo para trabajar sobre una BD
 * TEMPORAL sin tocar la de producción.
 */
import mariadb from "mariadb";

import { env } from "../../config/env";

export type Fila = Record<string, unknown>;
export type Consulta = <T extends Fila = Fila>(sql: string, params?: unknown[]) => Promise<T[]>;

/** Prefijo obligatorio de cualquier BD que el ensayo pueda crear, modificar o borrar. */
export const PREFIJO_BD_ENSAYO = "queLimpiamos_ensayo_";
const PATRON_BD_ENSAYO = /^queLimpiamos_ensayo_\d{14}$/;

export function esBdDeEnsayo(nombre: string): boolean {
  return PATRON_BD_ENSAYO.test(nombre) && nombre !== env.db.name;
}

/**
 * BD YA EXISTENTE que el usuario autorizó para el ensayo (variable ENSAYO_DATABASE_NAME).
 * Solo se aceptan nombres de ensayo, la shadow y queLimpiamos_proyecto; nunca producción. Además el
 * ensayo exige que esté VACÍA al empezar y la deja vacía al terminar.
 */
export function esBdExistentePermitidaParaEnsayo(nombre: string): boolean {
  return (
    nombre !== env.db.name &&
    (nombre.startsWith("queLimpiamos_ensayo") ||
      nombre === "queLimpiamos_shadow" ||
      // Autorizada por el usuario el 2026-11-24 como BD de pruebas (estaba vacía).
      nombre === "queLimpiamos_proyecto")
  );
}

export async function conectar(baseDeDatos: string | null) {
  const conexion = await mariadb.createConnection({
    host: env.db.host,
    port: env.db.port,
    user: env.db.user,
    password: env.db.password,
    ...(baseDeDatos ? { database: baseDeDatos } : {}),
    connectTimeout: 15_000,
    // TLS siempre, salvo la BD LOCAL de desarrollo/pruebas (env.db.tls solo es false en localhost).
    ...(env.db.tls ? { ssl: { minVersion: "TLSv1.2", rejectUnauthorized: true } } : {}),
  });

  const consultar: Consulta = async <T extends Fila = Fila>(sql: string, params: unknown[] = []) => {
    const resultado: unknown = await conexion.query(sql, params);
    return (Array.isArray(resultado) ? resultado : []) as T[];
  };

  return {
    consultar,
    /** Ejecuta una sentencia que no devuelve filas (DDL/DML). */
    ejecutar: async (sql: string, params: unknown[] = []) => {
      await conexion.query(sql, params);
    },
    cerrar: () => conexion.end(),
  };
}

/** Quita de un texto cualquier aparición de las credenciales (para logs de procesos hijos). */
export function ocultarSecretos(texto: string): string {
  let limpio = texto;
  for (const secreto of [env.db.password, encodeURIComponent(env.db.password), env.db.user]) {
    if (secreto) limpio = limpio.split(secreto).join("***");
  }
  return limpio;
}

/** URL para la CLI de Prisma apuntando a otra BD. Nunca se imprime. */
export function urlParaBd(baseDeDatos: string): string {
  const u = encodeURIComponent(env.db.user);
  const p = encodeURIComponent(env.db.password);
  return `mysql://${u}:${p}@${env.db.host}:${env.db.port}/${encodeURIComponent(baseDeDatos)}?sslaccept=strict`;
}
