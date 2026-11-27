/**
 * Respaldo lógico, estructura y huellas de datos. SOLO LECTURA sobre la BD consultada.
 * Funciona con cualquier `Consulta` (Prisma o conexión directa).
 */
import { createHash } from "node:crypto";

import type { Consulta } from "./db-directa";

export function citarIdentificador(nombre: string): string {
  return "`" + nombre.replace(/`/g, "``") + "`";
}

// Literal de cadena MySQL (sql_mode sin NO_BACKSLASH_ESCAPES, verificado).
export function citarValor(valor: string | null): string {
  if (valor === null) return "NULL";
  return (
    "'" +
    valor
      .replace(/\\/g, "\\\\")
      .replace(/'/g, "\\'")
      .replace(/\0/g, "\\0")
      .replace(/\n/g, "\\n")
      .replace(/\r/g, "\\r")
      .replace(/\x1a/g, "\\Z") +
    "'"
  );
}

export async function listarTablas(q: Consulta): Promise<string[]> {
  const filas = await q<{ t: string }>(
    `SELECT TABLE_NAME AS t FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME`,
  );
  return filas.map((f) => f.t);
}

async function columnas(q: Consulta, tabla: string) {
  const filas = await q<{ c: string; extra: string | null }>(
    `SELECT COLUMN_NAME AS c, EXTRA AS extra FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION`,
    [tabla],
  );
  return filas.map((f) => ({ nombre: f.c, generada: /GENERATED/i.test(f.extra ?? "") }));
}

async function clavePrimaria(q: Consulta, tabla: string): Promise<string[]> {
  const filas = await q<{ c: string }>(
    `SELECT COLUMN_NAME AS c FROM information_schema.KEY_COLUMN_USAGE
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND CONSTRAINT_NAME = 'PRIMARY'
     ORDER BY ORDINAL_POSITION`,
    [tabla],
  );
  return filas.map((f) => f.c);
}

export async function ddlDeTabla(q: Consulta, tabla: string): Promise<string> {
  const filas = await q<Record<string, string>>(`SHOW CREATE TABLE ${citarIdentificador(tabla)}`);
  const ddl = filas[0]?.["Create Table"];
  if (!ddl) throw new Error(`No se obtuvo el DDL de ${tabla}`);
  return ddl;
}

/** Quita paréntesis exteriores redundantes: "((a >= 1))" → "a >= 1". */
function sinParentesisExteriores(expr: string): string {
  let e = expr.trim();
  for (;;) {
    if (!e.startsWith("(") || !e.endsWith(")")) return e;
    let nivel = 0;
    let envuelveTodo = true;
    for (let i = 0; i < e.length; i++) {
      if (e[i] === "(") nivel++;
      else if (e[i] === ")") nivel--;
      if (nivel === 0 && i < e.length - 1) {
        envuelveTodo = false;
        break;
      }
    }
    if (!envuelveTodo) return e;
    e = e.slice(1, -1).trim();
  }
}

/**
 * TiDB vuelve a escribir las expresiones CHECK con paréntesis extra al recrear la tabla
 * ("CHECK ((x))" vs "CHECK (((x)))"); se normalizan para comparar estructuras.
 */
function normalizarChecks(ddl: string): string {
  let salida = "";
  let i = 0;
  for (;;) {
    const pos = ddl.indexOf("CHECK (", i);
    if (pos === -1) return salida + ddl.slice(i);
    const inicio = pos + "CHECK ".length;
    let nivel = 0;
    let fin = inicio;
    for (; fin < ddl.length; fin++) {
      if (ddl[fin] === "(") nivel++;
      else if (ddl[fin] === ")" && --nivel === 0) break;
    }
    salida += ddl.slice(i, pos) + `CHECK (${sinParentesisExteriores(ddl.slice(inicio, fin + 1))})`;
    i = fin + 1;
  }
}

/** DDL normalizado (sin contadores AUTO_INCREMENT; CHECK sin paréntesis redundantes). */
export async function estructura(q: Consulta, tablas?: string[]): Promise<Record<string, string>> {
  const resultado: Record<string, string> = {};
  for (const tabla of tablas ?? (await listarTablas(q))) {
    resultado[tabla] = normalizarChecks(
      (await ddlDeTabla(q, tabla))
        .replace(/\s+AUTO_INCREMENT=\d+/g, "")
        .replace(/\/\*T!\[auto_id_cache\][^*]*\*\//g, ""),
    ).trim();
  }
  return resultado;
}

async function filasComoTexto(q: Consulta, tabla: string) {
  const insertables = (await columnas(q, tabla)).filter((c) => !c.generada);
  const orden = await clavePrimaria(q, tabla);
  const seleccion = insertables
    .map((c) => `CAST(${citarIdentificador(c.nombre)} AS CHAR) AS ${citarIdentificador(c.nombre)}`)
    .join(", ");
  const ordenSql = orden.length ? ` ORDER BY ${orden.map(citarIdentificador).join(", ")}` : "";
  const filas = await q<Record<string, string | null>>(
    `SELECT ${seleccion} FROM ${citarIdentificador(tabla)}${ordenSql}`,
  );
  return { insertables, filas };
}

/** Huella (SHA-256) del contenido de cada tabla, para comparar datos entre dos BDs. */
export async function huellasDeDatos(
  q: Consulta,
  tablas?: string[],
  /** Si se indica, solo cuenta estas columnas por tabla (p. ej. las que había antes de un ALTER ADD COLUMN). */
  soloColumnas?: Record<string, string[]>,
): Promise<Record<string, { filas: number; sha256: string }>> {
  const resultado: Record<string, { filas: number; sha256: string }> = {};
  for (const tabla of tablas ?? (await listarTablas(q))) {
    const { insertables: todas, filas } = await filasComoTexto(q, tabla);
    const permitidas = soloColumnas?.[tabla];
    const insertables = permitidas ? todas.filter((c) => permitidas.includes(c.nombre)) : todas;
    const hash = createHash("sha256");
    for (const fila of filas) hash.update(JSON.stringify(insertables.map((c) => fila[c.nombre] ?? null)) + "\n");
    resultado[tabla] = { filas: filas.length, sha256: hash.digest("hex") };
  }
  return resultado;
}

/**
 * Ordena las tablas para que cada una aparezca DESPUÉS de las que referencia por FK
 * (las auto-referencias se ignoran). Así el restore funciona aunque el motor no permita
 * crear FKs hacia tablas inexistentes.
 */
export async function ordenarPorDependencias(q: Consulta, tablas: string[]): Promise<string[]> {
  const fks = await q<{ t: string; rt: string }>(
    `SELECT DISTINCT TABLE_NAME AS t, REFERENCED_TABLE_NAME AS rt FROM information_schema.KEY_COLUMN_USAGE
     WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME IS NOT NULL`,
  );
  const depende = new Map(tablas.map((t) => [t, new Set<string>()]));
  for (const { t, rt } of fks) if (t !== rt && depende.has(t) && depende.has(rt)) depende.get(t)?.add(rt);

  const orden: string[] = [];
  const visitando = new Set<string>();
  const visitar = (t: string) => {
    if (orden.includes(t)) return;
    if (visitando.has(t)) throw new Error(`Dependencia circular entre tablas en ${t}`);
    visitando.add(t);
    for (const rt of depende.get(t) ?? []) visitar(rt);
    visitando.delete(t);
    orden.push(t);
  };
  for (const t of tablas) visitar(t);
  return orden;
}

export type Respaldo = {
  bd: string;
  motor: string;
  contenido: string;
  filasPorTabla: Record<string, number>;
  sha256: string;
};

/** restore.sql: CREATE TABLE + INSERT de todas las filas. Para una BD VACÍA; no hace DROP. */
export async function generarRespaldo(q: Consulta): Promise<Respaldo> {
  const [info] = await q<{ motor: string; bd: string }>("SELECT VERSION() AS motor, DATABASE() AS bd");
  if (!info) throw new Error("No se pudo leer la versión del motor");

  const sql: string[] = [
    `-- Respaldo lógico de la BD ${info.bd} — ${new Date().toISOString()}`,
    `-- Motor: ${info.motor}`,
    "-- Restaurar SOLO en una base de datos VACÍA. Este archivo no borra nada.",
    "SET FOREIGN_KEY_CHECKS = 0;",
    "",
  ];
  const filasPorTabla: Record<string, number> = {};

  for (const tabla of await ordenarPorDependencias(q, await listarTablas(q))) {
    sql.push(`-- ─── ${tabla} ───`, `${await ddlDeTabla(q, tabla)};`, "");
    const { insertables, filas } = await filasComoTexto(q, tabla);
    filasPorTabla[tabla] = filas.length;
    const lista = insertables.map((c) => citarIdentificador(c.nombre)).join(", ");
    for (const fila of filas) {
      const valores = insertables.map((c) => citarValor(fila[c.nombre] ?? null)).join(", ");
      sql.push(`INSERT INTO ${citarIdentificador(tabla)} (${lista}) VALUES (${valores});`);
    }
    sql.push("");
  }

  sql.push("SET FOREIGN_KEY_CHECKS = 1;", "");
  const contenido = sql.join("\n");
  return {
    bd: info.bd,
    motor: info.motor,
    contenido,
    filasPorTabla,
    sha256: createHash("sha256").update(contenido).digest("hex"),
  };
}
