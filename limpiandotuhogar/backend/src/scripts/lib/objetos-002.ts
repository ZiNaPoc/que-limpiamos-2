/**
 * Objetos que agrega el SQL 002 (v10) y comprobación de cuáles existen. SOLO LECTURA.
 * Mantener sincronizado con docs/backend/sql/002_detalle_solicitud_especialidades_invitaciones.sql
 */
import type { Consulta } from "./db-directa";

export const TABLAS_NUEVAS_002 = [
  "especialidades",
  "areas_limpieza",
  "servicios_extra",
  "servicio_calculo",
  "servicio_calculo_tipo_inmueble",
  "reglas_cargo_cancelacion",
  "parametros_negocio",
  "descuentos",
  "descuento_servicios",
  "trabajador_especialidades",
  "servicio_especialidades",
  "extra_especialidades",
  "solicitud_areas",
  "solicitud_extras",
  "solicitud_especialidades",
  "solicitud_trabajadores",
  "solicitud_historial",
  "descuento_usos",
  "cliente_adeudos",
  "solicitud_resoluciones",
  "solicitud_reportes",
  "trabajador_movimientos",
  "trabajador_estado_historial",
  "notificaciones_trabajador",
];

export const COLUMNAS_NUEVAS_002: [string, string][] = [
  ...[
    "servicio_nombre_aplicado",
    "inmueble_tipo_aplicado",
    "habitaciones_aplicado",
    "banos_aplicado",
    "medios_banos_aplicado",
    "pisos_aplicado",
    "duracion_estimada_min",
    "fecha_hora_fin_estimada",
    "notas",
    "precio_base_aplicado",
    "precio_tamano_aplicado",
    "precio_ajuste_tipo_aplicado",
    "precio_extras_aplicado",
    "precio_descuento_aplicado",
    "porcentaje_trabajador_aplicado",
    "ganancia_trabajador",
    "comision_plataforma",
    "cargo_cancelacion",
    "metodo_pago",
    "adeudo_cobrado",
    "estado_pago",
    "pago_registrado_en",
    "pago_registrado_por",
    "trabajador_marco_realizado_en",
    "cliente_marco_realizado_en",
    "confirmacion_solicitada_en",
    "aviso_evidencia_en",
    "realizado_en",
    "realizado_via",
    "ganancia_liberada_en",
    "modo_eleccion",
  ].map((c): [string, string] => ["solicitudes", c]),
  ["inmuebles", "archivado_en"],
  ["usuarios", "identidad_huella"],
  ["usuarios", "identidad_registrada_en"],
  ...[
    "estado_verificacion",
    "mostrar_fuera_de_horario",
    "baja_en",
    "baja_tipo",
    "baja_motivo",
    "identidad_huella",
    "identidad_registrada_en",
  ].map((c): [string, string] => ["trabajadores", c]),
  ...["estado", "motivo_rechazo", "revisado_en", "revisado_por", "archivo_eliminado_en"].flatMap((c): [string, string][] => [
    ["documentos_cliente", c],
    ["documentos_trabajador", c],
  ]),
  ["notificaciones", "leida_en"],
  ["evidencias_solicitud", "aportada_por"],
  ["evidencias_solicitud", "reporte_id"],
];

/** Enums existentes a los que el 002 agrega valores: [tabla, columna, valor nuevo]. */
export const ENUMS_AMPLIADOS_002: [string, string, string][] = [
  ["notificaciones", "tipo", "REPORTE_RESUELTO"],
  ["trabajadores", "estado", "BAJA"],
];

/** Cambio de índices en trabajador_horarios (varias franjas por día). */
export const INDICES_002 = {
  tabla: "trabajador_horarios",
  nuevo: "idx_horario_trabajador_dia",
  quitado: "uq_horario_dia",
};

/** Restricciones CHECK nuevas: [tabla, nombre]. */
export const CHECKS_002: [string, string][] = [
  ["usuarios", "chk_usuario_cliente_telefono"],
  ["trabajador_movimientos", "chk_mov_referencia_obligatoria"],
];

/** Precondición: estos updated_at ya tienen ON UPDATE CURRENT_TIMESTAMP (el 002 no los toca). */
export const UPDATED_AT_PREEXISTENTES = ["servicios", "solicitudes", "trabajadores", "inmuebles"];

/** Tablas existentes que el 002 altera o a las que referencia (para contar filas). */
export const TABLAS_EXISTENTES_TOCADAS_002 = [
  "solicitudes",
  "inmuebles",
  "notificaciones",
  "servicios",
  "usuarios",
  "trabajadores",
  "documentos_cliente",
  "documentos_trabajador",
  "evidencias_solicitud",
];

export type ResultadoVerificacion = {
  bd: string;
  motor: string;
  presentes: number;
  total: number;
  estado: "NO APLICADO" | "APLICADO COMPLETO" | "APLICADO A MEDIAS";
  precondicionOk: boolean;
  lineas: string[];
};

export async function verificar002(q: Consulta): Promise<ResultadoVerificacion> {
  const lineas: string[] = [];
  const [info] = await q<{ bd: string; motor: string }>("SELECT DATABASE() AS bd, VERSION() AS motor");

  const tablas = new Set(
    (await q<{ t: string }>("SELECT TABLE_NAME AS t FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()")).map(
      (r) => r.t,
    ),
  );
  const columnas = new Map(
    (
      await q<{ k: string; extra: string | null; ty: string }>(
        `SELECT CONCAT(TABLE_NAME, '.', COLUMN_NAME) AS k, EXTRA AS extra, COLUMN_TYPE AS ty
         FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()`,
      )
    ).map((r) => [r.k, r]),
  );

  let presentes = 0;
  let total = 0;
  const marca = (ok: boolean) => (ok ? "existe   " : "no existe");

  lineas.push("Tablas nuevas:");
  for (const t of TABLAS_NUEVAS_002) {
    const ok = tablas.has(t);
    total++;
    if (ok) presentes++;
    lineas.push(`  ${marca(ok)}  ${t}`);
  }

  lineas.push("", "Columnas nuevas en tablas existentes:");
  for (const [t, c] of COLUMNAS_NUEVAS_002) {
    const ok = columnas.has(`${t}.${c}`);
    total++;
    if (ok) presentes++;
    lineas.push(`  ${marca(ok)}  ${t}.${c}`);
  }

  lineas.push("", "Enums existentes ampliados:");
  for (const [t, c, valor] of ENUMS_AMPLIADOS_002) {
    const ty = columnas.get(`${t}.${c}`)?.ty ?? "";
    const ok = ty.includes(`'${valor}'`);
    total++;
    if (ok) presentes++;
    lineas.push(`  ${ok ? "sí" : "no"}  ${t}.${c} → ${ty || "?"}`);
  }

  const indices = new Set(
    (
      await q<{ i: string }>(
        "SELECT DISTINCT INDEX_NAME AS i FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?",
        [INDICES_002.tabla],
      )
    ).map((r) => r.i),
  );
  lineas.push("", "Índices de trabajador_horarios (varias franjas por día):");
  const nuevoOk = indices.has(INDICES_002.nuevo);
  const quitadoOk = !indices.has(INDICES_002.quitado);
  total += 2;
  presentes += Number(nuevoOk) + Number(quitadoOk);
  lineas.push(`  ${nuevoOk ? "sí" : "no"}  existe ${INDICES_002.nuevo}`);
  lineas.push(`  ${quitadoOk ? "sí" : "no"}  ya no existe ${INDICES_002.quitado}`);

  lineas.push("", "Restricciones CHECK nuevas:");
  for (const [t, nombre] of CHECKS_002) {
    // La tabla puede no existir todavía (p. ej. trabajador_movimientos antes del 002).
    const filas = tablas.has(t) ? await q<Record<string, string>>("SHOW CREATE TABLE `" + t + "`") : [];
    const ok = (filas[0]?.["Create Table"] ?? "").includes("`" + nombre + "`");
    total++;
    if (ok) presentes++;
    lineas.push(`  ${marca(ok)}  ${t}.${nombre}`);
  }

  let precondicionOk = true;
  lineas.push("", "Precondición — updated_at existentes con ON UPDATE CURRENT_TIMESTAMP:");
  for (const t of UPDATED_AT_PREEXISTENTES) {
    const extra = columnas.get(`${t}.updated_at`)?.extra ?? "";
    const ok = /on update/i.test(extra);
    if (!ok) precondicionOk = false;
    lineas.push(`  ${ok ? "sí" : "NO ⚠"}  ${t}.updated_at (${extra || "sin ON UPDATE"})`);
  }

  lineas.push("", "Filas en tablas existentes que el 002 toca (no se modifican):");
  for (const t of TABLAS_EXISTENTES_TOCADAS_002) {
    const [conteo] = await q<{ n: bigint | number }>(`SELECT COUNT(*) AS n FROM \`${t}\``);
    lineas.push(`  ${t}: ${conteo ? Number(conteo.n) : "?"}`);
  }

  const estado = presentes === 0 ? "NO APLICADO" : presentes === total ? "APLICADO COMPLETO" : "APLICADO A MEDIAS";
  lineas.push("", `Resultado: ${presentes}/${total} objetos presentes → ${estado}`);

  return {
    bd: info?.bd ?? "?",
    motor: info?.motor ?? "?",
    presentes,
    total,
    estado,
    precondicionOk,
    lineas,
  };
}
