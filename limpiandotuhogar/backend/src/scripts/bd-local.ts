/**
 * BD LOCAL (TiDB en Docker) — doc 22.
 *   npm run bd:local -- iniciar             crea/arranca el contenedor quelimpiamos-tidb (127.0.0.1:4000)
 *   npm run bd:local -- preparar [--recrear] crea quelimpiamos_dev con 000 + 002 + 003 v2 + 004
 *   npm run bd:local -- estado               versión, BD locales y tablas
 *   npm run bd:local -- respaldar            respaldo lógico de quelimpiamos_dev en backups/ (ignorado por git)
 *   npm run bd:local -- migrar               aplica a quelimpiamos_dev (CON datos) las migraciones pendientes
 *                                            (hoy: 004), con respaldo previo y comprobación de que los datos
 *                                            existentes no cambian
 * Nunca se conecta al clúster remoto.
 */
import "./lib/entorno-bd-local";

import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

import {
  activarChecksLocales,
  BD_LOCAL,
  BD_LOCAL_DESARROLLO,
  construirBdLocal,
  MIGRACIONES_LOCALES,
  sentenciasDeArchivo,
  verificarQueEsLocal,
} from "./lib/bd-local";
import { conectar } from "./lib/db-directa";
import { generarRespaldo, huellasDeDatos } from "./lib/respaldo";

type Conexion = Awaited<ReturnType<typeof conectar>>;

/** Conexión a quelimpiamos_dev, comprobando que es el TiDB local y la BD correcta. */
async function conectarDesarrollo(): Promise<Conexion> {
  const c = await conectar(BD_LOCAL_DESARROLLO);
  await verificarQueEsLocal(c.consultar, BD_LOCAL.host);
  const [fila] = await c.consultar("SELECT DATABASE() AS bd");
  if (fila?.bd !== BD_LOCAL_DESARROLLO) {
    await c.cerrar();
    throw new Error(`Conectado a ${String(fila?.bd)} en vez de ${BD_LOCAL_DESARROLLO}: se aborta`);
  }
  return c;
}

/** Respaldo lógico (restore.sql + resumen.json con la huella de cada tabla). Devuelve la carpeta. */
async function respaldar(c: Conexion, etiqueta: string): Promise<string> {
  const respaldo = await generarRespaldo(c.consultar);
  const huellas = await huellasDeDatos(c.consultar);
  const carpeta = path.resolve(process.cwd(), "backups", `${new Date().toISOString().replace(/[:.]/g, "-")}-${BD_LOCAL_DESARROLLO}-${etiqueta}`);
  mkdirSync(carpeta, { recursive: true });
  writeFileSync(path.join(carpeta, "restore.sql"), respaldo.contenido, "utf8");
  writeFileSync(
    path.join(carpeta, "resumen.json"),
    JSON.stringify({ fecha: new Date().toISOString(), bd: respaldo.bd, motor: respaldo.motor, tablas: huellas, sha256: respaldo.sha256 }, null, 2),
    "utf8",
  );
  const filas = Object.values(respaldo.filasPorTabla).reduce((a, b) => a + b, 0);
  console.log(`Respaldo de ${respaldo.bd}: ${Object.keys(respaldo.filasPorTabla).length} tablas, ${filas} filas → ${carpeta}`);
  return carpeta;
}

/** Cada migración local sabe decir si ya está aplicada. */
const YA_APLICADA: Record<(typeof MIGRACIONES_LOCALES)[number], (c: Conexion) => Promise<boolean>> = {
  "004_ciclo_solicitudes.sql": async (c) => {
    const filas = await c.consultar(
      "SELECT COUNT(*) AS n FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'solicitudes' AND COLUMN_NAME = 'inmueble_alias_aplicado'",
    );
    return Number(filas[0]?.n) > 0;
  },
};

async function columnasDe(c: Conexion, tablas: string[]): Promise<Record<string, string[]>> {
  const resultado: Record<string, string[]> = {};
  for (const t of tablas) {
    const filas = await c.consultar("SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION", [t]);
    resultado[t] = filas.map((f) => String(f.c));
  }
  return resultado;
}

async function migrar(): Promise<void> {
  const c = await conectarDesarrollo();
  try {
    const pendientes = [];
    for (const archivo of MIGRACIONES_LOCALES) if (!(await YA_APLICADA[archivo](c))) pendientes.push(archivo);
    if (pendientes.length === 0) {
      console.log(`${BD_LOCAL_DESARROLLO}: sin migraciones pendientes.`);
      return;
    }
    console.log(`${BD_LOCAL_DESARROLLO}: migraciones pendientes: ${pendientes.join(", ")}`);
    await respaldar(c, "antes-de-migrar");
    // Huella de las columnas que existen ANTES (las nuevas no cuentan): deben quedar idénticas.
    const columnasPrevias = await columnasDe(c, ["solicitudes", "solicitud_resoluciones", "admin_permisos", "solicitud_trabajadores"]);
    const antes = await huellasDeDatos(c.consultar);
    for (const archivo of pendientes) {
      const sentencias = await sentenciasDeArchivo(archivo);
      for (const [i, s] of sentencias.entries()) {
        try {
          await c.ejecutar(s);
        } catch (error) {
          throw new Error(`${archivo}, sentencia ${i + 1}: ${(error as Error).message}. El respaldo previo está en backups/.`);
        }
      }
      console.log(`  ${archivo}: ${sentencias.length} sentencias aplicadas.`);
    }
    const despues = await huellasDeDatos(c.consultar, undefined, columnasPrevias);
    const distintas = Object.keys(antes).filter((t) => JSON.stringify(antes[t]) !== JSON.stringify(despues[t]));
    if (distintas.length) throw new Error(`Los datos de ${distintas.join(", ")} cambiaron: revisa y restaura desde backups/`);
    const filas = Object.values(antes).reduce((a, t) => a + t.filas, 0);
    console.log(`Datos existentes sin cambios: ${Object.keys(antes).length} tablas, ${filas} filas con la misma huella.`);
  } finally {
    await c.cerrar();
  }
}

async function conectarServidor() {
  return conectar(null);
}

function docker(args: string[]): string {
  return execFileSync("docker", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

async function esperarTidb(segundos: number) {
  const limite = Date.now() + segundos * 1000;
  let ultimo: unknown;
  while (Date.now() < limite) {
    try {
      const c = await conectarServidor();
      await c.cerrar();
      return;
    } catch (error) {
      ultimo = error;
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  throw new Error(`TiDB local no respondió en ${segundos} s: ${(ultimo as Error)?.message}`);
}

async function main() {
  const [accion, ...resto] = process.argv.slice(2);
  if (accion === "iniciar") {
    const existentes = docker(["ps", "-a", "--filter", `name=^${BD_LOCAL.contenedor}$`, "--format", "{{.Names}} {{.Status}}"]);
    if (!existentes) {
      docker(["run", "-d", "--name", BD_LOCAL.contenedor, "-p", `${BD_LOCAL.host}:${BD_LOCAL.port}:4000`, BD_LOCAL.imagen]);
      console.log(`Contenedor ${BD_LOCAL.contenedor} creado (${BD_LOCAL.imagen}), solo en ${BD_LOCAL.host}:${BD_LOCAL.port}.`);
    } else if (!existentes.includes(" Up ")) {
      docker(["start", BD_LOCAL.contenedor]);
      console.log(`Contenedor ${BD_LOCAL.contenedor} arrancado.`);
    } else {
      console.log(`Contenedor ${BD_LOCAL.contenedor} ya estaba en marcha.`);
    }
    await esperarTidb(90);
    const c = await conectarServidor();
    try {
      console.log("TiDB local:", await verificarQueEsLocal(c.consultar, BD_LOCAL.host));
    } finally {
      await c.cerrar();
    }
    return;
  }
  if (accion === "preparar") {
    const previa = await conectarServidor();
    try {
      await verificarQueEsLocal(previa.consultar, BD_LOCAL.host);
      await activarChecksLocales(previa.ejecutar);
    } finally {
      await previa.cerrar();
    }
    const c = await conectarServidor();
    try {
      console.log("TiDB local:", await verificarQueEsLocal(c.consultar, BD_LOCAL.host));
      const { sentencias } = await construirBdLocal(c.consultar, c.ejecutar, BD_LOCAL_DESARROLLO, { recrear: resto.includes("--recrear") });
      console.log(`BD ${BD_LOCAL_DESARROLLO} lista: ${sentencias} sentencias (000 + 002 v10 + 003 v2 + 004).`);
    } finally {
      await c.cerrar();
    }
    return;
  }
  if (accion === "estado") {
    const c = await conectarServidor();
    try {
      console.log("TiDB local:", await verificarQueEsLocal(c.consultar, BD_LOCAL.host));
      const filas = await c.consultar(
        "SELECT TABLE_SCHEMA AS bd, COUNT(*) AS tablas FROM information_schema.TABLES WHERE TABLE_SCHEMA LIKE 'quelimpiamos\\_%' GROUP BY TABLE_SCHEMA",
      );
      console.log(filas.length ? filas : "Sin BD locales del proyecto.");
      console.log("CHECK activos:", await c.consultar("SELECT @@global.tidb_enable_check_constraint AS global"));
      const checks = await c.consultar(
        // En TiDB los CHECK se listan en TIDB_CHECK_CONSTRAINTS (no en TABLE_CONSTRAINTS).
        "SELECT CONSTRAINT_SCHEMA AS bd, TABLE_NAME AS tabla, COUNT(*) AS checks FROM information_schema.TIDB_CHECK_CONSTRAINTS WHERE CONSTRAINT_SCHEMA LIKE 'quelimpiamos\\_%' GROUP BY CONSTRAINT_SCHEMA, TABLE_NAME ORDER BY 1, 2",
      );
      console.log("CHECK por tabla:", checks.map((f: Record<string, unknown>) => `${String(f.bd)}.${String(f.tabla)}=${String(f.checks)}`).join(" "));
    } finally {
      await c.cerrar();
    }
    return;
  }
  if (accion === "respaldar") {
    const c = await conectarDesarrollo();
    try {
      await respaldar(c, "manual");
    } finally {
      await c.cerrar();
    }
    return;
  }
  if (accion === "migrar") {
    await migrar();
    return;
  }
  console.log("Uso: npm run bd:local -- iniciar | preparar [--recrear] | estado | respaldar | migrar");
  process.exitCode = 1;
}

main().catch((error) => {
  console.error("ERROR:", (error as Error).message);
  process.exit(1);
});
