import { BD_PRUEBAS } from "./entorno";

import { createHash } from "node:crypto";

import { activarChecksLocales, BD_LOCAL, construirBdLocal, sentenciasDelEsquema, verificarQueEsLocal } from "../../src/scripts/lib/bd-local";
import { conectar } from "../../src/scripts/lib/db-directa";
import { listarTablas } from "../../src/scripts/lib/respaldo";

/**
 * BD de pruebas LOCAL (TiDB en Docker, doc 22): quelimpiamos_pruebas en 127.0.0.1:4000.
 * Ya no se lee ni se escribe el clúster remoto. El esquema (000 + 002 v10 + 003 v2) se construye
 * una vez y se reconstruye solo si cambian los archivos SQL; entre archivos de prueba se
 * BORRAN las filas (no el esquema). Así ninguna prueba hereda datos de otra.
 */

/** Se conserva el tipo para no cambiar las pruebas existentes; ya no hay foto de producción. */
export type FotoProduccion = { local: true };
export type ResultadoLimpieza = { tablasRestantes: string[]; estructuraDistinta: string[]; datosDistintos: string[] };

const TABLA_MARCA = "_esquema_local";

async function huellaDelEsquema(): Promise<string> {
  const h = createHash("sha256");
  for (const { archivo, sentencias } of await sentenciasDelEsquema()) h.update(archivo).update(sentencias.join(";\n"));
  return h.digest("hex");
}

async function conexionVerificada(nombre: string | null) {
  const c = await conectar(nombre);
  await verificarQueEsLocal(c.consultar, BD_LOCAL.host);
  return c;
}

async function borrarFilas(c: Awaited<ReturnType<typeof conectar>>): Promise<void> {
  await c.ejecutar("SET FOREIGN_KEY_CHECKS = 0");
  for (const t of await listarTablas(c.consultar)) {
    if (t !== TABLA_MARCA) await c.ejecutar(`DELETE FROM \`${t.replace(/`/g, "``")}\``);
  }
  await c.ejecutar("SET FOREIGN_KEY_CHECKS = 1");
}

export async function prepararBdDePruebas(): Promise<FotoProduccion> {
  const huella = await huellaDelEsquema();
  const previa = await conexionVerificada(null);
  try {
    await activarChecksLocales(previa.ejecutar);
  } finally {
    await previa.cerrar();
  }
  const servidor = await conexionVerificada(null);
  try {
    const existe = await servidor.consultar(
      "SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?",
      [BD_PRUEBAS, TABLA_MARCA],
    );
    let vigente = false;
    if (Number(existe[0]?.n ?? 0) === 1) {
      const [fila] = await servidor.consultar(`SELECT huella FROM \`${BD_PRUEBAS}\`.${TABLA_MARCA} LIMIT 1`);
      vigente = fila?.huella === huella;
    }
    if (!vigente) {
      await construirBdLocal(servidor.consultar, servidor.ejecutar, BD_PRUEBAS, { recrear: true });
      await servidor.ejecutar(`CREATE TABLE \`${BD_PRUEBAS}\`.${TABLA_MARCA} (huella CHAR(64) NOT NULL)`);
      await servidor.ejecutar(`INSERT INTO \`${BD_PRUEBAS}\`.${TABLA_MARCA} VALUES (?)`.replace("?", `'${huella}'`));
    }
  } finally {
    await servidor.cerrar();
  }
  const c = await conexionVerificada(BD_PRUEBAS);
  try {
    await borrarFilas(c);
  } finally {
    await c.cerrar();
  }
  return { local: true };
}

/** Vacía las filas que dejó la prueba. El esquema se conserva para la siguiente ejecución. */
export async function limpiarBdDePruebas(_foto: FotoProduccion | undefined): Promise<ResultadoLimpieza> {
  const c = await conexionVerificada(BD_PRUEBAS);
  try {
    await borrarFilas(c);
    const conFilas: string[] = [];
    for (const t of await listarTablas(c.consultar)) {
      if (t === TABLA_MARCA) continue;
      const [fila] = await c.consultar(`SELECT COUNT(*) AS n FROM \`${t}\``);
      if (Number(fila?.n ?? 0) > 0) conFilas.push(t);
    }
    return { tablasRestantes: conFilas, estructuraDistinta: [], datosDistintos: [] };
  } finally {
    await c.cerrar();
  }
}
