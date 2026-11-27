/**
 * Objetos que agrega el SQL 003 (v1) y precondiciones para aplicarlo. SOLO LECTURA.
 * Mantener sincronizado con docs/backend/sql/003_notificaciones_unicas_permisos_admin.sql
 */
import type { Consulta } from "./db-directa";
import { verificar002 } from "./objetos-002";

export const TABLA_NUEVA_003 = "admin_permisos";

export const COLUMNAS_NUEVAS_003: [string, string][] = [
  ["notificaciones", "clave_evento"],
  ["notificaciones_trabajador", "clave_evento"],
  ["solicitudes", "reporte_pago_hasta"],
  ["solicitud_resoluciones", "admin_permiso_id"],
  ["trabajador_movimientos", "resolucion_de_ajuste"],
];

export const INDICES_003: [string, string][] = [
  ["notificaciones", "uq_notif_evento"],
  ["notificaciones_trabajador", "uq_notif_trab_evento"],
  ["solicitud_resoluciones", "idx_res_permiso"],
];

export const PARAMETRO_003 = "HORAS_PLAZO_REPORTE_PAGO";

export type ResultadoVerificacion003 = {
  bd: string;
  presentes: number;
  total: number;
  estado: "NO APLICADO" | "APLICADO COMPLETO" | "APLICADO A MEDIAS";
  /** El 002 está completo (84/84). Sin esto el 003 no se puede aplicar. */
  requiere002Ok: boolean;
  /** Motivos por los que NO se debe aplicar todavía (vacío = se puede). */
  bloqueos: string[];
  /** Notificaciones existentes que recibirán la clave 'LEGADO:<id>'. */
  notificacionesALegado: number;
  lineas: string[];
};

export async function verificar003(q: Consulta): Promise<ResultadoVerificacion003> {
  const lineas: string[] = [];
  const [info] = await q<{ bd: string }>("SELECT DATABASE() AS bd");
  const r002 = await verificar002(q);
  const requiere002Ok = r002.estado === "APLICADO COMPLETO";

  const tablas = new Set(
    (await q<{ t: string }>("SELECT TABLE_NAME AS t FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()")).map((r) => r.t),
  );
  const columnas = new Map(
    (
      await q<{ k: string; nulo: string }>(
        `SELECT CONCAT(TABLE_NAME, '.', COLUMN_NAME) AS k, IS_NULLABLE AS nulo
         FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()`,
      )
    ).map((r) => [r.k, r]),
  );
  const indices = new Set(
    (
      await q<{ k: string }>(
        `SELECT DISTINCT CONCAT(TABLE_NAME, '.', INDEX_NAME) AS k FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE()`,
      )
    ).map((r) => r.k),
  );
  const ddl = async (t: string) =>
    tablas.has(t) ? ((await q<Record<string, string>>("SHOW CREATE TABLE `" + t + "`"))[0]?.["Create Table"] ?? "") : "";

  let presentes = 0;
  let total = 0;
  const contar = (ok: boolean, texto: string) => {
    total++;
    if (ok) presentes++;
    lineas.push(`  ${ok ? "sí" : "no"}  ${texto}`);
  };

  lineas.push(`Requisito — SQL 002 completo: ${requiere002Ok ? "sí" : "NO"} (${r002.presentes}/${r002.total})`, "", "Objetos del 003:");
  contar(tablas.has(TABLA_NUEVA_003), `tabla ${TABLA_NUEVA_003}`);
  for (const [t, c] of COLUMNAS_NUEVAS_003) contar(columnas.has(`${t}.${c}`), `columna ${t}.${c}`);
  for (const [t, i] of INDICES_003) contar(indices.has(`${t}.${i}`), `índice ${t}.${i}`);
  const ddlResoluciones = await ddl("solicitud_resoluciones");
  contar(ddlResoluciones.includes("`fk_res_permiso`"), "FK compuesta solicitud_resoluciones.fk_res_permiso");
  contar(columnas.get("solicitud_resoluciones.admin_id")?.nulo === "NO", "solicitud_resoluciones.admin_id NOT NULL");
  const reglaAdmin = tablas.has("solicitud_resoluciones")
    ? (
        await q<{ regla: string }>(
          `SELECT DELETE_RULE AS regla FROM information_schema.REFERENTIAL_CONSTRAINTS
           WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'solicitud_resoluciones' AND CONSTRAINT_NAME = 'fk_res_admin'`,
        )
      )[0]?.regla
    : undefined;
  contar(reglaAdmin === "RESTRICT" || reglaAdmin === "NO ACTION", `fk_res_admin ON DELETE ${reglaAdmin ?? "?"} (se espera RESTRICT)`);
  contar((await ddl("trabajador_movimientos")).includes("`chk_mov_ajuste_con_resolucion`"), "CHECK chk_mov_ajuste_con_resolucion");
  const parametro = tablas.has("parametros_negocio")
    ? (await q<{ n: bigint | number }>("SELECT COUNT(*) AS n FROM parametros_negocio WHERE clave = ?", [PARAMETRO_003]))[0]
    : undefined;
  contar(Number(parametro?.n ?? 0) === 1, `parámetro ${PARAMETRO_003}`);

  const estado = presentes === 0 ? "NO APLICADO" : presentes === total ? "APLICADO COMPLETO" : "APLICADO A MEDIAS";

  // Precondiciones (solo importan si todavía no se aplicó).
  const bloqueos: string[] = [];
  let notificacionesALegado = 0;
  if (estado !== "APLICADO COMPLETO") {
    if (!requiere002Ok) bloqueos.push("el SQL 002 no está aplicado completo");
    const contarFilas = async (sql: string) => Number((await q<{ n: bigint | number }>(sql))[0]?.n ?? 0);
    if (tablas.has("solicitud_resoluciones")) {
      const n = await contarFilas("SELECT COUNT(*) AS n FROM solicitud_resoluciones");
      if (n) bloqueos.push(`hay ${n} resoluciones sin permiso al que atribuirlas`);
    }
    if (tablas.has("trabajador_movimientos")) {
      const n = await contarFilas("SELECT COUNT(*) AS n FROM trabajador_movimientos WHERE tipo = 'AJUSTE'");
      if (n) bloqueos.push(`hay ${n} movimientos AJUSTE sin resolución`);
    }
    for (const t of ["notificaciones", "notificaciones_trabajador"]) {
      if (tablas.has(t) && !columnas.has(`${t}.clave_evento`)) notificacionesALegado += await contarFilas(`SELECT COUNT(*) AS n FROM \`${t}\``);
    }
    lineas.push("", "Precondiciones para aplicar el 003:");
    lineas.push(...(bloqueos.length ? bloqueos.map((b) => `  NO ⚠  ${b}`) : ["  sí  se puede aplicar"]));
    lineas.push(`  notificaciones existentes que recibirán clave 'LEGADO:<id>': ${notificacionesALegado}`);
  }

  lineas.push("", `Resultado: ${presentes}/${total} objetos del 003 presentes → ${estado}`);
  return { bd: info?.bd ?? "?", presentes, total, estado, requiere002Ok, bloqueos, notificacionesALegado, lineas };
}
