/**
 * BD de DEMOSTRACIÓN en TiDB Cloud para el backend de Render (doc 27).
 *   npm run nube:demo -- estado     solo lectura: tablas, CHECK y migraciones presentes
 *   npm run nube:demo -- preparar   construye 000 + 002 v10 + 003 v2 + 004 en queLimpiamos_proyecto,
 *                                   SOLO si está VACÍA (nunca borra, nunca toca la histórica queLimpiamos)
 * Las credenciales salen de .env y no se imprimen.
 */
import "./lib/entorno-datos";

import { env } from "../config/env";
import { ARCHIVOS_ESQUEMA, sentenciasDelEsquema } from "./lib/bd-local";
import { conectar } from "./lib/db-directa";

const BD = "queLimpiamos_proyecto";

async function main() {
  const accion = process.argv.find((a) => a === "estado" || a === "preparar") ?? "estado";
  if (env.db.esLocal || !env.db.tls || env.db.name !== BD) throw new Error("Destino inesperado: este script solo trabaja con queLimpiamos_proyecto en la nube, con TLS");
  const c = await conectar(BD);
  try {
    const [v] = await c.consultar("SELECT VERSION() AS v, DATABASE() AS bd, @@tidb_enable_check_constraint AS chk");
    if (String(v?.bd) !== BD) throw new Error(`Conectado a ${String(v?.bd)}: se aborta`);
    console.log(`Nube: ${String(v?.v)} · BD ${String(v?.bd)} · CHECK activos: ${Number(v?.chk) === 1 ? "sí" : "NO"}`);
    const [t] = await c.consultar("SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = ?", [BD]);
    const tablas = Number(t?.n ?? 0);
    console.log(`Tablas en ${BD}: ${tablas}`);
    if (accion === "estado") return;

    if (tablas > 0) throw new Error(`${BD} ya tiene ${tablas} tablas: no se reconstruye (nunca se borra). Revisa con  npm run nube:demo -- estado`);
    let total = 0;
    for (const { archivo, sentencias } of await sentenciasDelEsquema(ARCHIVOS_ESQUEMA)) {
      for (const [i, s] of sentencias.entries()) {
        try {
          await c.ejecutar(s);
          total++;
        } catch (error) {
          throw new Error(`${archivo}, sentencia ${i + 1}: ${(error as Error).message.split("\n")[0]}`);
        }
      }
      console.log(`  ${archivo}: ${sentencias.length} sentencias`);
    }
    const [f] = await c.consultar("SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = ?", [BD]);
    const [chk] = await c.consultar("SELECT COUNT(*) AS n FROM information_schema.TIDB_CHECK_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = ?", [BD]);
    console.log(`Listo: ${total} sentencias; ${Number(f?.n)} tablas; ${Number(chk?.n)} CHECK registrados.`);
  } finally {
    await c.cerrar();
  }
}

main().catch((e) => {
  console.error("ERROR:", (e as Error).message.replace(/mysql:\/\/[^@]+@/g, "mysql://***@"));
  process.exit(1);
});
