/**
 * Verificación del cambio 003 (SOLO LECTURA): `npm run db:verificar-003`
 *
 * Indica qué objetos del SQL 003 existen y si se cumplen sus precondiciones (002 completo,
 * sin resoluciones ni ajustes previos).
 *   - 0: todo bien (no aplicado y aplicable, o aplicado completo)
 *   - 2: aplicado a medias
 *   - 3: no aplicado y con bloqueos (no se debe aplicar todavía)
 */
import { prisma } from "../config/prisma";
import type { Consulta, Fila } from "./lib/db-directa";
import { verificar003 } from "./lib/objetos-003";

const q: Consulta = <T extends Fila = Fila>(sql: string, params: unknown[] = []) =>
  prisma.$queryRawUnsafe<T[]>(sql, ...params);

async function main() {
  const r = await verificar003(q);
  console.log(`BD: ${r.bd}\n`);
  console.log(r.lineas.join("\n"));
  if (r.estado === "APLICADO A MEDIAS") process.exitCode = 2;
  else if (r.estado === "NO APLICADO" && r.bloqueos.length) process.exitCode = 3;
}

main()
  .catch((error: unknown) => {
    console.error("La verificación falló:", (error as Error)?.message ?? error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
