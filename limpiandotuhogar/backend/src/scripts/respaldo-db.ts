/**
 * Respaldo lógico de la BD (SOLO LECTURA): `npm run db:respaldo`
 *
 * Genera en backups/<fecha>/ (carpeta ignorada por git):
 *   - restore.sql   → CREATE TABLE (SHOW CREATE TABLE) + INSERT de todas las filas.
 *                     Para restaurar en una BD VACÍA (nunca hace DROP).
 *   - resumen.json  → filas y huella de datos por tabla, motor y SHA-256 de restore.sql.
 * ⚠ El archivo contiene datos personales y hashes de contraseñas: no compartirlo.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

import { prisma } from "../config/prisma";
import type { Consulta, Fila } from "./lib/db-directa";
import { generarRespaldo, huellasDeDatos } from "./lib/respaldo";

const q: Consulta = <T extends Fila = Fila>(sql: string, params: unknown[] = []) =>
  prisma.$queryRawUnsafe<T[]>(sql, ...params);

async function main() {
  const respaldo = await generarRespaldo(q);
  const huellas = await huellasDeDatos(q);

  const carpeta = path.resolve(process.cwd(), "backups", new Date().toISOString().replace(/[:.]/g, "-"));
  mkdirSync(carpeta, { recursive: true });
  writeFileSync(path.join(carpeta, "restore.sql"), respaldo.contenido, "utf8");
  writeFileSync(
    path.join(carpeta, "resumen.json"),
    JSON.stringify(
      { fecha: new Date().toISOString(), bd: respaldo.bd, motor: respaldo.motor, tablas: huellas, sha256: respaldo.sha256 },
      null,
      2,
    ),
    "utf8",
  );

  console.log(`Respaldo creado en ${carpeta}`);
  console.log("Filas por tabla:", respaldo.filasPorTabla);
  console.log("SHA-256 restore.sql:", respaldo.sha256);
}

main()
  .catch((error: unknown) => {
    console.error("El respaldo falló:", (error as Error)?.message ?? error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
