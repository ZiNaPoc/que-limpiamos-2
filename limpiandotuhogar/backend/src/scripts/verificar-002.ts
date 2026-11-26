/**
 * Verificación del cambio 002 (SOLO LECTURA): `npm run db:verificar-002`
 *
 * Indica qué objetos del SQL 002 existen ya en la BD de la app, cuántas filas tienen
 * las tablas que toca y si se cumple la precondición de updated_at.
 *   - ANTES de ejecutar el 002: todo "no existe" → NO APLICADO.
 *   - DESPUÉS: todo "existe" → APLICADO COMPLETO.
 *   - A medias: muestra qué revertir o completar (sale con código 2).
 */
import { prisma } from "../config/prisma";
import type { Consulta, Fila } from "./lib/db-directa";
import { verificar002 } from "./lib/objetos-002";

const q: Consulta = <T extends Fila = Fila>(sql: string, params: unknown[] = []) =>
  prisma.$queryRawUnsafe<T[]>(sql, ...params);

async function main() {
  const r = await verificar002(q);
  console.log(`BD: ${r.bd} · Motor: ${r.motor}\n`);
  console.log(r.lineas.join("\n"));
  if (!r.precondicionOk) {
    console.log("\n⚠ Algún updated_at existente perdió ON UPDATE: revisar antes de continuar.");
    process.exitCode = 3;
  }
  if (r.estado === "APLICADO A MEDIAS") process.exitCode = 2;
}

main()
  .catch((error: unknown) => {
    console.error("La verificación falló:", (error as Error)?.message ?? error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
