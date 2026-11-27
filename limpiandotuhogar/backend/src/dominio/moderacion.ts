import type { Prisma, solicitud_reportes_estado, solicitud_reportes_tipo } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { AppError } from "../shared/errors/AppError";
import { registrarEvento, type Tx } from "./auditoria";
import { exigirPermiso, MODERAR_CONTENIDO } from "./permisos";
import { relojDominio } from "./reloj";
import { leerDatosResena } from "./resenas";
import { urlDeEvidencia } from "./reportes";

/**
 * MODERACIÓN (doc 20 §4–§5). Solo para admins con MODERAR_CONTENIDO (el permiso se vuelve a
 * comprobar DENTRO de cada transacción, con FOR UPDATE). Toda modificación: borrado LÓGICO,
 * motivo obligatorio y un evento en moderacion_eventos en la MISMA transacción. Estas son las
 * únicas vistas que muestran al AUTOR de una reseña (X0).
 */

type Participante = { id: string; rol: "CLIENTE" | "TRABAJADOR"; nombre: string };

async function nombres(clienteIds: number[], trabajadorIds: number[]) {
  const [clientes, trabajadores] = await Promise.all([
    prisma.usuarios.findMany({ where: { id: { in: [...new Set(clienteIds)] } }, select: { id: true, nombre_completo: true } }),
    prisma.trabajadores.findMany({ where: { id: { in: [...new Set(trabajadorIds)] } }, select: { id: true, nombre_completo: true } }),
  ]);
  const c = new Map(clientes.map((x) => [x.id, x.nombre_completo]));
  const t = new Map(trabajadores.map((x) => [x.id, x.nombre_completo]));
  return {
    cliente: (id: number): Participante => ({ id: String(id), rol: "CLIENTE", nombre: c.get(id) ?? `Cliente ${id}` }),
    trabajador: (id: number): Participante => ({ id: String(id), rol: "TRABAJADOR", nombre: t.get(id) ?? `Trabajador ${id}` }),
  };
}

async function servicios(solicitudIds: number[]) {
  const filas = await prisma.solicitudes.findMany({
    where: { id: { in: [...new Set(solicitudIds)] } },
    select: { id: true, estado: true, servicio_nombre_aplicado: true, servicios: { select: { nombre: true } } },
  });
  return new Map(filas.map((s) => [s.id, { nombre: s.servicio_nombre_aplicado ?? s.servicios.nombre, estado: s.estado }]));
}

// ── Reseñas ──────────────────────────────────────────────────────────────────
export type FiltrosResenas = { puntuacion?: number; autorRol?: "CLIENTE" | "TRABAJADOR"; trabajadorId?: number; clienteId?: number; incluirEliminadas?: boolean };

export async function listarResenas(f: FiltrosResenas) {
  const where: Prisma.resenasWhereInput = {
    ...(f.puntuacion ? { puntuacion: f.puntuacion } : {}),
    ...(f.autorRol ? { autor_rol: f.autorRol } : {}),
    ...(f.trabajadorId ? { trabajador_id: f.trabajadorId } : {}),
    ...(f.clienteId ? { cliente_id: f.clienteId } : {}),
    ...(f.incluirEliminadas ? {} : { eliminada_en: null }),
  };
  const filas = await prisma.resenas.findMany({ where, orderBy: { created_at: "desc" }, take: 500 });
  const n = await nombres(filas.map((r) => r.cliente_id), filas.map((r) => r.trabajador_id));
  const s = await servicios(filas.map((r) => r.solicitud_id));
  return filas.map((r) => {
    const cliente = n.cliente(r.cliente_id);
    const trabajador = n.trabajador(r.trabajador_id);
    return {
      id: String(r.id),
      idSolicitud: String(r.solicitud_id),
      servicio: s.get(r.solicitud_id)?.nombre ?? "",
      autor: r.autor_rol === "CLIENTE" ? cliente : trabajador,
      calificado: r.autor_rol === "CLIENTE" ? trabajador : cliente,
      puntuacion: r.puntuacion,
      comentario: r.comentario,
      fechaCreacion: r.created_at.toISOString(),
      editadaPorAdministracion: r.editada_en !== null,
      eliminada: r.eliminada_en !== null,
      eliminadaEn: r.eliminada_en?.toISOString() ?? null,
    };
  });
}

async function bloquearResena(tx: Tx, id: number) {
  const filas = await tx.$queryRaw<{ id: number }[]>`SELECT id FROM resenas WHERE id = ${id} FOR UPDATE`;
  if (!filas.length) throw new AppError(404, "No existe esa reseña", "RESENA_NO_ENCONTRADA");
  const r = await tx.resenas.findUniqueOrThrow({ where: { id } });
  if (r.eliminada_en) throw new AppError(409, "La reseña ya fue eliminada", "RESENA_ELIMINADA");
  return r;
}

/** Corrige calificación y/o comentario (p. ej. 1 estrella que debía ser 5). */
export async function editarResena(adminId: number, id: number, cambios: { puntuacion?: unknown; comentario?: unknown }, motivo: string) {
  if (cambios.puntuacion === undefined && cambios.comentario === undefined) {
    throw new AppError(400, "Indica la calificación o el comentario a corregir", "SIN_CAMBIOS");
  }
  return prisma.$transaction(async (tx) => {
    const permisoId = await exigirPermiso(tx, adminId, MODERAR_CONTENIDO, { bloquear: true });
    const actual = await bloquearResena(tx, id);
    const nuevos = leerDatosResena({
      puntuacion: cambios.puntuacion === undefined ? actual.puntuacion : cambios.puntuacion,
      comentario: cambios.comentario === undefined ? actual.comentario : cambios.comentario,
    });
    if (nuevos.puntuacion === actual.puntuacion && nuevos.comentario === actual.comentario) {
      throw new AppError(400, "No hay cambios que aplicar", "SIN_CAMBIOS");
    }
    const ahora = relojDominio.ahora();
    await tx.resenas.update({ where: { id }, data: { puntuacion: nuevos.puntuacion, comentario: nuevos.comentario, editada_en: ahora } });
    await registrarEvento(tx, {
      actor: { adminId, permisoId },
      objetivo: { entidad: "RESENA", resenaId: id },
      operacion: "EDITAR",
      antes: { puntuacion: actual.puntuacion, comentario: actual.comentario },
      despues: { puntuacion: nuevos.puntuacion, comentario: nuevos.comentario },
      motivo,
    });
    return { id: String(id), puntuacion: nuevos.puntuacion, comentario: nuevos.comentario, editadaEn: ahora.toISOString() };
  });
}

/** Borrado LÓGICO: la fila y su lugar único se conservan (X4); deja de contar en promedios. */
export async function eliminarResena(adminId: number, id: number, motivo: string) {
  return prisma.$transaction(async (tx) => {
    const permisoId = await exigirPermiso(tx, adminId, MODERAR_CONTENIDO, { bloquear: true });
    const actual = await bloquearResena(tx, id);
    const ahora = relojDominio.ahora();
    await tx.resenas.update({ where: { id }, data: { eliminada_en: ahora, eliminada_por: adminId } });
    await registrarEvento(tx, {
      actor: { adminId, permisoId },
      objetivo: { entidad: "RESENA", resenaId: id },
      operacion: "ELIMINAR",
      antes: { puntuacion: actual.puntuacion, comentario: actual.comentario, eliminada: false },
      despues: { eliminada: true, eliminada_en: ahora, eliminada_por: adminId },
      motivo,
    });
    return { id: String(id), eliminadaEn: ahora.toISOString() };
  });
}

// ── Reportes ─────────────────────────────────────────────────────────────────
export type FiltrosReportes = { id?: number; estado?: solicitud_reportes_estado; tipo?: solicitud_reportes_tipo; incluirEliminados?: boolean };

export async function listarReportes(f: FiltrosReportes) {
  const filas = await prisma.solicitud_reportes.findMany({
    where: { ...(f.id ? { id: f.id } : {}), ...(f.estado ? { estado: f.estado } : {}), ...(f.tipo ? { tipo: f.tipo } : {}), ...(f.incluirEliminados ? {} : { eliminado_en: null }) },
    include: { _count: { select: { evidencias_solicitud: { where: { eliminada_en: null } } } } },
    orderBy: { created_at: "desc" },
    take: 500,
  });
  const n = await nombres(
    filas.flatMap((r) => [r.cliente_id, r.reportado_cliente_id].filter((x): x is number => x !== null)),
    filas.flatMap((r) => [r.trabajador_id, r.reportado_trabajador_id].filter((x): x is number => x !== null)),
  );
  const s = await servicios(filas.map((r) => r.solicitud_id));
  return filas.map((r) => ({
    id: String(r.id),
    idSolicitud: String(r.solicitud_id),
    servicio: s.get(r.solicitud_id)?.nombre ?? "",
    reportante: r.reportado_por === "CLIENTE" ? n.cliente(r.cliente_id!) : n.trabajador(r.trabajador_id!),
    reportado: r.reportado_por === "CLIENTE" ? n.trabajador(r.reportado_trabajador_id!) : n.cliente(r.reportado_cliente_id!),
    tipo: r.tipo,
    descripcion: r.descripcion,
    estado: r.estado,
    fecha: r.created_at.toISOString(),
    cantidadFotos: r._count.evidencias_solicitud,
    editadoPorAdministracion: r.editado_en !== null,
    eliminado: r.eliminado_en !== null,
    // Doc 25 v2 §4: con la solicitud abierta, el reporte se resuelve con la resolución del servicio.
    estadoSolicitud: s.get(r.solicitud_id)?.estado ?? null,
    resolverConServicio: ["PENDIENTE", "CONFIRMADO", "EN_PROCESO"].includes(s.get(r.solicitud_id)?.estado ?? ""),
  }));
}

export async function detalleReporte(id: number) {
  const [base] = await listarReportes({ id, incluirEliminados: true });
  if (!base) throw new AppError(404, "No existe ese reporte", "REPORTE_NO_ENCONTRADO");
  const evidencias = await prisma.evidencias_solicitud.findMany({ where: { reporte_id: id }, orderBy: { id: "asc" } });
  const fotos = [];
  for (const e of evidencias) {
    fotos.push({
      id: String(e.id),
      tipoMime: e.tipo_mime,
      tamanoBytes: e.tamano_bytes,
      aportadaPor: e.aportada_por,
      eliminada: e.eliminada_en !== null,
      ...(e.eliminada_en === null ? await urlDeEvidencia(id, e.id) : { url: null, expiraEnSegundos: 0 }),
    });
  }
  return { ...base, fotos, eventos: await listarEventos({ entidad: "REPORTE", id }) };
}

async function bloquearReporte(tx: Tx, id: number) {
  const filas = await tx.$queryRaw<{ id: number }[]>`SELECT id FROM solicitud_reportes WHERE id = ${id} FOR UPDATE`;
  if (!filas.length) throw new AppError(404, "No existe ese reporte", "REPORTE_NO_ENCONTRADO");
  const r = await tx.solicitud_reportes.findUniqueOrThrow({ where: { id } });
  if (r.eliminado_en) throw new AppError(409, "El reporte ya fue eliminado", "REPORTE_ELIMINADO");
  return r;
}

/** Edita tipo y/o descripción del reporte. */
export async function editarReporte(adminId: number, id: number, cambios: { tipo?: solicitud_reportes_tipo; descripcion?: string | null }, motivo: string) {
  if (cambios.tipo === undefined && cambios.descripcion === undefined) throw new AppError(400, "Indica qué corregir", "SIN_CAMBIOS");
  return prisma.$transaction(async (tx) => {
    const permisoId = await exigirPermiso(tx, adminId, MODERAR_CONTENIDO, { bloquear: true });
    const actual = await bloquearReporte(tx, id);
    const tipo = cambios.tipo ?? actual.tipo;
    const descripcion = cambios.descripcion === undefined ? actual.descripcion : cambios.descripcion;
    if (tipo === actual.tipo && descripcion === actual.descripcion) throw new AppError(400, "No hay cambios que aplicar", "SIN_CAMBIOS");
    const ahora = relojDominio.ahora();
    await tx.solicitud_reportes.update({ where: { id }, data: { tipo, descripcion, editado_en: ahora } });
    await registrarEvento(tx, {
      actor: { adminId, permisoId },
      objetivo: { entidad: "REPORTE", reporteId: id },
      operacion: "EDITAR",
      antes: { tipo: actual.tipo, descripcion: actual.descripcion },
      despues: { tipo, descripcion },
      motivo,
    });
    return { id: String(id), tipo, descripcion };
  });
}

/** Seguimiento: ABIERTO ↔ EN_REVISION (la resolución va aparte). */
export async function cambiarEstadoReporte(adminId: number, id: number, estado: "ABIERTO" | "EN_REVISION", motivo: string) {
  return prisma.$transaction(async (tx) => {
    const permisoId = await exigirPermiso(tx, adminId, MODERAR_CONTENIDO, { bloquear: true });
    const actual = await bloquearReporte(tx, id);
    if (actual.estado === "RESUELTO") throw new AppError(409, "El reporte ya está resuelto", "REPORTE_RESUELTO");
    if (actual.estado === estado) throw new AppError(400, "El reporte ya está en ese estado", "SIN_CAMBIOS");
    await tx.solicitud_reportes.update({ where: { id }, data: { estado } });
    await registrarEvento(tx, {
      actor: { adminId, permisoId },
      objetivo: { entidad: "REPORTE", reporteId: id },
      operacion: "CAMBIAR_ESTADO",
      antes: { estado: actual.estado },
      despues: { estado },
      motivo,
    });
    return { id: String(id), estado };
  });
}

/** Nota de seguimiento (no cambia el reporte; queda en el historial con su texto como motivo). */
export async function notaDeSeguimiento(adminId: number, id: number, nota: string) {
  return prisma.$transaction(async (tx) => {
    const permisoId = await exigirPermiso(tx, adminId, MODERAR_CONTENIDO, { bloquear: true });
    const actual = await bloquearReporte(tx, id);
    const evento = await registrarEvento(tx, {
      actor: { adminId, permisoId },
      objetivo: { entidad: "REPORTE", reporteId: id },
      operacion: "NOTA",
      antes: { estado: actual.estado },
      despues: { nota },
      motivo: nota,
    });
    return { id: String(id), eventoId: evento };
  });
}

/**
 * Resolución de MODERACIÓN: el reporte pasa a RESUELTO (deja de bloquear la confirmación
 * automática, D57). No toca dinero: un PAGO_EN_DISPUTA lo resuelve el flujo financiero con
 * GESTIONAR_INCIDENCIAS_FINANZAS (D62, Fase 5).
 */
export async function resolverReporte(adminId: number, id: number, resolucion: string) {
  return prisma.$transaction(async (tx) => {
    const permisoId = await exigirPermiso(tx, adminId, MODERAR_CONTENIDO, { bloquear: true });
    const actual = await bloquearReporte(tx, id);
    if (actual.estado === "RESUELTO") throw new AppError(409, "El reporte ya está resuelto", "REPORTE_RESUELTO");
    if (actual.tipo === "PAGO_EN_DISPUTA") {
      throw new AppError(409, "Un pago en disputa se resuelve en el flujo financiero (D62)", "RESOLUCION_FINANCIERA");
    }
    // Decisión del 2026-11-25 (doc 25 v2 §4): el reporte de una solicitud SIN CERRAR solo se resuelve
    // con la resolución del servicio (permiso de incidencias). Si no, la confirmación automática la daría por realizada.
    const solicitud = await tx.solicitudes.findUniqueOrThrow({ where: { id: actual.solicitud_id }, select: { estado: true } });
    if (solicitud.estado === "PENDIENTE" || solicitud.estado === "CONFIRMADO" || solicitud.estado === "EN_PROCESO") {
      throw new AppError(409, "La solicitud de este reporte sigue abierta: se resuelve con la resolución del servicio (permiso de incidencias)", "RESOLUCION_DE_SERVICIO");
    }
    await tx.solicitud_reportes.update({ where: { id }, data: { estado: "RESUELTO" } });
    await registrarEvento(tx, {
      actor: { adminId, permisoId },
      objetivo: { entidad: "REPORTE", reporteId: id },
      operacion: "RESOLVER",
      antes: { estado: actual.estado },
      despues: { estado: "RESUELTO", resolucion },
      motivo: resolucion,
    });
    return { id: String(id), estado: "RESUELTO" as const };
  });
}

/** Borrado LÓGICO del reporte: deja de bloquear la confirmación automática (X5). */
export async function eliminarReporte(adminId: number, id: number, motivo: string) {
  return prisma.$transaction(async (tx) => {
    const permisoId = await exigirPermiso(tx, adminId, MODERAR_CONTENIDO, { bloquear: true });
    const actual = await bloquearReporte(tx, id);
    const ahora = relojDominio.ahora();
    await tx.solicitud_reportes.update({ where: { id }, data: { eliminado_en: ahora, eliminado_por: adminId } });
    await registrarEvento(tx, {
      actor: { adminId, permisoId },
      objetivo: { entidad: "REPORTE", reporteId: id },
      operacion: "ELIMINAR",
      antes: { tipo: actual.tipo, descripcion: actual.descripcion, estado: actual.estado, eliminado: false },
      despues: { eliminado: true, eliminado_en: ahora, eliminado_por: adminId },
      motivo,
    });
    return { id: String(id), eliminadoEn: ahora.toISOString() };
  });
}

/** Retira (borrado lógico) UNA foto del reporte; queda como edición del reporte. */
export async function eliminarFotoDeReporte(adminId: number, reporteId: number, evidenciaId: number, motivo: string) {
  return prisma.$transaction(async (tx) => {
    const permisoId = await exigirPermiso(tx, adminId, MODERAR_CONTENIDO, { bloquear: true });
    await bloquearReporte(tx, reporteId);
    const foto = await tx.evidencias_solicitud.findFirst({ where: { id: evidenciaId, reporte_id: reporteId } });
    if (!foto) throw new AppError(404, "No existe esa fotografía", "EVIDENCIA_NO_ENCONTRADA");
    if (foto.eliminada_en) throw new AppError(409, "La fotografía ya fue retirada", "EVIDENCIA_ELIMINADA");
    const ahora = relojDominio.ahora();
    await tx.evidencias_solicitud.update({ where: { id: evidenciaId }, data: { eliminada_en: ahora, eliminada_por: adminId } });
    await registrarEvento(tx, {
      actor: { adminId, permisoId },
      objetivo: { entidad: "REPORTE", reporteId },
      operacion: "EDITAR",
      antes: { foto: { id: evidenciaId, sha256: foto.sha256, tamano_bytes: foto.tamano_bytes, eliminada: false } },
      despues: { foto: { id: evidenciaId, eliminada: true, eliminada_en: ahora } },
      motivo,
    });
    return { id: String(evidenciaId), eliminadaEn: ahora.toISOString() };
  });
}

// ── Historial ────────────────────────────────────────────────────────────────
export async function listarEventos(f: { entidad?: "RESENA" | "REPORTE" | "PERMISO"; id?: number }) {
  const where: Prisma.moderacion_eventosWhereInput = {
    ...(f.entidad ? { entidad: f.entidad } : {}),
    ...(f.id && f.entidad === "RESENA" ? { resena_id: f.id } : {}),
    ...(f.id && f.entidad === "REPORTE" ? { reporte_id: f.id } : {}),
    ...(f.id && f.entidad === "PERMISO" ? { permiso_id: f.id } : {}),
  };
  const filas = await prisma.moderacion_eventos.findMany({ where, orderBy: { id: "asc" }, take: 1000, include: { usuarios: { select: { nombre_completo: true } } } });
  return filas.map((e) => ({
    id: String(e.id),
    entidad: e.entidad,
    objetivoId: String(e.resena_id ?? e.reporte_id ?? e.permiso_id),
    operacion: e.operacion,
    admin: e.admin_id === null ? null : { id: String(e.admin_id), nombre: e.usuarios?.nombre_completo ?? "" },
    datosAnteriores: e.datos_anteriores,
    datosNuevos: e.datos_nuevos,
    motivo: e.motivo,
    fecha: e.created_at.toISOString(),
  }));
}

