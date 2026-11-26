import type { solicitud_reportes, solicitud_reportes_tipo } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { almacenamiento, segundosUrlTemporal, validarArchivo, type ObjetoGuardado } from "../shared/almacenamiento";
import { AppError } from "../shared/errors/AppError";
import { relojDominio } from "./reloj";

/**
 * REPORTES entre usuarios (doc 20 §3), independientes de las reseñas.
 *  - El cliente reporta al trabajador y el trabajador al cliente, sobre UNA solicitud.
 *  - Desde la hora programada (D57), aunque el servicio no haya terminado; no exige reseña.
 *  - Descripción y fotos opcionales. Fotos: máx. 5, 8 MB c/u y 16 MB en total (1 MB =
 *    1 000 000 bytes, X3); JPEG, PNG o WebP según su CONTENIDO real (X2), sin GPS.
 *  - Visibilidad (X6): el reporte completo solo lo ven quien lo creó y los admins con
 *    MODERAR_CONTENIDO. El reportado no tiene ninguna ruta para verlo ni para saber quién fue.
 *  - D57/X5: un reporte activo (no RESUELTO y no eliminado) bloquea la confirmación automática;
 *    uno eliminado lógicamente, no.
 */

export const LIMITES_FOTOS = { cantidad: 5, bytesPorFoto: 8_000_000, bytesTotales: 16_000_000 } as const;
const TIPOS: readonly solicitud_reportes_tipo[] = ["NO_SE_PUDO_COMPLETAR", "INASISTENCIA", "PROBLEMA_UBICACION", "UBICACION_FALSA", "PAGO_EN_DISPUTA", "OTRO"];

export type RolReportante = "CLIENTE" | "TRABAJADOR";
export type ArchivoRecibido = { contenido: Buffer; nombreOriginal: string; mimeDeclarado?: string };

export function leerTipo(valor: unknown, opcional: true): solicitud_reportes_tipo | undefined;
export function leerTipo(valor: unknown, opcional: false): solicitud_reportes_tipo;
export function leerTipo(valor: unknown, opcional: boolean): solicitud_reportes_tipo | undefined {
  if (valor === undefined || valor === null || valor === "") {
    if (opcional) return undefined;
    throw new AppError(400, "Indica el tipo de reporte", "TIPO_REQUERIDO");
  }
  if (typeof valor !== "string" || !TIPOS.includes(valor as solicitud_reportes_tipo)) {
    throw new AppError(400, `Tipo de reporte no válido. Usa: ${TIPOS.join(", ")}`, "TIPO_INVALIDO");
  }
  return valor as solicitud_reportes_tipo;
}

export function leerDescripcion(valor: unknown): string | null {
  if (valor === undefined || valor === null) return null;
  if (typeof valor !== "string") throw new AppError(400, "La descripción debe ser texto", "DESCRIPCION_INVALIDA");
  return valor.trim() || null;
}

/** Valida cantidad, tamaño por foto, total y tipo REAL de cada foto (antes de guardar nada). */
export function validarFotos(archivos: ArchivoRecibido[]) {
  if (archivos.length > LIMITES_FOTOS.cantidad) {
    throw new AppError(400, `Un reporte admite como máximo ${LIMITES_FOTOS.cantidad} fotografías`, "DEMASIADAS_FOTOS");
  }
  let total = 0;
  for (const a of archivos) {
    if (a.contenido.length > LIMITES_FOTOS.bytesPorFoto) {
      throw new AppError(413, "Cada fotografía puede pesar como máximo 8 MB", "FOTO_DEMASIADO_GRANDE");
    }
    total += a.contenido.length;
  }
  if (total > LIMITES_FOTOS.bytesTotales) {
    throw new AppError(413, "Las fotografías de un reporte pueden sumar como máximo 16 MB", "REPORTE_DEMASIADO_GRANDE");
  }
  return archivos.map((a) =>
    validarArchivo(a.contenido, { proposito: "EVIDENCIA", nombreOriginal: a.nombreOriginal, mimeDeclarado: a.mimeDeclarado, maxBytes: LIMITES_FOTOS.bytesPorFoto }),
  );
}

type ReporteConEvidencias = solicitud_reportes & {
  evidencias_solicitud: { id: number; tipo_mime: string | null; tamano_bytes: number | null; eliminada_en: Date | null }[];
};

/** El reporte tal como lo ve QUIEN LO CREÓ. */
export function dtoReportePropio(r: ReporteConEvidencias) {
  return {
    id: r.id,
    solicitudId: r.solicitud_id,
    reportaA: r.reportado_por === "CLIENTE" ? "TRABAJADOR" : "CLIENTE",
    tipo: r.tipo,
    descripcion: r.descripcion,
    estado: r.estado,
    fecha: r.created_at.toISOString(),
    eliminadoPorModeracion: r.eliminado_en !== null,
    evidencias: r.evidencias_solicitud
      .filter((e) => e.eliminada_en === null)
      .map((e) => ({ id: e.id, tipoMime: e.tipo_mime, tamanoBytes: e.tamano_bytes })),
  };
}

/** Crea el reporte y sus fotos. La identidad sale del token; el reportado, de la solicitud. */
export async function crearReporte(datos: {
  solicitudId: number;
  rol: RolReportante;
  autorId: number;
  tipo?: solicitud_reportes_tipo;
  descripcion: string | null;
  archivos: ArchivoRecibido[];
}) {
  const solicitud = await prisma.solicitudes.findUnique({
    where: { id: datos.solicitudId },
    select: { id: true, cliente_id: true, trabajador_id: true, fecha_hora_programada: true, reporte_pago_hasta: true },
  });
  if (!solicitud) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  const esParte = datos.rol === "CLIENTE" ? solicitud.cliente_id === datos.autorId : solicitud.trabajador_id === datos.autorId;
  if (!esParte) throw new AppError(403, "Solo las partes del servicio pueden reportarlo", "NO_ES_PARTE");
  const ahora = relojDominio.ahora();
  if (ahora.getTime() < solicitud.fecha_hora_programada.getTime()) {
    throw new AppError(409, "Podrás reportar a partir de la hora programada del servicio", "REPORTE_ANTES_DE_HORA");
  }
  if (datos.rol === "CLIENTE" && solicitud.trabajador_id === null) {
    throw new AppError(409, "El servicio no tiene un trabajador asignado al que reportar", "SIN_CONTRAPARTE");
  }
  const tipo = datos.tipo ?? "OTRO";
  if (tipo === "PAGO_EN_DISPUTA") {
    // D59/D61: solo el trabajador, y solo dentro del plazo guardado en reporte_pago_hasta.
    if (datos.rol !== "TRABAJADOR") throw new AppError(400, "Solo el trabajador puede reportar un pago en disputa", "TIPO_NO_PERMITIDO_PARA_ROL");
    if (!solicitud.reporte_pago_hasta || ahora.getTime() > solicitud.reporte_pago_hasta.getTime()) {
      throw new AppError(409, "El plazo para reportar el pago ya venció o no aplica", "PLAZO_REPORTE_PAGO_VENCIDO");
    }
  }

  const validados = validarFotos(datos.archivos);
  const guardados: ObjetoGuardado[] = [];
  try {
    for (const archivo of validados) guardados.push(await almacenamiento().guardar("evidencias", `solicitud-${solicitud.id}`, archivo));
    const creado = await prisma.$transaction(async (tx) => {
      // Se bloquea la solicitud: así la tarea periódica (D54) y la resolución del admin no se cruzan
      // con un reporte nuevo (con un reporte activo no se confirma automáticamente, D57).
      await tx.$queryRaw`SELECT id FROM solicitudes WHERE id = ${solicitud.id} FOR UPDATE`;
      const reporte = await tx.solicitud_reportes.create({
        data: {
          solicitud_id: solicitud.id,
          reportado_por: datos.rol,
          cliente_id: datos.rol === "CLIENTE" ? datos.autorId : null,
          trabajador_id: datos.rol === "TRABAJADOR" ? datos.autorId : null,
          reportado_cliente_id: datos.rol === "TRABAJADOR" ? solicitud.cliente_id : null,
          reportado_trabajador_id: datos.rol === "CLIENTE" ? solicitud.trabajador_id : null,
          tipo,
          descripcion: datos.descripcion,
          created_at: ahora,
        },
      });
      for (const g of guardados) {
        await tx.evidencias_solicitud.create({
          data: {
            solicitud_id: solicitud.id,
            reporte_id: reporte.id,
            aportada_por: datos.rol,
            archivo_url: g.clave,
            tipo_mime: g.mime,
            tamano_bytes: g.bytes,
            sha256: g.sha256,
          },
        });
      }
      return tx.solicitud_reportes.findUniqueOrThrow({
        where: { id: reporte.id },
        include: { evidencias_solicitud: { select: { id: true, tipo_mime: true, tamano_bytes: true, eliminada_en: true } } },
      });
    });
    return dtoReportePropio(creado);
  } catch (error) {
    // Si la BD falla, no quedan archivos huérfanos.
    await Promise.all(guardados.map((g) => almacenamiento().eliminar(g.clave).catch(() => undefined)));
    throw error;
  }
}

function filtroPropios(rol: RolReportante, autorId: number) {
  return rol === "CLIENTE" ? { reportado_por: "CLIENTE" as const, cliente_id: autorId } : { reportado_por: "TRABAJADOR" as const, trabajador_id: autorId };
}

const CON_EVIDENCIAS = { evidencias_solicitud: { select: { id: true, tipo_mime: true, tamano_bytes: true, eliminada_en: true } } } as const;

/** Reportes que creó el usuario. */
export async function reportesPropios(rol: RolReportante, autorId: number) {
  const filas = await prisma.solicitud_reportes.findMany({ where: filtroPropios(rol, autorId), include: CON_EVIDENCIAS, orderBy: { id: "desc" } });
  return filas.map(dtoReportePropio);
}

/** Un reporte propio. Si no es suyo (p. ej. el reportado), 404: ni siquiera se confirma que exista. */
export async function reportePropio(rol: RolReportante, autorId: number, reporteId: number) {
  const fila = await prisma.solicitud_reportes.findFirst({ where: { id: reporteId, ...filtroPropios(rol, autorId) }, include: CON_EVIDENCIAS });
  if (!fila) throw new AppError(404, "No existe ese reporte", "REPORTE_NO_ENCONTRADO");
  return dtoReportePropio(fila);
}

/** URL TEMPORAL de una foto de un reporte propio (no eliminada). */
export async function urlEvidenciaPropia(rol: RolReportante, autorId: number, reporteId: number, evidenciaId: number) {
  const reporte = await prisma.solicitud_reportes.findFirst({ where: { id: reporteId, ...filtroPropios(rol, autorId) }, select: { id: true } });
  if (!reporte) throw new AppError(404, "No existe ese reporte", "REPORTE_NO_ENCONTRADO");
  return urlDeEvidencia(reporteId, evidenciaId);
}

export async function urlDeEvidencia(reporteId: number, evidenciaId: number) {
  const evidencia = await prisma.evidencias_solicitud.findFirst({
    where: { id: evidenciaId, reporte_id: reporteId, eliminada_en: null },
    select: { archivo_url: true, tipo_mime: true },
  });
  if (!evidencia || !evidencia.tipo_mime) throw new AppError(404, "No existe esa fotografía", "EVIDENCIA_NO_ENCONTRADA");
  const segundos = segundosUrlTemporal("otros");
  const url = await almacenamiento().urlTemporal(evidencia.archivo_url, { mime: evidencia.tipo_mime as "image/jpeg", segundos });
  return { url, expiraEnSegundos: segundos };
}

/**
 * D57 + X5: ¿hay reportes que impiden confirmar AUTOMÁTICAMENTE el servicio? Cuentan los no
 * RESUELTOS y NO eliminados. La tarea periódica de confirmación (Fase 4) debe usar esta función.
 */
export async function bloqueaConfirmacionAutomatica(solicitudId: number): Promise<boolean> {
  const n = await prisma.solicitud_reportes.count({ where: { solicitud_id: solicitudId, estado: { not: "RESUELTO" }, eliminado_en: null } });
  return n > 0;
}

export function esTipoReporte(valor: string): valor is solicitud_reportes_tipo {
  return TIPOS.includes(valor as solicitud_reportes_tipo);
}

