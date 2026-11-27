import type { Prisma, solicitudes_estado } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { AppError } from "../shared/errors/AppError";
import { fotosDeTerminado, urlDeFotoDeSolicitud, VENTANA_INICIO_MIN } from "./ciclo-solicitudes";
import { GESTIONAR_INCIDENCIAS_FINANZAS, permisoVigente } from "./permisos";
import { relojDominio } from "./reloj";

/**
 * SUPERVISIÓN de solicitudes en el panel (doc 25 v2 §5 y §7.2). Solo LECTURA: el admin no asigna,
 * reasigna, confirma, finaliza ni cancela solicitudes ordinarias (D24). La única intervención es la
 * resolución del servicio (dominio/resoluciones.ts).
 *  - Ver: SUPERVISAR_SOLICITUDES (o el propietario, implícito). Lo comprueba la ruta.
 *  - Contenido de los reportes (descripción y fotos): solo con GESTIONAR_INCIDENCIAS_FINANZAS (X6).
 *    Con solo supervisar se ve un resumen (tipo, estado, quién reportó, fecha).
 */

const MIN = 60_000;
const HORA = 60 * MIN;
const ABIERTOS: solicitudes_estado[] = ["PENDIENTE", "CONFIRMADO", "EN_PROCESO"];
const ESTADOS: solicitudes_estado[] = ["PENDIENTE", "CONFIRMADO", "EN_PROCESO", "REALIZADO", "CANCELADO", "RECHAZADO"];
export const HORAS_AVISO_VENCIMIENTO = 2;

export type Alerta = "REPORTE_ACTIVO" | "SIN_INICIAR" | "ESPERANDO_CONFIRMACION" | "POR_VENCER";

type Base = {
  estado: solicitudes_estado;
  fecha_hora_programada: Date;
  fecha_hora_fin_estimada: Date | null;
  trabajador_marco_realizado_en: Date | null;
};

/** Alertas de «requieren atención» de una solicitud (las mismas que filtra atencion=1). */
export function alertasDe(s: Base, reportesActivos: number, ahora: Date): Alerta[] {
  const a: Alerta[] = [];
  if (reportesActivos > 0 && ABIERTOS.includes(s.estado)) a.push("REPORTE_ACTIVO");
  if (s.estado === "CONFIRMADO" && ahora.getTime() > s.fecha_hora_programada.getTime() + VENTANA_INICIO_MIN * MIN) a.push("SIN_INICIAR");
  if (s.estado === "EN_PROCESO" && (s.trabajador_marco_realizado_en !== null || (s.fecha_hora_fin_estimada !== null && ahora.getTime() >= s.fecha_hora_fin_estimada.getTime()))) {
    a.push("ESPERANDO_CONFIRMACION");
  }
  if (s.estado === "PENDIENTE" && s.fecha_hora_programada.getTime() - ahora.getTime() < HORAS_AVISO_VENCIMIENTO * HORA) a.push("POR_VENCER");
  return a;
}

const REPORTE_ACTIVO = { estado: { not: "RESUELTO" as const }, eliminado_en: null };

/** El mismo criterio que alertasDe, como filtro de la BD. */
function filtroAtencion(ahora: Date): Prisma.solicitudesWhereInput {
  return {
    OR: [
      { estado: { in: ABIERTOS }, solicitud_reportes: { some: REPORTE_ACTIVO } },
      { estado: "CONFIRMADO", fecha_hora_programada: { lt: new Date(ahora.getTime() - VENTANA_INICIO_MIN * MIN) } },
      { estado: "EN_PROCESO", OR: [{ trabajador_marco_realizado_en: { not: null } }, { fecha_hora_fin_estimada: { lte: ahora } }] },
      { estado: "PENDIENTE", fecha_hora_programada: { lt: new Date(ahora.getTime() + HORAS_AVISO_VENCIMIENTO * HORA) } },
    ],
  };
}

export type FiltrosSupervision = {
  estado?: solicitudes_estado;
  modo?: "INVITACION" | "BOLSA";
  desde?: Date;
  hasta?: Date;
  busqueda?: string;
  atencion?: boolean;
  pagina: number;
  tamano: number;
};

export function leerFiltros(q: Record<string, unknown>): FiltrosSupervision {
  const texto = (k: string) => (typeof q[k] === "string" && (q[k] as string).trim() !== "" ? (q[k] as string).trim() : undefined);
  const estado = texto("estado");
  if (estado !== undefined && !ESTADOS.includes(estado as solicitudes_estado)) throw new AppError(400, "El filtro estado no es válido", "FILTRO_INVALIDO");
  const modo = texto("modo");
  if (modo !== undefined && modo !== "INVITACION" && modo !== "BOLSA") throw new AppError(400, "El filtro modo no es válido", "FILTRO_INVALIDO");
  const fecha = (k: string) => {
    const v = texto(k);
    if (v === undefined) return undefined;
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) throw new AppError(400, `El filtro ${k} no es una fecha válida`, "FILTRO_INVALIDO");
    return d;
  };
  const entero = (k: string, def: number, max: number) => {
    const v = texto(k);
    if (v === undefined) return def;
    const n = Number(v);
    if (!Number.isInteger(n) || n < 1 || n > max) throw new AppError(400, `El filtro ${k} no es válido`, "FILTRO_INVALIDO");
    return n;
  };
  const busqueda = texto("q");
  if (busqueda && busqueda.length > 100) throw new AppError(400, "La búsqueda admite como máximo 100 caracteres", "FILTRO_INVALIDO");
  return {
    estado: estado as solicitudes_estado | undefined,
    modo: modo as "INVITACION" | "BOLSA" | undefined,
    desde: fecha("desde"),
    hasta: fecha("hasta"),
    busqueda,
    atencion: texto("atencion") === "1",
    pagina: entero("pagina", 1, 10_000),
    tamano: entero("tamano", 50, 100),
  };
}

/** GET /api/admin/solicitudes */
export async function listarParaSupervision(f: FiltrosSupervision) {
  const ahora = relojDominio.ahora();
  const condiciones: Prisma.solicitudesWhereInput[] = [];
  if (f.estado) condiciones.push({ estado: f.estado });
  if (f.modo) condiciones.push({ modo_eleccion: f.modo === "INVITACION" ? "MANUAL" : "AUTOMATICA" });
  if (f.desde) condiciones.push({ fecha_hora_programada: { gte: f.desde } });
  if (f.hasta) condiciones.push({ fecha_hora_programada: { lte: f.hasta } });
  if (f.atencion) condiciones.push(filtroAtencion(ahora));
  if (f.busqueda) {
    const q = f.busqueda;
    const id = /^\d+$/.test(q) ? Number(q) : null;
    condiciones.push({
      OR: [
        ...(id !== null ? [{ id }] : []),
        { servicio_nombre_aplicado: { contains: q } },
        { direccion_servicio: { contains: q } },
        { usuarios: { nombre_completo: { contains: q } } },
        { usuarios: { correo: { contains: q } } },
        { trabajadores: { nombre_completo: { contains: q } } },
      ],
    });
  }
  const where: Prisma.solicitudesWhereInput = condiciones.length ? { AND: condiciones } : {};
  const [total, filas] = await Promise.all([
    prisma.solicitudes.count({ where }),
    prisma.solicitudes.findMany({
      where,
      orderBy: [{ fecha_hora_programada: "desc" }, { id: "desc" }],
      skip: (f.pagina - 1) * f.tamano,
      take: f.tamano,
      include: {
        usuarios: { select: { id: true, nombre_completo: true, correo: true, telefono: true } },
        trabajadores: { select: { id: true, nombre_completo: true, estado: true } },
        solicitud_trabajadores: { select: { estado: true, origen: true } },
        _count: { select: { solicitud_reportes: { where: REPORTE_ACTIVO } } },
      },
    }),
  ]);
  return {
    total,
    pagina: f.pagina,
    tamano: f.tamano,
    actualizadoEn: ahora.toISOString(),
    solicitudes: filas.map((s) => ({
      id: s.id,
      estado: s.estado,
      modo: s.modo_eleccion === "MANUAL" ? ("INVITACION" as const) : ("BOLSA" as const),
      servicio: s.servicio_nombre_aplicado ?? "",
      direccion: s.direccion_servicio,
      fechaProgramada: s.fecha_hora_programada.toISOString(),
      finEstimado: s.fecha_hora_fin_estimada?.toISOString() ?? null,
      creadaEn: s.created_at.toISOString(),
      precio: Number(s.precio_estimado),
      cliente: { id: s.usuarios.id, nombre: s.usuarios.nombre_completo, correo: s.usuarios.correo, telefono: s.usuarios.telefono },
      trabajador: s.trabajadores ? { id: s.trabajadores.id, nombre: s.trabajadores.nombre_completo, estado: s.trabajadores.estado } : null,
      invitaciones: {
        pendientes: s.solicitud_trabajadores.filter((t) => t.estado === "PENDIENTE").length,
        rechazadas: s.solicitud_trabajadores.filter((t) => t.estado === "RECHAZADA").length,
      },
      reportesActivos: s._count.solicitud_reportes,
      alertas: alertasDe(s, s._count.solicitud_reportes, ahora),
    })),
  };
}

/** GET /api/admin/solicitudes/:id — detalle completo para supervisar (y resolver, con el permiso). */
export async function detalleParaSupervision(adminId: number, id: number) {
  const s = await prisma.solicitudes.findUnique({
    where: { id },
    include: {
      usuarios: { select: { id: true, nombre_completo: true, correo: true, telefono: true, estado_verificacion: true } },
      trabajadores: { select: { id: true, nombre_completo: true, estado: true, telefono: true } },
      solicitud_areas: true,
      solicitud_extras: true,
      solicitud_especialidades: true,
      solicitud_trabajadores: { include: { trabajadores: { select: { id: true, nombre_completo: true } } }, orderBy: { id: "asc" } },
      solicitud_historial: { orderBy: [{ created_at: "asc" }, { id: "asc" }] },
      evidencias_solicitud: { select: { id: true, tipo_mime: true, tamano_bytes: true, created_at: true, reporte_id: true, aportada_por: true, eliminada_en: true } },
      solicitud_reportes: { orderBy: { id: "asc" } },
      solicitud_resoluciones: { where: { resultado_servicio: { not: null } }, include: { usuarios: { select: { nombre_completo: true } } } },
    },
  });
  if (!s) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  const ahora = relojDominio.ahora();
  const verContenido = (await permisoVigente(prisma, adminId, GESTIONAR_INCIDENCIAS_FINANZAS)) !== null;
  const activos = s.solicitud_reportes.filter((r) => r.estado !== "RESUELTO" && r.eliminado_en === null);
  const resolucion = s.solicitud_resoluciones[0] ?? null;

  // Nombres de quien hizo cada cambio del historial.
  const idsPorActor = (actor: string) => [...new Set(s.solicitud_historial.filter((h) => h.actor === actor && h.actor_id !== null).map((h) => h.actor_id as number))];
  const [usuariosHist, trabajadoresHist] = await Promise.all([
    prisma.usuarios.findMany({ where: { id: { in: [...idsPorActor("CLIENTE"), ...idsPorActor("ADMIN")] } }, select: { id: true, nombre_completo: true } }),
    prisma.trabajadores.findMany({ where: { id: { in: idsPorActor("TRABAJADOR") } }, select: { id: true, nombre_completo: true } }),
  ]);
  const nombreActor = (actor: string, actorId: number | null) => {
    if (actor === "SISTEMA" || actorId === null) return "Sistema";
    const lista = actor === "TRABAJADOR" ? trabajadoresHist : usuariosHist;
    return lista.find((x) => x.id === actorId)?.nombre_completo ?? `#${actorId}`;
  };

  return {
    id: s.id,
    estado: s.estado,
    modo: s.modo_eleccion === "MANUAL" ? ("INVITACION" as const) : ("BOLSA" as const),
    servicio: s.servicio_nombre_aplicado ?? "",
    fechaProgramada: s.fecha_hora_programada.toISOString(),
    finEstimado: s.fecha_hora_fin_estimada?.toISOString() ?? null,
    duracionMin: s.duracion_estimada_min,
    creadaEn: s.created_at.toISOString(),
    actualizadoEn: ahora.toISOString(),
    direccion: s.direccion_servicio,
    inmueble: {
      nombre: s.inmueble_alias_aplicado,
      tipo: s.inmueble_tipo_aplicado,
      habitaciones: s.habitaciones_aplicado,
      banos: s.banos_aplicado,
      mediosBanos: s.medios_banos_aplicado,
      pisos: s.pisos_aplicado,
      guardado: s.inmueble_id !== null,
    },
    notas: s.notas,
    areas: s.solicitud_areas.map((a) => a.nombre_aplicado),
    extras: s.solicitud_extras.map((e) => ({ nombre: e.nombre_aplicado, precio: Number(e.precio_aplicado), duracionMin: e.duracion_aplicada_min })),
    especialidades: s.solicitud_especialidades.map((e) => e.nombre_aplicado),
    // Informativo: en esta fase no hay pagos ni movimientos (estado_pago siempre PENDIENTE).
    precio: { total: Number(s.precio_estimado), base: Number(s.precio_base_aplicado ?? 0), extras: Number(s.precio_extras_aplicado ?? 0), metodoPago: s.metodo_pago, estadoPago: s.estado_pago },
    cliente: { id: s.usuarios.id, nombre: s.usuarios.nombre_completo, correo: s.usuarios.correo, telefono: s.usuarios.telefono, verificacion: s.usuarios.estado_verificacion },
    trabajador: s.trabajadores ? { id: s.trabajadores.id, nombre: s.trabajadores.nombre_completo, estado: s.trabajadores.estado, telefono: s.trabajadores.telefono } : null,
    trabajadores: s.solicitud_trabajadores.map((t) => ({
      trabajador: { id: t.trabajador_id, nombre: t.trabajadores.nombre_completo },
      origen: t.origen,
      estado: t.estado,
      motivoCierre: t.motivo_cierre,
      creadaEn: t.created_at.toISOString(),
      respondidaEn: t.respondida_en?.toISOString() ?? null,
    })),
    historial: s.solicitud_historial.map((h) => ({
      fecha: h.created_at.toISOString(),
      estadoAnterior: h.estado_anterior,
      estadoNuevo: h.estado_nuevo,
      actor: h.actor,
      actorNombre: nombreActor(h.actor, h.actor_id),
      motivo: h.motivo,
    })),
    marcas: {
      trabajadorTerminoEn: s.trabajador_marco_realizado_en?.toISOString() ?? null,
      clienteConfirmoEn: s.cliente_marco_realizado_en?.toISOString() ?? null,
      confirmacionSolicitadaEn: s.confirmacion_solicitada_en?.toISOString() ?? null,
      avisoEvidenciaEn: s.aviso_evidencia_en?.toISOString() ?? null,
      realizadoEn: s.realizado_en?.toISOString() ?? null,
      realizadoVia: s.realizado_via,
    },
    fotosTerminado: fotosDeTerminado(s),
    verContenidoDeReportes: verContenido,
    reportes: s.solicitud_reportes.map((r) => ({
      id: r.id,
      reportadoPor: r.reportado_por,
      tipo: r.tipo,
      estado: r.estado,
      fecha: r.created_at.toISOString(),
      eliminado: r.eliminado_en !== null,
      activo: r.estado !== "RESUELTO" && r.eliminado_en === null,
      // X6: el contenido solo con el permiso de incidencias (o en Reportes, con moderación).
      ...(verContenido
        ? {
            descripcion: r.descripcion,
            fotos: s.evidencias_solicitud.filter((e) => e.reporte_id === r.id && e.eliminada_en === null).map((e) => ({ id: e.id, tipoMime: e.tipo_mime, tamanoBytes: e.tamano_bytes })),
          }
        : {}),
    })),
    resolucion: resolucion
      ? { id: resolucion.id, resultadoServicio: resolucion.resultado_servicio, motivo: resolucion.motivo, admin: resolucion.usuarios.nombre_completo, fecha: resolucion.created_at.toISOString() }
      : null,
    alertas: alertasDe(s, activos.length, ahora),
    puedeResolver: verContenido && resolucion === null && (s.estado === "CONFIRMADO" || s.estado === "EN_PROCESO") && activos.length > 0,
  };
}

/** URL temporal de una foto de la solicitud. Las de un REPORTE exigen el permiso de incidencias (X6). */
export async function urlFotoParaSupervision(adminId: number, solicitudId: number, evidenciaId: number) {
  const e = await prisma.evidencias_solicitud.findFirst({ where: { id: evidenciaId, solicitud_id: solicitudId, eliminada_en: null }, select: { reporte_id: true } });
  if (!e) throw new AppError(404, "No existe esa fotografía", "EVIDENCIA_NO_ENCONTRADA");
  if (e.reporte_id !== null && (await permisoVigente(prisma, adminId, GESTIONAR_INCIDENCIAS_FINANZAS)) === null) {
    throw new AppError(403, "Las fotos de un reporte requieren el permiso de incidencias", "PERMISO_REQUERIDO");
  }
  return urlDeFotoDeSolicitud(solicitudId, evidenciaId, { soloTerminado: false });
}
