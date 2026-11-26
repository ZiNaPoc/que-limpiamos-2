/**
 * Comprobación explícita del destino ANTES de servir o sembrar (doc 24): host, puerto y nombre de
 * la BD deben ser los del TiDB LOCAL de desarrollo, y el servidor debe ser TiDB local (no Serverless).
 * Lanza si algo no cuadra; nunca crea ni migra el esquema.
 */
import { env } from "../../config/env";
import { BD_LOCAL, BD_LOCAL_DESARROLLO, verificarQueEsLocal } from "./bd-local";
import { conectar } from "./db-directa";

export async function verificarDestinoLocal(): Promise<{ host: string; port: number; bd: string; version: string; tablas: number }> {
  const { host, port, name: bd, esLocal, tls } = env.db;
  if (!esLocal || host !== BD_LOCAL.host) throw new Error(`Destino no local: host ${host}`);
  if (port !== BD_LOCAL.port) throw new Error(`Destino no local: puerto ${port}`);
  if (bd !== BD_LOCAL_DESARROLLO) throw new Error(`BD inesperada: ${bd} (solo ${BD_LOCAL_DESARROLLO})`);
  if (tls) throw new Error("La BD local se usa sin TLS; TLS activo indica una conexión remota");

  const c = await conectar(bd);
  try {
    const version = await verificarQueEsLocal(c.consultar, host);
    const [actual] = await c.consultar("SELECT DATABASE() AS bd");
    if (String(actual?.bd) !== bd) throw new Error(`La conexión quedó en ${String(actual?.bd)}, no en ${bd}`);
    const [fila] = await c.consultar("SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = ?", [bd]);
    const tablas = Number(fila?.n ?? 0);
    if (!tablas) throw new Error(`${bd} no tiene tablas: ejecuta antes  npm run bd:local -- preparar`);
    return { host, port, bd, version, tablas };
  } finally {
    await c.cerrar();
  }
}

/**
 * Destino de la BD de DEMOSTRACIÓN en TiDB Cloud (datos:local -- --nube y nube-demo): TLS, host no local,
 * TiDB Serverless y SOLO la BD queLimpiamos_proyecto (nunca la histórica queLimpiamos).
 */
export async function verificarDestinoNube(opciones: { conTablas: boolean }): Promise<{ host: string; port: number; bd: string; version: string; tablas: number }> {
  const { host, port, name: bd, esLocal, tls } = env.db;
  if (esLocal || !tls) throw new Error("El destino de la nube exige un host remoto con TLS");
  if (bd !== "queLimpiamos_proyecto") throw new Error(`BD inesperada en la nube: ${bd} (solo queLimpiamos_proyecto)`);
  const c = await conectar(bd);
  try {
    const [v] = await c.consultar("SELECT VERSION() AS v, DATABASE() AS bd");
    const version = String(v?.v ?? "");
    if (!version.includes("TiDB")) throw new Error(`El servidor no es TiDB (${version})`);
    if (String(v?.bd) !== bd) throw new Error(`La conexión quedó en ${String(v?.bd)}`);
    const [fila] = await c.consultar("SELECT COUNT(*) AS n FROM information_schema.TABLES WHERE TABLE_SCHEMA = ?", [bd]);
    const tablas = Number(fila?.n ?? 0);
    if (opciones.conTablas && !tablas) throw new Error(`${bd} no tiene tablas: ejecuta antes  npm run nube:demo -- preparar`);
    return { host: "(nube)", port, bd, version, tablas };
  } finally {
    await c.cerrar();
  }
}
