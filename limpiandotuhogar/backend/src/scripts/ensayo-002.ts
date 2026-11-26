/**
 * Ensayo COMPLETO del SQL 002 en una BD de ensayo: `npm run db:ensayo-002`
 * (o con ENSAYO_DATABASE_NAME=<bd existente y vacía>, p. ej. queLimpiamos_proyecto)
 *
 * Producción (DATABASE_NAME) solo se LEE. Todo lo que escribe ocurre en una BD nueva
 * `queLimpiamos_ensayo_<AAAAMMDDhhmmss>` que se borra al final (salvo `--conservar`).
 *
 *  1. Respaldo de producción (restore.sql + huellas) en backups/<fecha>-ensayo/
 *  2. Crear la BD temporal y RESTAURAR el respaldo en ella
 *  3. Comparar estructura y datos: temporal == producción
 *  4. Verificación previa en la temporal (0/N)
 *  5. Aplicar el SQL 002 en la temporal y verificar (N/N)
 *  6. Introspección (prisma db pull --print) vs schema Prisma previsto
 *  7. Pruebas con el cliente Prisma previsto (restricciones, concurrencia, updated_at…)
 *  8. Limpiar datos de prueba, aplicar el ROLLBACK y comparar de nuevo con producción
 *  9. Borrar la BD temporal
 * Reporte: backups/<fecha>-ensayo/reporte.json (sin secretos).
 */
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { PrismaMariaDb } from "@prisma/adapter-mariadb";

import { env } from "../config/env";
import {
  conectar,
  esBdDeEnsayo,
  esBdExistentePermitidaParaEnsayo,
  ocultarSecretos,
  PREFIJO_BD_ENSAYO,
  urlParaBd,
} from "./lib/db-directa";
import { verificar002 } from "./lib/objetos-002";
import { estructura, generarRespaldo, huellasDeDatos, listarTablas } from "./lib/respaldo";
import { dividirSentencias } from "./lib/sql";

const RAIZ = process.cwd(); // limpiandotuhogar/backend
const SQL_002 = path.resolve(RAIZ, "../../docs/backend/sql/002_detalle_solicitud_especialidades_invitaciones.sql");
const SQL_ROLLBACK = path.resolve(RAIZ, "../../docs/backend/sql/002_rollback.sql");
const SCHEMA_PREVISTO = path.resolve(RAIZ, "../../docs/backend/sql/002_schema_prisma_previsto.prisma");
const CARPETA_PRISMA_ENSAYO = path.resolve(RAIZ, ".ensayo");

type Paso = { paso: string; ok: boolean; detalle: string };
const pasos: Paso[] = [];
function registrar(paso: string, ok: boolean, detalle = "") {
  pasos.push({ paso, ok, detalle });
  console.log(`${ok ? "✔" : "✘"} ${paso}${detalle ? ` — ${detalle}` : ""}`);
}

function sello(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}`;
}

function compararMapas(a: Record<string, unknown>, b: Record<string, unknown>): string[] {
  const dif: string[] = [];
  for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
    if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) dif.push(k);
  }
  return dif;
}

function prismaCli(args: string[], extraEnv: Record<string, string> = {}) {
  const r = spawnSync("npx", ["--no-install", "prisma", ...args], {
    cwd: RAIZ,
    env: { ...process.env, ...extraEnv },
    encoding: "utf8",
    shell: process.platform === "win32",
    maxBuffer: 50 * 1024 * 1024,
  });
  return { ok: r.status === 0, stdout: r.stdout ?? "", salida: ocultarSecretos(`${r.stdout ?? ""}\n${r.stderr ?? ""}`) };
}

/** Modelos (campos escalares con tipo) y enums de un schema Prisma, para comparar. */
function resumenSchema(texto: string) {
  const bloques = [...texto.matchAll(/^(model|enum)\s+(\w+)\s*\{([\s\S]*?)^\}/gm)];
  const nombresModelos = new Set(bloques.filter((b) => b[1] === "model").map((b) => b[2] as string));
  const modelos: Record<string, Record<string, string>> = {};
  const enums: Record<string, string[]> = {};
  for (const [, clase, nombre, cuerpo] of bloques) {
    const lineas = (cuerpo ?? "")
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith("//") && !l.startsWith("@@"));
    if (clase === "enum") {
      enums[nombre as string] = lineas.map((l) => l.split(/\s+/)[0] as string);
      continue;
    }
    const campos: Record<string, string> = {};
    for (const l of lineas) {
      const [campo, tipo] = l.split(/\s+/);
      if (!campo || !tipo) continue;
      if (nombresModelos.has(tipo.replace(/[?[\]]/g, ""))) continue; // relación
      campos[campo] = tipo;
    }
    modelos[nombre as string] = campos;
  }
  return { modelos, enums };
}

async function esperarErrorPrisma(fn: () => Promise<unknown>, codigo: string): Promise<boolean> {
  try {
    await fn();
    return false;
  } catch (e) {
    return (e as { code?: string })?.code === codigo;
  }
}

const pausa = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const conservar = process.argv.includes("--conservar");
  // Modo A (por defecto): crear una BD nueva con sello de tiempo y borrarla al final.
  // Modo B: ENSAYO_DATABASE_NAME = BD YA EXISTENTE y VACÍA autorizada por el usuario;
  //         no se crea ni se borra la BD, solo se borran al final las tablas creadas.
  const bdExistente = process.env.ENSAYO_DATABASE_NAME?.trim() || null;
  const nombreEnsayo = bdExistente ?? `${PREFIJO_BD_ENSAYO}${sello()}`;
  const nombreValido = bdExistente ? esBdExistentePermitidaParaEnsayo(nombreEnsayo) : esBdDeEnsayo(nombreEnsayo);
  if (!nombreValido) throw new Error(`"${nombreEnsayo}" no está permitida como BD de ensayo`);
  const carpeta = path.resolve(RAIZ, "backups", `${new Date().toISOString().replace(/[:.]/g, "-")}-ensayo`);
  mkdirSync(carpeta, { recursive: true });

  console.log(`Producción (solo lectura): ${env.db.name}`);
  console.log(`BD del ensayo:             ${nombreEnsayo} (${bdExistente ? "existente, debe estar vacía" : "nueva, temporal"})\n`);

  const prod = await conectar(env.db.name);
  const servidor = await conectar(null);
  // Foto de producción ANTES de empezar, para comprobar al final que no cambió nada.
  const estructuraProdInicial = await estructura(prod.consultar);
  const huellasProdInicial = await huellasDeDatos(prod.consultar);
  let temp: Awaited<ReturnType<typeof conectar>> | null = null;
  let bdCreada = false;
  let prismaEnsayo: { $disconnect: () => Promise<void> } | null = null;

  try {
    // 1. Respaldo de producción
    const tablasOriginales = await listarTablas(prod.consultar);
    const respaldo = await generarRespaldo(prod.consultar);
    const huellasProd = await huellasDeDatos(prod.consultar, tablasOriginales);
    const estructuraProd = await estructura(prod.consultar, tablasOriginales);
    writeFileSync(path.join(carpeta, "restore.sql"), respaldo.contenido, "utf8");
    registrar(
      "1. Respaldo de producción",
      true,
      `${tablasOriginales.length} tablas, ${Object.values(respaldo.filasPorTabla).reduce((a, b) => a + b, 0)} filas, sha256 ${respaldo.sha256.slice(0, 12)}…`,
    );

    // 2. Preparar la BD del ensayo y restaurar
    if (bdExistente) {
      temp = await conectar(nombreEnsayo);
      const [{ bd } = { bd: "" }] = await temp.consultar<{ bd: string }>("SELECT DATABASE() AS bd");
      if (bd !== nombreEnsayo || !esBdExistentePermitidaParaEnsayo(bd)) throw new Error(`La conexión apunta a ${bd}: se aborta`);
      const tablasPrevias = await listarTablas(temp.consultar);
      if (tablasPrevias.length) {
        temp = null;
        throw new Error(`${nombreEnsayo} no está vacía (${tablasPrevias.length} tablas): el ensayo no la toca`);
      }
      bdCreada = true; // a partir de aquí hay que limpiar lo que se cree
      registrar("2a. BD del ensayo existente y vacía", true, nombreEnsayo);
    } else {
      await servidor.ejecutar(
        `CREATE DATABASE \`${nombreEnsayo}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`,
      );
      bdCreada = true;
      temp = await conectar(nombreEnsayo);
      const [{ bd } = { bd: "" }] = await temp.consultar<{ bd: string }>("SELECT DATABASE() AS bd");
      if (!esBdDeEnsayo(bd)) throw new Error(`La conexión temporal apunta a ${bd}: se aborta`);
    }
    const sentenciasRestore = dividirSentencias(respaldo.contenido);
    for (const s of sentenciasRestore) await temp.ejecutar(s);
    registrar("2. Restauración del respaldo en la BD temporal", true, `${sentenciasRestore.length} sentencias`);

    // 3. Comparar temporal vs producción
    const difEstructura = compararMapas(estructuraProd, await estructura(temp.consultar, tablasOriginales));
    const difDatos = compararMapas(huellasProd, await huellasDeDatos(temp.consultar, tablasOriginales));
    registrar(
      "3. Restauración idéntica a producción (estructura y datos)",
      difEstructura.length === 0 && difDatos.length === 0,
      difEstructura.length || difDatos.length
        ? `estructura distinta: [${difEstructura.join(", ")}] · datos distintos: [${difDatos.join(", ")}]`
        : `${tablasOriginales.length} tablas iguales`,
    );

    // 4. Verificación previa
    const antes = await verificar002(temp.consultar);
    registrar(
      "4. Verificación previa en la temporal",
      antes.presentes === 0 && antes.precondicionOk,
      `${antes.presentes}/${antes.total}, precondición updated_at ${antes.precondicionOk ? "OK" : "FALLA"}`,
    );

    // 5. Aplicar 002
    const sentencias002 = dividirSentencias(readFileSync(SQL_002, "utf8"));
    let aplicadas = 0;
    try {
      for (const s of sentencias002) {
        await temp.ejecutar(s);
        aplicadas++;
      }
    } catch (e) {
      const sentencia = sentencias002[aplicadas] ?? "";
      registrar(
        "5. Aplicar SQL 002",
        false,
        `falló la sentencia ${aplicadas + 1}/${sentencias002.length}: ${sentencia.slice(0, 120).replace(/\s+/g, " ")} → ${(e as Error).message}`,
      );
      throw new Error("El 002 falló en la BD temporal");
    }
    const despues = await verificar002(temp.consultar);
    registrar(
      "5. Aplicar SQL 002 y verificar",
      despues.estado === "APLICADO COMPLETO",
      `${aplicadas} sentencias, ${despues.presentes}/${despues.total} objetos`,
    );
    // Se comparan solo las columnas que ya existían en producción: el 002 agrega columnas
    // (en NULL o con DEFAULT) a tablas con filas, como usuarios, y eso no es modificar datos.
    const columnasProd: Record<string, string[]> = {};
    for (const r of await prod.consultar<{ t: string; c: string }>(
      "SELECT TABLE_NAME AS t, COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()",
    )) {
      (columnasProd[r.t] ??= []).push(r.c);
    }
    const huellasTrasAplicar = await huellasDeDatos(temp.consultar, tablasOriginales, columnasProd);
    const datosAlterados = compararMapas(huellasProd, huellasTrasAplicar);
    registrar(
      "5b. El 002 no modificó filas existentes (columnas originales)",
      datosAlterados.length === 0,
      datosAlterados.length ? `cambiaron: ${datosAlterados.join(", ")}` : "huellas de datos iguales",
    );
    const [semillas] = await temp.consultar<Record<string, bigint | number>>(
      `SELECT (SELECT COUNT(*) FROM areas_limpieza) AS areas, (SELECT COUNT(*) FROM servicios_extra) AS extras,
              (SELECT COUNT(*) FROM servicio_calculo) AS calculo, (SELECT COUNT(*) FROM reglas_cargo_cancelacion) AS reglas,
              (SELECT COUNT(*) FROM parametros_negocio) AS parametros`,
    );
    const sem = Object.fromEntries(Object.entries(semillas ?? {}).map(([k, v]) => [k, Number(v)]));
    const reglas = await temp.consultar<{ a: string; h: number; v: string }>(
      "SELECT aplica_a AS a, horas_antes AS h, CAST(valor AS CHAR) AS v FROM reglas_cargo_cancelacion ORDER BY aplica_a",
    );
    const reglasOk = reglas.length === 2 && reglas.every((r) => Number(r.h) === 24 && Number(r.v) === 100);
    registrar(
      "5c. Datos iniciales (áreas, extras, cálculo, reglas al 100 % con 24 h, parámetros)",
      sem.areas === 6 &&
        sem.extras === 5 &&
        sem.calculo === Number(respaldo.filasPorTabla.servicios ?? -1) &&
        sem.parametros === 8 &&
        reglasOk,
      `${JSON.stringify(sem)} reglas=${reglas.map((r) => `${r.a}:${r.h}h:${r.v}`).join(",")}`,
    );

    // 6. Introspección vs schema previsto
    const pull = prismaCli(["db", "pull", "--print"], { DATABASE_URL: urlParaBd(nombreEnsayo) });
    if (!pull.ok) {
      registrar("6. Introspección (prisma db pull --print)", false, pull.salida.slice(0, 400));
    } else {
      writeFileSync(path.join(carpeta, "schema-introspeccionado.prisma"), pull.stdout, "utf8");
      const real = resumenSchema(pull.stdout);
      const previsto = resumenSchema(readFileSync(SCHEMA_PREVISTO, "utf8"));
      const dif: string[] = [];
      for (const m of new Set([...Object.keys(real.modelos), ...Object.keys(previsto.modelos)])) {
        const r = real.modelos[m];
        const p = previsto.modelos[m];
        if (!r || !p) {
          dif.push(`modelo ${m}: ${r ? "sobra en la BD" : "falta en la BD"}`);
          continue;
        }
        for (const c of new Set([...Object.keys(r), ...Object.keys(p)])) {
          if (r[c] !== p[c]) dif.push(`${m}.${c}: BD=${r[c] ?? "—"} previsto=${p[c] ?? "—"}`);
        }
      }
      for (const e of new Set([...Object.keys(real.enums), ...Object.keys(previsto.enums)])) {
        if (JSON.stringify(real.enums[e]) !== JSON.stringify(previsto.enums[e])) {
          dif.push(`enum ${e}: BD=${(real.enums[e] ?? ["—"]).join("|")} previsto=${(previsto.enums[e] ?? ["—"]).join("|")}`);
        }
      }
      writeFileSync(path.join(carpeta, "diferencias-schema.txt"), dif.join("\n") || "(ninguna)", "utf8");
      registrar(
        "6. Introspección de la BD == schema Prisma previsto",
        dif.length === 0,
        dif.length
          ? `${dif.length} diferencias (ver diferencias-schema.txt): ${dif.slice(0, 5).join("; ")}`
          : `${Object.keys(real.modelos).length} modelos y ${Object.keys(real.enums).length} enums coinciden`,
      );
    }

    // 7. Pruebas con el cliente Prisma previsto
    rmSync(CARPETA_PRISMA_ENSAYO, { recursive: true, force: true });
    mkdirSync(CARPETA_PRISMA_ENSAYO, { recursive: true });
    const schemaEnsayo = readFileSync(SCHEMA_PREVISTO, "utf8").replace(
      /output\s*=\s*"\.\.\/generated\/prisma"/,
      'output   = "./generated/prisma"',
    );
    writeFileSync(path.join(CARPETA_PRISMA_ENSAYO, "schema.prisma"), schemaEnsayo, "utf8");
    const gen = prismaCli(["generate", "--schema", ".ensayo/schema.prisma"]);
    registrar("7a. prisma generate con el schema previsto", gen.ok, gen.ok ? "" : gen.salida.slice(0, 400));
    if (!gen.ok) throw new Error("No se pudo generar el cliente previsto");

    const modulo = (await import(
      pathToFileURL(path.join(CARPETA_PRISMA_ENSAYO, "generated", "prisma", "client.ts")).href
    )) as { PrismaClient: new (opciones: unknown) => any };
    const db = new modulo.PrismaClient({
      adapter: new PrismaMariaDb({
        host: env.db.host,
        port: env.db.port,
        user: env.db.user,
        password: env.db.password,
        database: nombreEnsayo,
        connectionLimit: 3,
        connectTimeout: 15_000,
        ssl: { minVersion: "TLSv1.2", rejectUnauthorized: true },
      }),
    });
    prismaEnsayo = db;

    const creados = { usuarios: [] as number[], trabajadores: [] as number[], inmuebles: [] as number[], solicitudes: [] as number[], notificaciones: [] as number[] };
    const prueba = async (nombre: string, fn: () => Promise<boolean | string>) => {
      try {
        const r = await fn();
        registrar(`7. ${nombre}`, r === true, typeof r === "string" ? r : "");
      } catch (e) {
        registrar(`7. ${nombre}`, false, ocultarSecretos((e as Error).message).slice(0, 300));
      }
    };

    const servicio = await db.servicios.findFirst({ orderBy: { id: "asc" }, include: { servicio_calculo: true } });
    await prueba("Lectura de servicios existentes con su fila de cálculo", async () =>
      !!servicio?.servicio_calculo || "el servicio no tiene servicio_calculo",
    );
    await prueba("parametros_negocio = 85 / 10 / 60 / 5 / 30 / 15 / 30 / 0", async () => {
      const p = Object.fromEntries((await db.parametros_negocio.findMany()).map((x: any) => [x.clave, Number(x.valor)]));
      return (
        (p.PORCENTAJE_TRABAJADOR === 85 &&
          p.PORCENTAJE_RETENCION_DEUDA === 10 &&
          p.MARGEN_TRASLADO_MIN === 60 &&
          p.MAX_INVITACIONES_PENDIENTES === 5 &&
          p.MINUTOS_ESPERA_CONFIRMACION === 30 &&
          p.MINUTOS_PLAZO_CLIENTE_EVIDENCIA === 15 &&
          p.MINUTOS_CONFIRMACION_AUTOMATICA === 30 &&
          p.DIAS_ESPERA_PAGO_ADEUDO === 0) ||
        JSON.stringify(p)
      );
    });

    await prueba("Un CLIENTE sin teléfono es rechazado por la BD (CHECK)", async () => {
      try {
        await db.usuarios.create({ data: { nombre_completo: "Sin teléfono", correo: `sin.tel.${Date.now()}@ensayo.test`, password_hash: "x" } });
        return "la BD aceptó un cliente sin teléfono";
      } catch (e) {
        const m = String((e as Error).message ?? "");
        return /chk_usuario_cliente_telefono|check constraint/i.test(m) || `otro error: ${ocultarSecretos(m).slice(0, 160)}`;
      }
    });
    const cliente = await db.usuarios.create({
      data: { nombre_completo: "Cliente Ensayo", correo: `ensayo.${Date.now()}@ensayo.test`, telefono: "9100000001", password_hash: "x" },
    });
    creados.usuarios.push(cliente.id);
    const t1 = await db.trabajadores.create({
      data: { nombre_completo: "Trabajador Ensayo 1", telefono: "9000000001", correo: "t1@ensayo.test", direccion: "x" },
    });
    const t2 = await db.trabajadores.create({
      data: { nombre_completo: "Trabajador Ensayo 2", telefono: "9000000002", correo: "t2@ensayo.test", direccion: "x" },
    });
    creados.trabajadores.push(t1.id, t2.id);
    const inmueble = await db.inmuebles.create({
      data: { usuario_id: cliente.id, alias: "Casa ensayo", direccion: "Calle 1", habitaciones: 2, banos: 1 },
    });
    creados.inmuebles.push(inmueble.id);
    const area = await db.areas_limpieza.findFirst({ where: { nombre: "Sala" } });
    const extra = await db.servicios_extra.findFirst({ orderBy: { id: "asc" } });
    const esp = await db.especialidades.create({ data: { nombre: "Máquina de vapor (ensayo)" } });
    const inicio = new Date("2030-01-07T15:00:00Z"); // lunes 10:00 en America/Cancun
    const solicitud = await db.solicitudes.create({
      data: {
        cliente_id: cliente.id,
        servicio_id: servicio.id,
        servicio_nombre_aplicado: servicio.nombre,
        inmueble_id: inmueble.id,
        inmueble_tipo_aplicado: "CASA",
        habitaciones_aplicado: 2,
        banos_aplicado: 1,
        medios_banos_aplicado: 0,
        pisos_aplicado: 1,
        fecha_hora_programada: inicio,
        duracion_estimada_min: 120,
        fecha_hora_fin_estimada: new Date(inicio.getTime() + 120 * 60_000),
        direccion_servicio: "Calle 1",
        precio_estimado: "700.00",
        porcentaje_trabajador_aplicado: "85.00",
        ganancia_trabajador: "595.00",
        comision_plataforma: "105.00",
        modo_eleccion: "MANUAL",
        solicitud_areas: { create: [{ area_id: area.id, nombre_aplicado: area.nombre }] },
        solicitud_extras: { create: [{ extra_id: extra.id, nombre_aplicado: extra.nombre, precio_aplicado: extra.precio }] },
        solicitud_especialidades: { create: [{ especialidad_id: esp.id, nombre_aplicado: esp.nombre }] },
      },
    });
    creados.solicitudes.push(solicitud.id);
    await prueba("Crear solicitud con snapshot (inmueble, nombres, precio, reparto, duración)", async () => {
      const s = await db.solicitudes.findUnique({ where: { id: solicitud.id }, include: { solicitud_areas: true } });
      return s?.solicitud_areas?.[0]?.nombre_aplicado === "Sala" && Number(s.ganancia_trabajador) === 595 || "snapshot incompleto";
    });

    await prueba("Renombrar un área no altera el nombre guardado en la solicitud", async () => {
      await db.areas_limpieza.update({ where: { id: area.id }, data: { nombre: "Living room (ensayo)" } });
      const sa = await db.solicitud_areas.findFirst({ where: { solicitud_id: solicitud.id } });
      await db.areas_limpieza.update({ where: { id: area.id }, data: { nombre: "Sala" } });
      return sa?.nombre_aplicado === "Sala" || `quedó ${sa?.nombre_aplicado}`;
    });

    const inv1 = await db.solicitud_trabajadores.create({ data: { solicitud_id: solicitud.id, trabajador_id: t1.id, origen: "INVITACION" } });
    const inv2 = await db.solicitud_trabajadores.create({ data: { solicitud_id: solicitud.id, trabajador_id: t2.id, origen: "INVITACION" } });
    await prueba("Columna generada oculta en Prisma (@ignore)", async () =>
      !("aceptada_solicitud_id" in inv1) || "el campo generado es visible",
    );
    await db.solicitud_trabajadores.update({ where: { id: inv1.id }, data: { estado: "ACEPTADA" } });
    await prueba("La BD impide DOS aceptadas en la misma solicitud (P2002)", () =>
      esperarErrorPrisma(() => db.solicitud_trabajadores.update({ where: { id: inv2.id }, data: { estado: "ACEPTADA" } }), "P2002"),
    );
    await prueba("La BD impide invitar dos veces al mismo trabajador a la misma solicitud (P2002)", () =>
      esperarErrorPrisma(
        () => db.solicitud_trabajadores.create({ data: { solicitud_id: solicitud.id, trabajador_id: t1.id, origen: "INVITACION" } }),
        "P2002",
      ),
    );
    // Lecturas de Prisma frente a cambios hechos fuera de Prisma (otra conexión). Se lee
    // varias veces para pasar por distintas conexiones del pool.
    const prismaVeCambiosExternos = async (valor: number) => {
      await temp!.ejecutar("UPDATE servicio_calculo SET precio_por_piso = ? WHERE servicio_id = ?", [valor, servicio.id]);
      const lecturas: number[] = [];
      for (let i = 0; i < 6; i++) {
        const r = await db.servicio_calculo.findUnique({ where: { servicio_id: servicio.id } });
        lecturas.push(Number(r?.precio_por_piso));
      }
      return lecturas.every((v) => v === valor) || `esperado ${valor}, Prisma leyó [${lecturas.join(", ")}]`;
    };
    await prueba("Prisma ve cambios hechos por otra conexión (ANTES de la prueba de concurrencia)", () =>
      prismaVeCambiosExternos(11),
    );

    await prueba("Concurrencia real: dos aceptaciones simultáneas → solo una gana", async () => {
      await db.solicitud_trabajadores.update({ where: { id: inv1.id }, data: { estado: "CERRADA", motivo_cierre: "CAMBIO_A_AUTOMATICA" } });
      const intentos = await Promise.allSettled([
        db.solicitud_trabajadores.update({ where: { id: inv1.id }, data: { estado: "ACEPTADA" } }),
        db.solicitud_trabajadores.update({ where: { id: inv2.id }, data: { estado: "ACEPTADA" } }),
      ]);
      const ganadores = intentos.filter((r) => r.status === "fulfilled").length;
      const aceptadas = await db.solicitud_trabajadores.count({ where: { solicitud_id: solicitud.id, estado: "ACEPTADA" } });
      return (ganadores === 1 && aceptadas === 1) || `ganadores=${ganadores}, aceptadas=${aceptadas}`;
    });

    await prueba("Libro: clave_idempotencia impide registrar dos veces (P2002) y AJUSTE se enlaza", async () => {
      const g = await db.trabajador_movimientos.create({
        data: { trabajador_id: t1.id, cuenta: "POR_COBRAR", tipo: "GANANCIA_SERVICIO", monto: "595.00", saldo_resultante: "595.00", porcentaje_aplicado: "85.00", solicitud_id: solicitud.id, clave_idempotencia: `GANANCIA:sol:${solicitud.id}` },
      });
      const duplicado = await esperarErrorPrisma(
        () => db.trabajador_movimientos.create({ data: { trabajador_id: t1.id, cuenta: "POR_COBRAR", tipo: "GANANCIA_SERVICIO", monto: "595.00", saldo_resultante: "1190.00", clave_idempotencia: `GANANCIA:sol:${solicitud.id}` } }),
        "P2002",
      );
      const ajuste = await db.trabajador_movimientos.create({
        data: { trabajador_id: t1.id, cuenta: "POR_COBRAR", tipo: "AJUSTE", monto: "-595.00", saldo_resultante: "0.00", movimiento_relacionado_id: g.id, clave_idempotencia: `AJUSTE:mov:${g.id}` },
        include: { movimiento_relacionado: true },
      });
      return (duplicado && ajuste.movimiento_relacionado?.id === g.id) || `duplicado=${duplicado}`;
    });

    await prueba("Libro: la comisión de un servicio se registra UNA vez aunque cambie la clave (P2002)", async () => {
      const comision = (clave: string) =>
        db.trabajador_movimientos.create({
          data: { trabajador_id: t1.id, cuenta: "DEUDA", tipo: "COMISION_EFECTIVO", monto: "105.00", saldo_resultante: "105.00", solicitud_id: solicitud.id, clave_idempotencia: clave },
        });
      await comision(`COMISION:sol:${solicitud.id}`);
      return esperarErrorPrisma(() => comision(`COMISION:sol:${solicitud.id}:reintento`), "P2002");
    });

    await prueba("Libro: LIBERACION_SALDO o AJUSTE sin movimiento de origen son rechazados (CHECK)", async () => {
      const resultados: string[] = [];
      for (const tipo of ["LIBERACION_SALDO", "AJUSTE"]) {
        try {
          await db.trabajador_movimientos.create({
            data: { trabajador_id: t1.id, cuenta: "DISPONIBLE", tipo, monto: "1.00", saldo_resultante: "1.00", clave_idempotencia: `${tipo}:sin-origen:${Date.now()}` },
          });
          resultados.push(`${tipo}: aceptado`);
        } catch (e) {
          const m = String((e as Error).message ?? "");
          if (!/chk_mov_referencia_obligatoria|check constraint/i.test(m)) resultados.push(`${tipo}: otro error ${ocultarSecretos(m).slice(0, 120)}`);
        }
      }
      return resultados.length === 0 || resultados.join("; ");
    });

    await prueba("No se puede borrar un trabajador con historial (FK RESTRICT, P2003)", () =>
      esperarErrorPrisma(() => db.trabajadores.delete({ where: { id: t1.id } }), "P2003"),
    );

    await prueba("Baja administrativa + historial de estados del trabajador", async () => {
      const admin = await db.usuarios.findFirst({ where: { rol: "ADMIN" } });
      const t = await db.trabajadores.update({
        where: { id: t2.id },
        data: { estado: "BAJA", baja_en: new Date(), baja_tipo: "ADMINISTRATIVA", baja_motivo: "ensayo" },
      });
      await db.trabajador_estado_historial.create({
        data: { trabajador_id: t2.id, estado_anterior: "ACTIVO", estado_nuevo: "BAJA", tipo: "BAJA_ADMINISTRATIVA", actor: "ADMIN", admin_id: admin?.id ?? null, motivo: "ensayo" },
      });
      const h = await db.trabajador_estado_historial.count({ where: { trabajador_id: t2.id } });
      return (t.estado === "BAJA" && h === 1) || `estado=${t.estado} historial=${h}`;
    });

    await prueba("Varias franjas el mismo día en trabajador_horarios", async () => {
      await db.trabajador_horarios.createMany({
        data: [
          { trabajador_id: t1.id, dia_semana: 1, hora_inicio: new Date("1970-01-01T08:00:00Z"), hora_fin: new Date("1970-01-01T12:00:00Z") },
          { trabajador_id: t1.id, dia_semana: 1, hora_inicio: new Date("1970-01-01T15:00:00Z"), hora_fin: new Date("1970-01-01T19:00:00Z") },
        ],
      });
      return (await db.trabajador_horarios.count({ where: { trabajador_id: t1.id, dia_semana: 1 } })) === 2;
    });

    await prueba("Método de pago por defecto EFECTIVO", async () => {
      const s = await db.solicitudes.findUnique({ where: { id: solicitud.id } });
      return s?.metodo_pago === "EFECTIVO" || String(s?.metodo_pago);
    });

    await prueba("Descuentos: código único, servicios, un uso por solicitud (P2002)", async () => {
      const d = await db.descuentos.create({
        data: {
          nombre: "Ensayo 10 %",
          tipo: "PORCENTAJE",
          valor: "10.00",
          codigo: "ENSAYO10",
          fecha_inicio: new Date("2030-01-01T00:00:00Z"),
          fecha_fin: new Date("2030-12-31T23:59:59Z"),
          limite_usos: 100,
          limite_usos_por_cliente: 1,
          descuento_servicios: { create: [{ servicio_id: servicio.id }] },
        },
      });
      const codigoRepetido = await esperarErrorPrisma(
        () => db.descuentos.create({ data: { nombre: "Otro", tipo: "MONTO_FIJO", valor: "50.00", codigo: "ensayo10", fecha_inicio: new Date(), fecha_fin: new Date() } }),
        "P2002",
      );
      await db.descuento_usos.create({ data: { descuento_id: d.id, solicitud_id: solicitud.id, cliente_id: cliente.id, codigo_aplicado: "ENSAYO10", monto_descontado: "70.00" } });
      const segundoUso = await esperarErrorPrisma(
        () => db.descuento_usos.create({ data: { descuento_id: d.id, solicitud_id: solicitud.id, cliente_id: cliente.id, monto_descontado: "70.00" } }),
        "P2002",
      );
      return (codigoRepetido && segundoUso) || `codigoRepetido(mayúsc/minúsc)=${codigoRepetido} segundoUso=${segundoUso}`;
    });

    await prueba("Prisma ve cambios hechos por otra conexión (DESPUÉS de la prueba de concurrencia)", () =>
      prismaVeCambiosExternos(22),
    );

    await prueba("updated_at con @updatedAt de Prisma", async () => {
      const a = await db.servicio_calculo.findUnique({ where: { servicio_id: servicio.id } });
      await pausa(1_500);
      const b = await db.servicio_calculo.update({ where: { servicio_id: servicio.id }, data: { minutos_por_piso: 1 } });
      return b.updated_at > a.updated_at || `antes=${a.updated_at.toISOString()} después=${b.updated_at.toISOString()}`;
    });

    await prueba("updated_at con ON UPDATE de la BD (UPDATE fuera de Prisma, sin depender del reloj)", async () => {
      await temp!.ejecutar("UPDATE servicio_calculo SET updated_at = '2000-01-01 00:00:00' WHERE servicio_id = ?", [servicio.id]);
      await temp!.ejecutar("UPDATE servicio_calculo SET minutos_por_piso = 2 WHERE servicio_id = ?", [servicio.id]);
      const [fila] = await temp!.consultar<{ u: string }>(
        "SELECT CAST(updated_at AS CHAR) AS u FROM servicio_calculo WHERE servicio_id = ?",
        [servicio.id],
      );
      return (fila?.u ?? "").slice(0, 4) >= "2020" || `quedó ${fila?.u}`;
    });

    await prueba("Adeudo del cliente: origen único, cobro en el siguiente servicio y libro del cobrador", async () => {
      const siguiente = await db.solicitudes.create({
        data: {
          cliente_id: cliente.id,
          servicio_id: servicio.id,
          fecha_hora_programada: new Date("2030-01-14T15:00:00Z"),
          direccion_servicio: "Calle 1",
          precio_estimado: "700.00",
          adeudo_cobrado: "700.00",
        },
      });
      creados.solicitudes.push(siguiente.id);
      // D55 = 0 días: la plataforma pagó la compensación al cancelarse el servicio de origen.
      const adeudo = await db.cliente_adeudos.create({
        data: {
          cliente_id: cliente.id, solicitud_origen_id: solicitud.id, motivo: "CANCELACION_TARDIA", monto: "700.00", estado: "EN_COBRO",
          solicitud_cobro_id: siguiente.id, compensacion_liberada_en: new Date(), compensacion_pagada_por: "PLATAFORMA",
        },
      });
      const origenRepetido = await esperarErrorPrisma(
        () => db.cliente_adeudos.create({ data: { cliente_id: cliente.id, solicitud_origen_id: solicitud.id, motivo: "CANCELACION_TARDIA", monto: "1.00" } }),
        "P2002",
      );
      await db.solicitudes.update({
        where: { id: siguiente.id },
        data: {
          estado: "REALIZADO",
          estado_pago: "PAGADO",
          pago_registrado_en: new Date(),
          pago_registrado_por: "TRABAJADOR",
          trabajador_marco_realizado_en: new Date(),
          cliente_marco_realizado_en: new Date(),
          realizado_en: new Date(),
          realizado_via: "CLIENTE",
          ganancia_liberada_en: new Date(),
        },
      });
      // El cobro recupera lo que ya pagó la plataforma: no se toca la compensación.
      await db.cliente_adeudos.update({
        where: { id: adeudo.id },
        data: { estado: "COBRADO", trabajador_cobro_id: t1.id, cobrado_en: new Date() },
      });
      await db.trabajador_movimientos.create({
        data: {
          trabajador_id: t1.id, cuenta: "DEUDA", tipo: "COBRO_ADEUDO_CLIENTE", monto: "700.00", saldo_resultante: "700.00",
          solicitud_id: siguiente.id, descripcion: `Cobro del adeudo de la solicitud #${solicitud.id}`, clave_idempotencia: `ADEUDO:${adeudo.id}`,
        },
      });
      const leido = await db.cliente_adeudos.findUnique({ where: { id: adeudo.id }, include: { solicitud_origen: true, solicitud_cobro: true } });
      return (
        (origenRepetido &&
          leido?.solicitud_origen?.id === solicitud.id &&
          leido?.solicitud_cobro?.id === siguiente.id &&
          leido?.estado === "COBRADO" &&
          leido?.compensacion_pagada_por === "PLATAFORMA") ||
        `origenRepetido=${origenRepetido} estado=${leido?.estado} pagada_por=${leido?.compensacion_pagada_por}`
      );
    });

    await prueba("Compensación: se libera UNA sola vez (dos intentos simultáneos y uno posterior al cobro del adeudo)", async () => {
      const comp = await db.trabajador_movimientos.create({
        data: {
          trabajador_id: t1.id, cuenta: "POR_COBRAR", tipo: "COMPENSACION_CANCELACION", monto: "595.00", saldo_resultante: "595.00",
          porcentaje_aplicado: "85.00", solicitud_id: solicitud.id, clave_idempotencia: `COMPENSACION:sol:${solicitud.id}`,
        },
      });
      const compensacionRepetida = await esperarErrorPrisma(
        () => db.trabajador_movimientos.create({
          data: { trabajador_id: t1.id, cuenta: "POR_COBRAR", tipo: "COMPENSACION_CANCELACION", monto: "595.00", saldo_resultante: "1190.00", solicitud_id: solicitud.id, clave_idempotencia: `COMPENSACION:sol:${solicitud.id}:otra` },
        }),
        "P2002",
      );
      // Cada liberación es un par (POR_COBRAR − y DISPONIBLE +) que apunta a la compensación.
      const liberar = (quien: string) =>
        db.$transaction([
          db.trabajador_movimientos.create({
            data: { trabajador_id: t1.id, cuenta: "POR_COBRAR", tipo: "LIBERACION_SALDO", monto: "-595.00", saldo_resultante: "0.00", solicitud_id: solicitud.id, movimiento_relacionado_id: comp.id, clave_idempotencia: `LIB:${quien}:${comp.id}:PC` },
          }),
          db.trabajador_movimientos.create({
            data: { trabajador_id: t1.id, cuenta: "DISPONIBLE", tipo: "LIBERACION_SALDO", monto: "595.00", saldo_resultante: "595.00", solicitud_id: solicitud.id, movimiento_relacionado_id: comp.id, clave_idempotencia: `LIB:${quien}:${comp.id}:DI` },
          }),
        ]);
      const intentos = await Promise.allSettled([liberar("CLIENTE"), liberar("PLATAFORMA")]);
      const ganadores = intentos.filter((r) => r.status === "fulfilled").length;
      const perdedorP2002 = intentos.every((r) => r.status === "fulfilled" || (r.reason as { code?: string })?.code === "P2002");
      const tardio = await esperarErrorPrisma(() => liberar("CLIENTE_PAGA_DESPUES"), "P2002");
      const filas = await db.trabajador_movimientos.count({ where: { tipo: "LIBERACION_SALDO", movimiento_relacionado_id: comp.id } });
      return (
        (compensacionRepetida && ganadores === 1 && perdedorP2002 && tardio && filas === 2) ||
        `compensacionRepetida=${compensacionRepetida} ganadores=${ganadores} perdedorP2002=${perdedorP2002} tardio=${tardio} filas=${filas}`
      );
    });

    await prueba("Identidad: una huella por cuenta (cliente y trabajador por separado) y foto de INE borrada", async () => {
      // En la app la huella es un HMAC del CURP normalizado; aquí basta un hash de prueba.
      const huella = createHash("sha256").update(`ensayo-identidad-${Date.now()}`).digest("hex");
      await db.usuarios.update({ where: { id: cliente.id }, data: { identidad_huella: huella, identidad_registrada_en: new Date() } });
      let otraCuentaRechazada = false;
      try {
        const otra = await db.usuarios.create({
          data: { nombre_completo: "Otra cuenta", correo: `otra.${Date.now()}@ensayo.test`, telefono: "9100000002", password_hash: "x", identidad_huella: huella },
        });
        creados.usuarios.push(otra.id);
      } catch (e) {
        otraCuentaRechazada = (e as { code?: string })?.code === "P2002";
      }
      await db.trabajadores.update({ where: { id: t1.id }, data: { identidad_huella: huella, identidad_registrada_en: new Date() } });
      const otroTrabajadorRechazado = await esperarErrorPrisma(
        () => db.trabajadores.update({ where: { id: t2.id }, data: { identidad_huella: huella } }),
        "P2002",
      );
      const doc = await db.documentos_cliente.create({
        data: { usuario_id: cliente.id, tipo: "INE_FRENTE", archivo_url: "https://almacenamiento.invalid/ine-ensayo.jpg" },
      });
      const revisado = await db.documentos_cliente.update({
        where: { id: doc.id },
        data: { estado: "APROBADO", revisado_en: new Date(), archivo_eliminado_en: new Date() },
      });
      return (
        (otraCuentaRechazada && otroTrabajadorRechazado && revisado.archivo_eliminado_en instanceof Date) ||
        `otraCuentaRechazada=${otraCuentaRechazada} otroTrabajadorRechazado=${otroTrabajadorRechazado}`
      );
    });

    await prueba("Confirmación: automática sin pago, evidencia después y pago liberado UNA sola vez", async () => {
      const fin = new Date("2030-01-21T17:00:00Z");
      const s = await db.solicitudes.create({
        data: {
          cliente_id: cliente.id, servicio_id: servicio.id, trabajador_id: t1.id, estado: "EN_PROCESO",
          fecha_hora_programada: new Date(fin.getTime() - 120 * 60_000), duracion_estimada_min: 120, fecha_hora_fin_estimada: fin,
          direccion_servicio: "Calle 1", precio_estimado: "700.00",
        },
      });
      creados.solicitudes.push(s.id);
      // Nadie confirmó: en T+30 se pide a ambos; en T+60 se confirma solo, SIN liberar el pago.
      await db.solicitudes.update({ where: { id: s.id }, data: { confirmacion_solicitada_en: new Date(fin.getTime() + 30 * 60_000) } });
      await db.solicitudes.update({
        where: { id: s.id },
        data: { estado: "REALIZADO", realizado_en: new Date(fin.getTime() + 60 * 60_000), realizado_via: "AUTOMATICO" },
      });
      const sinPago = (await db.solicitudes.findUnique({ where: { id: s.id } }))?.ganancia_liberada_en === null;
      // Después el trabajador sube evidencia y, al mismo tiempo, el cliente confirma.
      await db.evidencias_solicitud.create({
        data: { solicitud_id: s.id, archivo_url: "https://almacenamiento.invalid/evidencia-ensayo.jpg", descripcion: "ensayo" },
      });
      const liberarGanancia = () =>
        db.solicitudes.updateMany({ where: { id: s.id, ganancia_liberada_en: null }, data: { ganancia_liberada_en: new Date() } });
      const r = await Promise.all([liberarGanancia(), liberarGanancia()]);
      const veces = r.reduce((a: number, x: { count: number }) => a + x.count, 0);
      const leida = await db.solicitudes.findUnique({ where: { id: s.id }, include: { evidencias_solicitud: true } });
      return (
        (sinPago &&
          veces === 1 &&
          leida?.realizado_via === "AUTOMATICO" &&
          leida?.ganancia_liberada_en instanceof Date &&
          leida?.evidencias_solicitud.length === 1 &&
          leida?.evidencias_solicitud[0]?.aportada_por === "TRABAJADOR") ||
        `sinPago=${sinPago} veces=${veces} via=${leida?.realizado_via}`
      );
    });

    await prueba("Pago en efectivo: registrarlo genera la comisión UNA vez sin marcar «terminado», aunque ambos lo registren a la vez", async () => {
      const s = await db.solicitudes.create({
        data: {
          cliente_id: cliente.id, servicio_id: servicio.id, trabajador_id: t1.id, estado: "EN_PROCESO",
          fecha_hora_programada: new Date("2030-01-28T15:00:00Z"), direccion_servicio: "Calle 1",
          precio_estimado: "1000.00", ganancia_trabajador: "850.00", comision_plataforma: "150.00",
        },
      });
      creados.solicitudes.push(s.id);
      // Lo que hará el backend: cambiar el estado del pago y, solo si cambió, registrar la comisión.
      const registrarPago = (quien: "CLIENTE" | "TRABAJADOR") =>
        db.$transaction(async (tx: any) => {
          const r = await tx.solicitudes.updateMany({
            where: { id: s.id, estado_pago: "PENDIENTE" },
            data: { estado_pago: "PAGADO", pago_registrado_en: new Date(), pago_registrado_por: quien },
          });
          if (r.count === 0) return "ya estaba registrado";
          await tx.trabajador_movimientos.create({
            data: {
              trabajador_id: t1.id, cuenta: "DEUDA", tipo: "COMISION_EFECTIVO", monto: "150.00", saldo_resultante: "150.00",
              porcentaje_aplicado: "15.00", solicitud_id: s.id, clave_idempotencia: `COMISION:sol:${s.id}:${quien}`,
            },
          });
          return "registrado";
        });
      const intentos = await Promise.allSettled([registrarPago("CLIENTE"), registrarPago("TRABAJADOR")]);
      const resultados = intentos.map((x) => (x.status === "fulfilled" ? x.value : `error ${(x.reason as { code?: string })?.code}`));
      // Aunque el backend se saltara la condición, la BD rechaza una segunda comisión.
      const comisionExtra = await esperarErrorPrisma(
        () => db.trabajador_movimientos.create({
          data: { trabajador_id: t1.id, cuenta: "DEUDA", tipo: "COMISION_EFECTIVO", monto: "150.00", saldo_resultante: "300.00", solicitud_id: s.id, clave_idempotencia: `COMISION:sol:${s.id}:otra` },
        }),
        "P2002",
      );
      const comisiones = await db.trabajador_movimientos.findMany({ where: { solicitud_id: s.id, tipo: "COMISION_EFECTIVO" } });
      const leida = await db.solicitudes.findUnique({ where: { id: s.id } });
      return (
        (resultados.filter((x) => x === "registrado").length === 1 &&
          resultados.filter((x) => x === "ya estaba registrado").length === 1 &&
          comisionExtra &&
          comisiones.length === 1 &&
          Number(comisiones[0]?.monto) === 150 &&
          leida?.estado_pago === "PAGADO" &&
          leida?.estado === "EN_PROCESO" &&
          leida?.trabajador_marco_realizado_en === null) ||
        `resultados=${resultados.join(",")} comisionExtra=${comisionExtra} comisiones=${comisiones.length} pago=${leida?.estado_pago} servicio=${leida?.estado}`
      );
    });

    await prueba("Reportes: bloquean la confirmación automática; la resolución corrige la comisión con AJUSTE sin borrar historial", async () => {
      const fin = new Date("2030-02-04T17:00:00Z");
      const s = await db.solicitudes.create({
        data: {
          cliente_id: cliente.id, servicio_id: servicio.id, trabajador_id: t1.id, estado: "EN_PROCESO",
          fecha_hora_programada: new Date(fin.getTime() - 120 * 60_000), fecha_hora_fin_estimada: fin, direccion_servicio: "Calle 1",
          precio_estimado: "1000.00", estado_pago: "PAGADO", pago_registrado_en: new Date(), pago_registrado_por: "CLIENTE",
          confirmacion_solicitada_en: new Date(fin.getTime() + 30 * 60_000),
        },
      });
      creados.solicitudes.push(s.id);
      const comision = await db.trabajador_movimientos.create({
        data: { trabajador_id: t1.id, cuenta: "DEUDA", tipo: "COMISION_EFECTIVO", monto: "150.00", saldo_resultante: "150.00", solicitud_id: s.id, clave_idempotencia: `COMISION:sol:${s.id}` },
      });
      // Ambas partes reportan y adjuntan evidencia.
      const repTrabajador = await db.solicitud_reportes.create({
        data: { solicitud_id: s.id, reportado_por: "TRABAJADOR", trabajador_id: t1.id, tipo: "PAGO_EN_DISPUTA", descripcion: "No recibí el efectivo" },
      });
      const repCliente = await db.solicitud_reportes.create({
        data: { solicitud_id: s.id, reportado_por: "CLIENTE", cliente_id: cliente.id, tipo: "OTRO", descripcion: "Sí pagué" },
      });
      await db.evidencias_solicitud.createMany({
        data: [
          { solicitud_id: s.id, archivo_url: "https://almacenamiento.invalid/rep-t.jpg", aportada_por: "TRABAJADOR", reporte_id: repTrabajador.id },
          { solicitud_id: s.id, archivo_url: "https://almacenamiento.invalid/rep-c.jpg", aportada_por: "CLIENTE", reporte_id: repCliente.id },
        ],
      });
      // La tarea periódica NO confirma sola una solicitud con reportes sin resolver.
      const autoConfirmadas = await db.$executeRawUnsafe(
        `UPDATE solicitudes SET estado = 'REALIZADO', realizado_via = 'AUTOMATICO', realizado_en = NOW()
         WHERE id = ? AND estado = 'EN_PROCESO'
           AND NOT EXISTS (SELECT 1 FROM solicitud_reportes r WHERE r.solicitud_id = solicitudes.id AND r.estado <> 'RESUELTO')`,
        s.id,
      );
      // El admin resuelve: el servicio sí se hizo, pero el cobro no existió → se corrige la comisión.
      const admin = await db.usuarios.findFirst({ where: { rol: "ADMIN" } });
      const res = await db.solicitud_resoluciones.create({
        data: { solicitud_id: s.id, admin_id: admin?.id ?? null, resultado_servicio: "REALIZADO", resultado_pago: "NO_PAGADO", motivo: "Según las evidencias, el cobro no existió" },
      });
      await db.$transaction([
        db.solicitud_reportes.updateMany({ where: { solicitud_id: s.id, estado: { not: "RESUELTO" } }, data: { estado: "RESUELTO", resolucion_id: res.id } }),
        db.solicitudes.update({
          where: { id: s.id },
          data: { estado_pago: "ANULADO", estado: "REALIZADO", realizado_via: "RESOLUCION_ADMIN", realizado_en: new Date() },
        }),
        db.trabajador_movimientos.create({
          data: {
            trabajador_id: t1.id, cuenta: "DEUDA", tipo: "AJUSTE", monto: "-150.00", saldo_resultante: "0.00", solicitud_id: s.id,
            movimiento_relacionado_id: comision.id, resolucion_id: res.id, descripcion: `Resolución #${res.id}: el cobro no existió`,
            clave_idempotencia: `AJUSTE:res:${res.id}:mov:${comision.id}`,
          },
        }),
      ]);
      const segundoAjuste = await esperarErrorPrisma(
        () => db.trabajador_movimientos.create({
          data: { trabajador_id: t1.id, cuenta: "DEUDA", tipo: "AJUSTE", monto: "-150.00", saldo_resultante: "-150.00", solicitud_id: s.id, movimiento_relacionado_id: comision.id, clave_idempotencia: `AJUSTE:otra:${comision.id}` },
        }),
        "P2002",
      );
      const historial = await db.trabajador_movimientos.findMany({ where: { solicitud_id: s.id }, orderBy: { id: "asc" } });
      const abiertos = await db.solicitud_reportes.count({ where: { solicitud_id: s.id, estado: { not: "RESUELTO" } } });
      const evidencias = await db.evidencias_solicitud.count({ where: { solicitud_id: s.id, reporte_id: { not: null } } });
      const leida = await db.solicitudes.findUnique({ where: { id: s.id } });
      const borrarConReportes = await esperarErrorPrisma(() => db.solicitudes.delete({ where: { id: s.id } }), "P2003");
      return (
        (Number(autoConfirmadas) === 0 &&
          segundoAjuste &&
          historial.length === 2 &&
          historial[0]?.tipo === "COMISION_EFECTIVO" &&
          historial[1]?.resolucion_id === res.id &&
          abiertos === 0 &&
          evidencias === 2 &&
          leida?.estado_pago === "ANULADO" &&
          leida?.realizado_via === "RESOLUCION_ADMIN" &&
          borrarConReportes) ||
        `auto=${autoConfirmadas} segundoAjuste=${segundoAjuste} historial=${historial.length} abiertos=${abiertos} evidencias=${evidencias} pago=${leida?.estado_pago} borrar=${borrarConReportes}`
      );
    });

    await prueba("Confirmación automática con pago presumido (SISTEMA): solo si se inició y sin reportes, una comisión aunque la tarea corra dos veces, y anulable por disputa", async () => {
      const fin = new Date("2030-02-11T17:00:00Z");
      const base = {
        cliente_id: cliente.id, servicio_id: servicio.id, trabajador_id: t1.id,
        fecha_hora_programada: new Date(fin.getTime() - 120 * 60_000), fecha_hora_fin_estimada: fin, direccion_servicio: "Calle 1",
        precio_estimado: "1000.00", ganancia_trabajador: "850.00", confirmacion_solicitada_en: new Date(fin.getTime() + 30 * 60_000),
      };
      const elegible = await db.solicitudes.create({ data: { ...base, estado: "EN_PROCESO" } });
      const noIniciada = await db.solicitudes.create({ data: { ...base, estado: "CONFIRMADO" } });
      const conReporte = await db.solicitudes.create({ data: { ...base, estado: "EN_PROCESO" } });
      const yaPagada = await db.solicitudes.create({
        data: { ...base, estado: "EN_PROCESO", estado_pago: "PAGADO", pago_registrado_en: new Date(), pago_registrado_por: "CLIENTE" },
      });
      creados.solicitudes.push(elegible.id, noIniciada.id, conReporte.id, yaPagada.id);
      await db.trabajador_movimientos.create({
        data: { trabajador_id: t1.id, cuenta: "DEUDA", tipo: "COMISION_EFECTIVO", monto: "150.00", saldo_resultante: "150.00", solicitud_id: yaPagada.id, clave_idempotencia: `COMISION:sol:${yaPagada.id}` },
      });
      await db.solicitud_reportes.create({
        data: { solicitud_id: conReporte.id, reportado_por: "CLIENTE", cliente_id: cliente.id, tipo: "INASISTENCIA" },
      });

      // Lo que hará la tarea periódica con cada solicitud vencida (una transacción por solicitud).
      const confirmarAutomaticamente = (id: number) =>
        db.$transaction(async (tx: any) => {
          const servicioConfirmado = await tx.$executeRawUnsafe(
            `UPDATE solicitudes SET estado = 'REALIZADO', realizado_via = 'AUTOMATICO', realizado_en = NOW()
             WHERE id = ? AND estado = 'EN_PROCESO'
               AND NOT EXISTS (SELECT 1 FROM solicitud_reportes r WHERE r.solicitud_id = solicitudes.id AND r.estado <> 'RESUELTO')`,
            id,
          );
          if (Number(servicioConfirmado) === 0) return "no confirmada";
          const pago = await tx.solicitudes.updateMany({
            where: { id, estado_pago: "PENDIENTE", metodo_pago: "EFECTIVO" },
            data: { estado_pago: "PAGADO", pago_registrado_en: new Date(), pago_registrado_por: "SISTEMA" },
          });
          if (pago.count === 0) return "confirmada (el pago ya estaba registrado)";
          await tx.trabajador_movimientos.create({
            data: {
              trabajador_id: t1.id, cuenta: "DEUDA", tipo: "COMISION_EFECTIVO", monto: "150.00", saldo_resultante: "150.00", porcentaje_aplicado: "15.00",
              solicitud_id: id, descripcion: "Pago en efectivo presumido al confirmarse automáticamente", clave_idempotencia: `COMISION:sol:${id}:sistema`,
            },
          });
          await tx.notificaciones_trabajador.create({
            data: { trabajador_id: t1.id, solicitud_id: id, tipo: "PAGO_EFECTIVO_PRESUMIDO", titulo: "Pago registrado", mensaje: "Si no recibiste el efectivo, repórtalo." },
          });
          return "confirmada con pago presumido";
        });

      const dobles = await Promise.allSettled([confirmarAutomaticamente(elegible.id), confirmarAutomaticamente(elegible.id)]);
      const rDobles = dobles.map((x) => (x.status === "fulfilled" ? x.value : `error ${(x.reason as { code?: string })?.code ?? (x.reason as Error)?.message}`)).sort();
      const rNoIniciada = await confirmarAutomaticamente(noIniciada.id);
      const rConReporte = await confirmarAutomaticamente(conReporte.id);
      const rYaPagada = await confirmarAutomaticamente(yaPagada.id);
      const comisiones = (id: number) => db.trabajador_movimientos.count({ where: { solicitud_id: id, tipo: "COMISION_EFECTIVO" } });
      const leer = (id: number) => db.solicitudes.findUnique({ where: { id } });
      const [e, ni, cr, yp] = await Promise.all([leer(elegible.id), leer(noIniciada.id), leer(conReporte.id), leer(yaPagada.id)]);
      const [ce, cni, ccr, cyp] = await Promise.all([comisiones(elegible.id), comisiones(noIniciada.id), comisiones(conReporte.id), comisiones(yaPagada.id)]);
      const avisos = await db.notificaciones_trabajador.count({ where: { solicitud_id: elegible.id, tipo: "PAGO_EFECTIVO_PRESUMIDO" } });

      // El trabajador reporta que no recibió el efectivo; el admin anula la comisión presumida.
      const rep = await db.solicitud_reportes.create({
        data: { solicitud_id: elegible.id, reportado_por: "TRABAJADOR", trabajador_id: t1.id, tipo: "PAGO_EN_DISPUTA", descripcion: "No recibí el efectivo" },
      });
      const comision = await db.trabajador_movimientos.findFirst({ where: { solicitud_id: elegible.id, tipo: "COMISION_EFECTIVO" } });
      const res = await db.solicitud_resoluciones.create({
        data: { solicitud_id: elegible.id, resultado_pago: "NO_PAGADO", motivo: "Según las pruebas, el efectivo no fue recibido" },
      });
      await db.$transaction([
        db.solicitud_reportes.update({ where: { id: rep.id }, data: { estado: "RESUELTO", resolucion_id: res.id } }),
        db.solicitudes.update({ where: { id: elegible.id }, data: { estado_pago: "ANULADO" } }),
        db.trabajador_movimientos.create({
          data: {
            trabajador_id: t1.id, cuenta: "DEUDA", tipo: "AJUSTE", monto: "-150.00", saldo_resultante: "0.00", solicitud_id: elegible.id,
            movimiento_relacionado_id: comision.id, resolucion_id: res.id, descripcion: `Resolución #${res.id}: efectivo no recibido`,
            clave_idempotencia: `AJUSTE:res:${res.id}:mov:${comision.id}`,
          },
        }),
      ]);
      const historial = await db.trabajador_movimientos.findMany({ where: { solicitud_id: elegible.id }, orderBy: { id: "asc" } });
      const final = await leer(elegible.id);

      const ok =
        JSON.stringify(rDobles) === JSON.stringify(["confirmada con pago presumido", "no confirmada"]) &&
        e?.estado === "REALIZADO" && e?.realizado_via === "AUTOMATICO" && e?.pago_registrado_por === "SISTEMA" && ce === 1 && avisos === 1 &&
        rNoIniciada === "no confirmada" && ni?.estado === "CONFIRMADO" && ni?.estado_pago === "PENDIENTE" && cni === 0 &&
        rConReporte === "no confirmada" && cr?.estado === "EN_PROCESO" && cr?.estado_pago === "PENDIENTE" && ccr === 0 &&
        rYaPagada === "confirmada (el pago ya estaba registrado)" && yp?.pago_registrado_por === "CLIENTE" && cyp === 1 &&
        historial.length === 2 && historial[0]?.tipo === "COMISION_EFECTIVO" && historial[1]?.tipo === "AJUSTE" &&
        final?.estado === "REALIZADO" && final?.estado_pago === "ANULADO";
      return (
        ok ||
        `dobles=${rDobles.join("|")} elegible=${e?.estado}/${e?.pago_registrado_por}/${ce} noIniciada=${rNoIniciada}/${cni} ` +
          `conReporte=${rConReporte}/${ccr} yaPagada=${rYaPagada}/${cyp} avisos=${avisos} historial=${historial.length} final=${final?.estado}/${final?.estado_pago}`
      );
    });

    await prueba("Notificaciones: tipos nuevos de cliente y de trabajador", async () => {
      const n = await db.notificaciones.create({
        data: { usuario_id: cliente.id, solicitud_id: solicitud.id, tipo: "INVITACIONES_RECHAZADAS", titulo: "t", mensaje: "m" },
      });
      creados.notificaciones.push(n.id);
      const n2 = await db.notificaciones.create({
        data: { usuario_id: cliente.id, solicitud_id: solicitud.id, tipo: "SERVICIO_CONFIRMADO_AUTOMATICAMENTE", titulo: "t", mensaje: "m" },
      });
      creados.notificaciones.push(n2.id);
      const n3 = await db.notificaciones.create({
        data: { usuario_id: cliente.id, solicitud_id: solicitud.id, tipo: "AVISO_CONFIRMACION_CON_EVIDENCIA", titulo: "t", mensaje: "m" },
      });
      creados.notificaciones.push(n3.id);
      await db.notificaciones_trabajador.create({
        data: { trabajador_id: t1.id, solicitud_id: solicitud.id, tipo: "COMPENSACION_REGISTRADA", titulo: "t", mensaje: "m" },
      });
      await db.notificaciones_trabajador.create({
        data: { trabajador_id: t1.id, solicitud_id: solicitud.id, tipo: "PAGO_SERVICIO_LIBERADO", titulo: "t", mensaje: "m" },
      });
      const n4 = await db.notificaciones.create({
        data: { usuario_id: cliente.id, solicitud_id: solicitud.id, tipo: "REPORTE_RESUELTO", titulo: "t", mensaje: "m" },
      });
      creados.notificaciones.push(n4.id);
      await db.notificaciones_trabajador.create({
        data: { trabajador_id: t1.id, solicitud_id: solicitud.id, tipo: "AJUSTE_REGISTRADO", titulo: "t", mensaje: "m" },
      });
      return n.leida_en === null;
    });

    await db.$disconnect();
    prismaEnsayo = null;

    // 8. Limpiar datos de prueba, rollback y comparar con producción
    const lista = (ids: number[]) => (ids.length ? ids.join(",") : "0");
    // evidencias_solicitud es una tabla EXISTENTE: solo se borran las filas de las solicitudes de prueba
    // (y antes que los reportes, porque las de reporte los referencian).
    await temp.ejecutar(`DELETE FROM evidencias_solicitud WHERE solicitud_id IN (${lista(creados.solicitudes)})`);
    for (const t of [
      "solicitud_reportes",
      "notificaciones_trabajador",
      "cliente_adeudos",
      "trabajador_estado_historial",
      "descuento_usos",
      "descuento_servicios",
      "descuentos",
      "solicitud_historial",
      "solicitud_trabajadores",
      "solicitud_especialidades",
      "solicitud_extras",
      "solicitud_areas",
      "trabajador_especialidades",
      "servicio_especialidades",
      "extra_especialidades",
    ]) {
      await temp.ejecutar(`DELETE FROM \`${t}\``);
    }
    await temp.ejecutar("DELETE FROM trabajador_movimientos WHERE movimiento_relacionado_id IS NOT NULL");
    await temp.ejecutar("DELETE FROM trabajador_movimientos");
    await temp.ejecutar("DELETE FROM solicitud_resoluciones");
    await temp.ejecutar("DELETE FROM especialidades");
    await temp.ejecutar(`DELETE FROM trabajador_horarios WHERE trabajador_id IN (${lista(creados.trabajadores)})`);
    await temp.ejecutar(`DELETE FROM notificaciones WHERE id IN (${lista(creados.notificaciones)})`);
    await temp.ejecutar(`DELETE FROM solicitudes WHERE id IN (${lista(creados.solicitudes)})`);
    await temp.ejecutar(`DELETE FROM inmuebles WHERE id IN (${lista(creados.inmuebles)})`);
    await temp.ejecutar(`DELETE FROM trabajadores WHERE id IN (${lista(creados.trabajadores)})`);
    await temp.ejecutar(`DELETE FROM usuarios WHERE id IN (${lista(creados.usuarios)})`);

    const sentenciasRollback = dividirSentencias(readFileSync(SQL_ROLLBACK, "utf8"));
    let revertidas = 0;
    try {
      for (const s of sentenciasRollback) {
        await temp.ejecutar(s);
        revertidas++;
      }
      registrar("8. Rollback aplicado", true, `${revertidas} sentencias`);
    } catch (e) {
      registrar(
        "8. Rollback aplicado",
        false,
        `falló la sentencia ${revertidas + 1}: ${(sentenciasRollback[revertidas] ?? "").slice(0, 120).replace(/\s+/g, " ")} → ${(e as Error).message}`,
      );
    }
    const trasRollback = await verificar002(temp.consultar);
    const tablasTras = await listarTablas(temp.consultar);
    const sobrantes = tablasTras.filter((t) => !tablasOriginales.includes(t));
    const difEstr2 = compararMapas(estructuraProd, await estructura(temp.consultar, tablasOriginales));
    const difDatos2 = compararMapas(huellasProd, await huellasDeDatos(temp.consultar, tablasOriginales));
    registrar(
      "8b. Tras el rollback la BD es idéntica a producción",
      trasRollback.presentes === 0 && trasRollback.precondicionOk && sobrantes.length === 0 && difEstr2.length === 0 && difDatos2.length === 0,
      `${trasRollback.presentes}/${trasRollback.total} objetos; tablas sobrantes [${sobrantes.join(", ")}]; estructura distinta [${difEstr2.join(", ")}]; datos distintos [${difDatos2.join(", ")}]`,
    );
    if (difEstr2.length) {
      const estrTemp = await estructura(temp.consultar, difEstr2);
      writeFileSync(
        path.join(carpeta, "diferencias-estructura.txt"),
        difEstr2.map((t) => `### ${t}\n--- producción\n${estructuraProd[t]}\n--- ensayo\n${estrTemp[t]}\n`).join("\n"),
        "utf8",
      );
    }
  } catch (error) {
    registrar("Ensayo detenido por un error", false, ocultarSecretos((error as Error)?.message ?? String(error)).slice(0, 400));
  } finally {
    if (prismaEnsayo) await prismaEnsayo.$disconnect().catch(() => undefined);
    if (temp) await temp.cerrar().catch(() => undefined);
    if (bdCreada) {
      if (conservar) {
        registrar("9. BD del ensayo conservada (--conservar)", true, nombreEnsayo);
      } else if (bdExistente && esBdExistentePermitidaParaEnsayo(nombreEnsayo)) {
        // Modo B: dejar la BD existente VACÍA como estaba (se borran solo tablas, no la BD).
        try {
          const limpieza = await conectar(nombreEnsayo);
          const [{ bd } = { bd: "" }] = await limpieza.consultar<{ bd: string }>("SELECT DATABASE() AS bd");
          if (bd !== nombreEnsayo || !esBdExistentePermitidaParaEnsayo(bd)) throw new Error(`conexión a ${bd}`);
          await limpieza.ejecutar("SET FOREIGN_KEY_CHECKS = 0");
          for (const t of await listarTablas(limpieza.consultar)) await limpieza.ejecutar(`DROP TABLE \`${t.replace(/`/g, "``")}\``);
          await limpieza.ejecutar("SET FOREIGN_KEY_CHECKS = 1");
          const quedan = await listarTablas(limpieza.consultar);
          await limpieza.cerrar();
          registrar("9. BD del ensayo vaciada (como estaba al empezar)", quedan.length === 0, `${nombreEnsayo}: ${quedan.length} tablas`);
        } catch (e) {
          registrar("9. Vaciar la BD del ensayo", false, ocultarSecretos((e as Error).message));
        }
      } else if (esBdDeEnsayo(nombreEnsayo)) {
        await servidor.ejecutar(`DROP DATABASE \`${nombreEnsayo}\``);
        const quedan = await servidor.consultar<{ n: bigint }>(
          "SELECT COUNT(*) AS n FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = ?",
          [nombreEnsayo],
        );
        registrar("9. BD temporal borrada", Number(quedan[0]?.n ?? 1) === 0, nombreEnsayo);
      }
    }
    try {
      const tablasFinales = await listarTablas(prod.consultar);
      const difEstrProd = compararMapas(estructuraProdInicial, await estructura(prod.consultar, tablasFinales));
      const difDatosProd = compararMapas(huellasProdInicial, await huellasDeDatos(prod.consultar, tablasFinales));
      registrar(
        "10. Producción intacta (misma estructura y datos que al empezar)",
        difEstrProd.length === 0 && difDatosProd.length === 0,
        `${tablasFinales.length} tablas en ${env.db.name}; estructura distinta [${difEstrProd.join(", ")}]; datos distintos [${difDatosProd.join(", ")}]`,
      );
    } catch (e) {
      registrar("10. Producción intacta", false, `no se pudo comprobar: ${(e as Error).message}`);
    }
    await prod.cerrar().catch(() => undefined);
    await servidor.cerrar().catch(() => undefined);
    rmSync(CARPETA_PRISMA_ENSAYO, { recursive: true, force: true });
    writeFileSync(
      path.join(carpeta, "reporte.json"),
      JSON.stringify({ fecha: new Date().toISOString(), bdEnsayo: nombreEnsayo, pasos }, null, 2),
      "utf8",
    );
    const fallos = pasos.filter((p) => !p.ok).length;
    console.log(`\nReporte: ${path.join(carpeta, "reporte.json")}`);
    console.log(fallos === 0 ? "ENSAYO OK: todos los pasos pasaron." : `ENSAYO CON ${fallos} FALLO(S).`);
    if (fallos) process.exitCode = 1;
  }
}

main().catch((error: unknown) => {
  console.error("El ensayo se detuvo:", ocultarSecretos((error as Error)?.message ?? String(error)));
  process.exitCode = 1;
});
