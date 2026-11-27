/**
 * Ensayo del SQL 004 (doc 25 v2 §6) SOLO en la BD local de PRUEBAS:
 *   npm run bd:ensayo-004
 *
 * 1. Reconstruye quelimpiamos_pruebas con 000 + 002 v10 + 003 v2 (SIN el 004).
 * 2. Carga datos "anteriores" en las tablas que el 004 toca (todos los valores de ENUM previos).
 * 3. Huella de datos de TODAS las tablas.
 * 4. Aplica el 004 → la huella de las columnas que ya existían no cambia (ni filas ni valores).
 * 5. Comprueba lo nuevo: SUPERVISAR_SOLICITUDES, VENCIDA, inmueble_alias_aplicado y una sola
 *    resolución de servicio por solicitud (una solo de pago sí se permite).
 * 6. Rollback (tras quitar las filas de prueba del paso 5) → huella igual que en el paso 3.
 * 7. Vuelve a aplicar el 004 (debe funcionar sobre el rollback).
 * Al final la BD de pruebas queda con el esquema completo; `npm test` la reconstruye sola si hace falta.
 * Nunca toca quelimpiamos_dev, la demo ni ninguna BD remota.
 */
import "./lib/entorno-bd-pruebas";

import { activarChecksLocales, BD_LOCAL, BD_LOCAL_PRUEBAS, construirBdLocal, sentenciasDeArchivo, verificarQueEsLocal } from "./lib/bd-local";
import { conectar } from "./lib/db-directa";
import { huellasDeDatos } from "./lib/respaldo";

const BASE = ["000_estructura_produccion.sql", "002_detalle_solicitud_especialidades_invitaciones.sql", "003_v2_notificaciones_permisos_resenas_reportes.sql"] as const;
type Conexion = Awaited<ReturnType<typeof conectar>>;
const resultados: { paso: string; ok: boolean; detalle: string }[] = [];

function anotar(paso: string, ok: boolean, detalle = "") {
  resultados.push({ paso, ok, detalle });
  console.log(`${ok ? "OK   " : "FALLO"} ${paso}${detalle ? ` — ${detalle}` : ""}`);
  if (!ok) throw new Error(`Falló: ${paso}. ${detalle}`);
}

async function aplicar(c: Conexion, archivo: string): Promise<number> {
  const sentencias = await sentenciasDeArchivo(archivo);
  for (const [i, s] of sentencias.entries()) {
    try {
      await c.ejecutar(s);
    } catch (error) {
      throw new Error(`${archivo}, sentencia ${i + 1}: ${(error as Error).message}`);
    }
  }
  return sentencias.length;
}

async function esperarError(c: Conexion, sql: string, patron: RegExp): Promise<string> {
  try {
    await c.ejecutar(sql);
  } catch (error) {
    const m = (error as Error).message;
    if (patron.test(m)) return m.split("\n")[0]!.slice(0, 160);
    throw new Error(`Error inesperado: ${m}`);
  }
  throw new Error(`Se esperaba un error y la sentencia funcionó: ${sql}`);
}

async function columnas(c: Conexion, tabla: string): Promise<string[]> {
  const filas = await c.consultar(
    "SELECT COLUMN_NAME AS c FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION",
    [tabla],
  );
  return filas.map((f) => String(f.c));
}

async function cargarDatosAnteriores(c: Conexion) {
  await c.ejecutar(
    "INSERT INTO usuarios (id, rol, nombre_completo, correo, telefono, password_hash) VALUES (1,'CLIENTE','Cliente Ensayo','cliente@ensayo.test','9990000001','x'),(2,'ADMIN','Admin Uno','admin1@ensayo.test',NULL,'x'),(3,'ADMIN','Admin Dos','admin2@ensayo.test',NULL,'x')",
  );
  const trabajadores = [1, 2, 3, 4, 5, 6, 7].map((i) => `(${i},'Trab ${i}','99900000${10 + i}','t${i}@ensayo.test','Calle ${i}')`).join(",");
  await c.ejecutar(`INSERT INTO trabajadores (id, nombre_completo, telefono, correo, direccion) VALUES ${trabajadores}`);
  await c.ejecutar("INSERT INTO servicios (id, nombre, descripcion, precio_base) VALUES (1,'Servicio Ensayo','desc',400.00)");
  await c.ejecutar("INSERT INTO inmuebles (id, usuario_id, alias, tipo, direccion, habitaciones, banos, medios_banos, pisos) VALUES (1,1,'Casa Ensayo','CASA','Calle Ensayo 1',2,1,0,1)");
  await c.ejecutar(
    "INSERT INTO solicitudes (id, cliente_id, servicio_id, inmueble_id, fecha_hora_programada, direccion_servicio, precio_estimado, estado) VALUES (1,1,1,1,'2026-12-01 15:00:00','Calle Ensayo 1',400.00,'CANCELADO'),(2,1,1,NULL,'2026-12-02 15:00:00','Otra calle 2',400.00,'EN_PROCESO')",
  );
  const motivos = ["OTRO_TRABAJADOR_ACEPTO", "CLIENTE_CANCELO", "CAMBIO_A_AUTOMATICA", "TRABAJADOR_OCUPADO", "TRABAJADOR_CANCELO", "TRABAJADOR_DADO_DE_BAJA"];
  for (const [i, m] of motivos.entries()) {
    await c.ejecutar("INSERT INTO solicitud_trabajadores (solicitud_id, trabajador_id, origen, estado, motivo_cierre) VALUES (1, ?, 'INVITACION', 'CERRADA', ?)", [i + 1, m]);
  }
  await c.ejecutar("INSERT INTO solicitud_trabajadores (solicitud_id, trabajador_id, origen, estado) VALUES (1, 7, 'BOLSA', 'RECHAZADA')");
  await c.ejecutar(
    "INSERT INTO admin_permisos (id, usuario_id, permiso, origen, motivo) VALUES (1,2,'ADMINISTRAR_PERMISOS','ASIGNACION_INICIAL','Propietario de ensayo'),(2,2,'MODERAR_CONTENIDO','ASIGNACION_INICIAL','Propietario de ensayo')",
  );
  await c.ejecutar(
    "INSERT INTO admin_permisos (id, usuario_id, permiso, origen, otorgado_por) VALUES (3,3,'GESTIONAR_INCIDENCIAS_FINANZAS','OTORGADO_POR_ADMIN',2),(4,3,'REVISAR_DOCUMENTOS_IDENTIDAD','OTORGADO_POR_ADMIN',2)",
  );
  await c.ejecutar(
    "INSERT INTO solicitud_resoluciones (id, solicitud_id, admin_id, admin_permiso_id, resultado_servicio, motivo) VALUES (1,1,3,3,'NO_REALIZADO','Resolución anterior al 004')",
  );
}

async function main() {
  const previa = await conectar(null);
  try {
    await verificarQueEsLocal(previa.consultar, BD_LOCAL.host);
    await activarChecksLocales(previa.ejecutar);
  } finally {
    await previa.cerrar();
  }
  const servidor = await conectar(null);
  try {
    const version = await verificarQueEsLocal(servidor.consultar, BD_LOCAL.host);
    const { sentencias } = await construirBdLocal(servidor.consultar, servidor.ejecutar, BD_LOCAL_PRUEBAS, { recrear: true, archivos: BASE });
    anotar("1. BD de pruebas sin el 004", true, `${version}; ${sentencias} sentencias (000 + 002 v10 + 003 v2)`);
  } finally {
    await servidor.cerrar();
  }

  const c = await conectar(BD_LOCAL_PRUEBAS);
  try {
    const [bd] = await c.consultar("SELECT DATABASE() AS bd");
    if (bd?.bd !== BD_LOCAL_PRUEBAS) throw new Error(`Conectado a ${String(bd?.bd)}: se aborta`);
    await cargarDatosAnteriores(c);
    anotar("2. Datos anteriores", true, "7 invitaciones (los 6 motivos previos), 4 permisos (los 4 valores previos), 2 solicitudes, 1 resolución");

    const columnasPrevias = { solicitudes: await columnas(c, "solicitudes"), solicitud_resoluciones: await columnas(c, "solicitud_resoluciones") };
    const antes = await huellasDeDatos(c.consultar);
    anotar("3. Huella de datos", true, `${Object.keys(antes).length} tablas`);

    const n = await aplicar(c, "004_ciclo_solicitudes.sql");
    const despues = await huellasDeDatos(c.consultar, undefined, columnasPrevias);
    const distintas = Object.keys(antes).filter((t) => JSON.stringify(antes[t]) !== JSON.stringify(despues[t]));
    anotar("4. Aplicar el 004", distintas.length === 0, `${n} sentencias; tablas con datos distintos: ${distintas.length ? distintas.join(", ") : "ninguna"}`);

    const permisos = await c.consultar("SELECT permiso FROM admin_permisos ORDER BY id");
    anotar(
      "4b. Valores previos intactos",
      permisos.map((p) => p.permiso).join(",") === "ADMINISTRAR_PERMISOS,MODERAR_CONTENIDO,GESTIONAR_INCIDENCIAS_FINANZAS,REVISAR_DOCUMENTOS_IDENTIDAD",
    );
    const alias = await c.consultar("SELECT COUNT(*) AS n FROM solicitudes WHERE inmueble_alias_aplicado IS NOT NULL");
    anotar("4c. Solicitudes existentes sin alias (no se rellenan)", Number(alias[0]?.n) === 0);

    await c.ejecutar("INSERT INTO admin_permisos (id, usuario_id, permiso, origen, otorgado_por) VALUES (10,3,'SUPERVISAR_SOLICITUDES','OTORGADO_POR_ADMIN',2)");
    anotar("5a. Permiso SUPERVISAR_SOLICITUDES", true);
    await esperarError(c, "INSERT INTO admin_permisos (usuario_id, permiso, origen, otorgado_por) VALUES (2,'SUPERVISAR_SOLICITUDES','OTORGADO_POR_ADMIN',2)", /chk_permiso_otorgamiento|3819/);
    anotar("5b. Nadie se otorga SUPERVISAR a sí mismo (CHECK)", true);
    await esperarError(c, "INSERT INTO admin_permisos (usuario_id, permiso, origen, otorgado_por) VALUES (3,'SUPERVISAR_SOLICITUDES','OTORGADO_POR_ADMIN',2)", /Duplicate|uq_permiso_activo|1062/);
    anotar("5c. Un solo SUPERVISAR vigente por admin (UNIQUE)", true);
    await c.ejecutar("INSERT INTO solicitud_trabajadores (id, solicitud_id, trabajador_id, origen, estado, motivo_cierre) VALUES (100, 2, 1, 'INVITACION', 'CERRADA', 'VENCIDA')");
    anotar("5d. motivo_cierre VENCIDA", true);
    await esperarError(c, "INSERT INTO solicitud_trabajadores (solicitud_id, trabajador_id, origen, estado, motivo_cierre) VALUES (2, 2, 'INVITACION', 'CERRADA', 'INVENTADO')", /Data truncated|1265|enum/i);
    anotar("5e. Un motivo inexistente se rechaza", true);
    await c.ejecutar(
      "INSERT INTO solicitudes (id, cliente_id, servicio_id, inmueble_id, inmueble_alias_aplicado, fecha_hora_programada, direccion_servicio, precio_estimado) VALUES (3,1,1,1,'Casa Ensayo','2026-12-03 15:00:00','Calle Ensayo 1',400.00)",
    );
    await c.ejecutar("UPDATE inmuebles SET alias = 'Casa renombrada', archivado_en = NOW() WHERE id = 1");
    const [snap] = await c.consultar("SELECT inmueble_alias_aplicado AS a FROM solicitudes WHERE id = 3");
    anotar("5f. El snapshot del alias no cambia al renombrar o archivar el inmueble", snap?.a === "Casa Ensayo");
    await esperarError(c, "DELETE FROM inmuebles WHERE id = 1", /foreign key|1451/i);
    anotar("5g. Un inmueble usado por solicitudes no se puede borrar (FK RESTRICT)", true);
    await c.ejecutar("INSERT INTO solicitud_resoluciones (id, solicitud_id, admin_id, admin_permiso_id, resultado_servicio, motivo) VALUES (2,2,3,3,'REALIZADO','Primera resolución')");
    const dup = await esperarError(
      c,
      "INSERT INTO solicitud_resoluciones (solicitud_id, admin_id, admin_permiso_id, resultado_servicio, motivo) VALUES (2,3,3,'NO_REALIZADO','Segunda resolución')",
      /Duplicate|uq_res_una_de_servicio|1062/,
    );
    anotar("5h. Segunda resolución de servicio rechazada (UNIQUE)", true, dup);
    await c.ejecutar("INSERT INTO solicitud_resoluciones (id, solicitud_id, admin_id, admin_permiso_id, resultado_pago, motivo) VALUES (3,2,3,3,'PAGADO','Solo pago (fase de dinero)')");
    anotar("5i. Una resolución solo de pago no ocupa el lugar de la de servicio", true);
    await esperarError(
      c,
      "INSERT INTO solicitud_resoluciones (solicitud_id, admin_id, admin_permiso_id, resultado_servicio, motivo) VALUES (1,3,3,'REALIZADO','Otra sobre la anterior al 004')",
      /Duplicate|uq_res_una_de_servicio|1062/,
    );
    anotar("5j. La resolución anterior al 004 también cuenta", true);

    // Rollback: primero se quitan las filas de prueba del paso 5 y se deshace el cambio al inmueble.
    await c.ejecutar("DELETE FROM solicitud_resoluciones WHERE id IN (2, 3)");
    await c.ejecutar("DELETE FROM solicitudes WHERE id = 3");
    await c.ejecutar("DELETE FROM solicitud_trabajadores WHERE id = 100");
    await c.ejecutar("DELETE FROM admin_permisos WHERE id = 10");
    await c.ejecutar("UPDATE inmuebles SET alias = 'Casa Ensayo', archivado_en = NULL WHERE id = 1");
    const usados = await c.consultar(
      "SELECT (SELECT COUNT(*) FROM admin_permisos WHERE permiso = 'SUPERVISAR_SOLICITUDES') AS p, (SELECT COUNT(*) FROM solicitud_trabajadores WHERE motivo_cierre = 'VENCIDA') AS v",
    );
    anotar("6a. Comprobación previa del rollback (valores nuevos sin usar)", Number(usados[0]?.p) === 0 && Number(usados[0]?.v) === 0);
    const r = await aplicar(c, "004_rollback.sql");
    const tras = await huellasDeDatos(c.consultar);
    const columnasTras = { solicitudes: await columnas(c, "solicitudes"), solicitud_resoluciones: await columnas(c, "solicitud_resoluciones") };
    // inmuebles.updated_at cambió por el UPDATE de prueba (ON UPDATE): esa tabla se compara sin esa columna.
    const sinUpdated = { inmuebles: ["id", "usuario_id", "alias", "tipo", "direccion", "habitaciones", "banos", "medios_banos", "pisos", "archivado_en", "created_at"] };
    const inmAntes = await huellasDeDatos(c.consultar, ["inmuebles"], sinUpdated);
    const distintasTras = Object.keys(antes).filter((t) => t !== "inmuebles" && JSON.stringify(antes[t]) !== JSON.stringify(tras[t]));
    anotar(
      "6b. Rollback",
      distintasTras.length === 0 && JSON.stringify(columnasTras) === JSON.stringify(columnasPrevias) && inmAntes.inmuebles!.filas === 1,
      `${r} sentencias; columnas como antes del 004; tablas distintas: ${distintasTras.length ? distintasTras.join(", ") : "ninguna"} (los valores nuevos de los ENUM se quedan: límite de TiDB)`,
    );
    const n2 = await aplicar(c, "004_ciclo_solicitudes.sql");
    anotar("7. Volver a aplicar el 004 tras el rollback", (await columnas(c, "solicitudes")).includes("inmueble_alias_aplicado"), `${n2} sentencias`);
  } finally {
    await c.cerrar();
  }
  console.log(`\nEnsayo del 004: ${resultados.filter((x) => x.ok).length}/${resultados.length} OK.`);
}

main().catch((error) => {
  console.error("ERROR:", (error as Error).message);
  process.exit(1);
});
