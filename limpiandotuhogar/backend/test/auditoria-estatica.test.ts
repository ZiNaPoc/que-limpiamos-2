import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";

/**
 * Inmutabilidad del historial de moderación (doc 21 §6, capa 1). TiDB no tiene triggers: la
 * garantía en el backend es que NINGÚN código actualiza ni borra moderacion_eventos, y que solo
 * dominio/auditoria.ts lo escribe (con create). Prueba estática: no necesita BD.
 */

const SRC = path.resolve(__dirname, "..", "src");

function archivos(dir: string): string[] {
  return readdirSync(dir).flatMap((nombre) => {
    const ruta = path.join(dir, nombre);
    return statSync(ruta).isDirectory() ? archivos(ruta) : /\.ts$/.test(nombre) ? [ruta] : [];
  });
}

const fuentes = archivos(SRC).map((ruta) => ({ ruta: path.relative(SRC, ruta).replace(/\\/g, "/"), texto: readFileSync(ruta, "utf8") }));

describe("Auditoría inmutable (estático)", () => {
  it("ningún archivo actualiza, borra o hace upsert de moderacion_eventos con Prisma", () => {
    const usos = fuentes.filter((f) => /moderacion_eventos\s*\.\s*(update|updateMany|delete|deleteMany|upsert|createMany)\b/.test(f.texto));
    assert.deepEqual(usos.map((f) => f.ruta), []);
  });

  it("ningún SQL de src modifica moderacion_eventos (UPDATE/DELETE/TRUNCATE/DROP/ALTER)", () => {
    const usos = fuentes.filter((f) => /(UPDATE|DELETE\s+FROM|TRUNCATE(\s+TABLE)?|DROP\s+TABLE|ALTER\s+TABLE)\s+`?moderacion_eventos/i.test(f.texto));
    assert.deepEqual(usos.map((f) => f.ruta), []);
  });

  it("solo dominio/auditoria.ts crea eventos", () => {
    const creadores = fuentes.filter((f) => /moderacion_eventos\s*\.\s*create\b/.test(f.texto)).map((f) => f.ruta);
    assert.deepEqual(creadores, ["dominio/auditoria.ts"]);
  });

  it("no hay rutas de escritura sobre el historial (solo GET /moderacion/eventos)", () => {
    const rutas = fuentes.flatMap((f) => [...f.texto.matchAll(/\.(post|put|patch|delete)\(\s*"([^"]*eventos[^"]*)"/g)].map((m) => `${f.ruta} ${m[1]} ${m[2]}`));
    assert.deepEqual(rutas, []);
  });
});
