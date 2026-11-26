/**
 * Schema Prisma a partir de la BD LOCAL de desarrollo (quelimpiamos_dev = 000 + 002 v10 + 003 v2).
 *   npm run prisma:local
 * 1) prisma db pull contra 127.0.0.1:4000 (DATABASE_URL solo de este proceso; .env no cambia);
 * 2) marca con @ignore las columnas GENERADAS (las calcula la BD; el backend nunca las escribe);
 * 3) prisma generate (el cliente en generated/ lo escribe la CLI, nunca a mano).
 */
import "./lib/entorno-bd-local";

import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import { BD_LOCAL, BD_LOCAL_DESARROLLO, verificarQueEsLocal } from "./lib/bd-local";
import { conectar } from "./lib/db-directa";
import { prismaCli } from "./lib/ensayo-utils";

const RAIZ = path.resolve(__dirname, "../..");
const SCHEMA = path.join(RAIZ, "prisma/schema.prisma");

async function main() {
  const c = await conectar(BD_LOCAL_DESARROLLO);
  let generadas: { tabla: string; columna: string }[];
  try {
    await verificarQueEsLocal(c.consultar, BD_LOCAL.host);
    const filas = await c.consultar(
      "SELECT TABLE_NAME AS tabla, COLUMN_NAME AS columna FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? AND (EXTRA LIKE '%VIRTUAL GENERATED%' OR EXTRA LIKE '%STORED GENERATED%')",
      [BD_LOCAL_DESARROLLO],
    );
    generadas = filas.map((f: Record<string, unknown>) => ({ tabla: String(f.tabla), columna: String(f.columna) }));
  } finally {
    await c.cerrar();
  }

  const pull = prismaCli(RAIZ, ["db", "pull", "--force"]);
  if (!pull.ok) throw new Error(`prisma db pull falló:\n${pull.salida}`);

  let texto = readFileSync(SCHEMA, "utf8").replace(/\r\n/g, "\n");
  let marcadas = 0;
  for (const { tabla, columna } of generadas) {
    const bloque = new RegExp(`(^model ${tabla} \\{[\\s\\S]*?^\\})`, "m");
    texto = texto.replace(bloque, (modelo) =>
      modelo.replace(new RegExp(`^(\\s+${columna}\\s[^\\n]*?)(\\s*)$`, "m"), (linea, campo: string) => {
        if (campo.includes("@ignore")) return linea;
        marcadas++;
        return `${campo} @ignore`;
      }),
    );
  }
  const cabecera =
    "// Generado con `npm run prisma:local` desde la BD LOCAL (000 + 002 v10 + 003 v2). Las columnas\n" +
    "// GENERADAS por la BD van con @ignore. Producción NO tiene todavía el 002 ni el 003 v2.\n";
  writeFileSync(SCHEMA, cabecera + texto.replace(/^\/\/ Generado con `npm run prisma:local`[^\n]*\n\/\/[^\n]*\n/, ""));
  console.log(`Schema actualizado: ${generadas.length} columnas generadas, ${marcadas} marcadas con @ignore.`);

  const gen = prismaCli(RAIZ, ["generate"]);
  if (!gen.ok) throw new Error(`prisma generate falló:\n${gen.salida}`);
  console.log("Cliente Prisma regenerado.");
}

main().catch((error) => {
  console.error("ERROR:", (error as Error).message);
  process.exit(1);
});
