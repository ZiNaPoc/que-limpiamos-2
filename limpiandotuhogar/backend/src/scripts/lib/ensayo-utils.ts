/**
 * Utilidades de los ensayos de SQL (copiadas de ensayo-002.ts para no modificarlo).
 */
import { spawnSync } from "node:child_process";

import { ocultarSecretos } from "./db-directa";

export function compararMapas(a: Record<string, unknown>, b: Record<string, unknown>): string[] {
  const dif: string[] = [];
  for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
    if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) dif.push(k);
  }
  return dif;
}

export function prismaCli(raiz: string, args: string[], extraEnv: Record<string, string> = {}) {
  const r = spawnSync("npx", ["--no-install", "prisma", ...args], {
    cwd: raiz,
    env: { ...process.env, ...extraEnv },
    encoding: "utf8",
    shell: process.platform === "win32",
    maxBuffer: 50 * 1024 * 1024,
  });
  return { ok: r.status === 0, stdout: r.stdout ?? "", salida: ocultarSecretos(`${r.stdout ?? ""}\n${r.stderr ?? ""}`) };
}

/** Modelos (campos escalares con tipo) y enums de un schema Prisma, para comparar. */
export function resumenSchema(texto: string) {
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

/** Diferencias entre dos schemas Prisma (campos escalares y enums). */
export function diferenciasSchema(real: string, previsto: string): string[] {
  const r = resumenSchema(real);
  const p = resumenSchema(previsto);
  const dif: string[] = [];
  for (const m of new Set([...Object.keys(r.modelos), ...Object.keys(p.modelos)])) {
    const a = r.modelos[m];
    const b = p.modelos[m];
    if (!a || !b) {
      dif.push(`modelo ${m}: ${a ? "sobra en la BD" : "falta en la BD"}`);
      continue;
    }
    for (const c of new Set([...Object.keys(a), ...Object.keys(b)])) {
      if (a[c] !== b[c]) dif.push(`${m}.${c}: BD=${a[c] ?? "—"} previsto=${b[c] ?? "—"}`);
    }
  }
  for (const e of new Set([...Object.keys(r.enums), ...Object.keys(p.enums)])) {
    if (JSON.stringify(r.enums[e]) !== JSON.stringify(p.enums[e])) dif.push(`enum ${e}`);
  }
  return dif;
}

export async function esperarErrorPrisma(fn: () => Promise<unknown>, codigo: string): Promise<boolean> {
  try {
    await fn();
    return false;
  } catch (e) {
    return (e as { code?: string })?.code === codigo;
  }
}

/** Ejecuta y devuelve el mensaje de error, o null si no falló. */
export async function mensajeDeError(fn: () => Promise<unknown>): Promise<string | null> {
  try {
    await fn();
    return null;
  } catch (e) {
    return ocultarSecretos(String((e as Error)?.message ?? e));
  }
}
