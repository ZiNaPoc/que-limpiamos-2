import { prisma } from "../config/prisma";
import { AppError } from "../shared/errors/AppError";
import { cicloParaCliente, cicloParaTrabajador, filtrarElegibles } from "./ciclo-solicitudes";
import { relojDominio } from "./reloj";
import { PLAZO_HORAS, reputacionesDeTrabajadores } from "./resenas";

/**
 * Consultas de SOLO LECTURA para las apps (Fase 3b, doc 23 §2, autorizadas el 2026-11-25).
 * Dan a las apps el id REAL de cada solicitud para calificar y reportar desde el servicio.
 * La identidad sale del token; un usuario solo ve SUS solicitudes. No se expone el correo ni
 * el teléfono de la otra parte, ni las reseñas que el usuario RECIBIÓ (V5/V6).
 *
 * Doc 25 v2 (ciclo sin dinero): cada elemento AÑADE los datos del ciclo (modo, snapshot del inmueble,
 * invitaciones, marcas de D54, fotos de «terminado» y las acciones permitidas). Los campos de la
 * Fase 3b se conservan con el mismo nombre y significado.
 */

const PLAZO_MS = PLAZO_HORAS * 3600_000;
const ESTADOS_INVITACION_VIGENTE = ["PENDIENTE", "ACEPTADA"] as const;

type Base = {
  id: number;
  estado: string;
  fecha_hora_programada: Date;
  realizado_en: Date | null;
  servicio_nombre_aplicado: string | null;
  direccion_servicio: string;
  trabajador_id: number | null;
  servicios: { nombre: string };
};

function plazoDeCalificacion(s: Base): Date | null {
  return s.estado === "REALIZADO" && s.realizado_en ? new Date(s.realizado_en.getTime() + PLAZO_MS) : null;
}

function resenaPropia(r: { puntuacion: number; comentario: string | null; created_at: Date; eliminada_en: Date | null } | undefined) {
  return r ? { puntuacion: r.puntuacion, comentario: r.comentario, fecha: r.created_at.toISOString(), eliminadaPorModeracion: r.eliminada_en !== null } : null;
}

const CAMPOS = {
  id: true,
  estado: true,
  fecha_hora_programada: true,
  realizado_en: true,
  servicio_nombre_aplicado: true,
  direccion_servicio: true,
  trabajador_id: true,
  cliente_id: true,
  servicios: { select: { nombre: true } },
} as const;

/** GET /api/cliente/solicitudes — las solicitudes del cliente, de la más reciente a la más antigua. */
export async function solicitudesDelCliente(clienteId: number) {
  const filas = await prisma.solicitudes.findMany({ where: { cliente_id: clienteId }, select: CAMPOS, orderBy: { fecha_hora_programada: "desc" }, take: 200 });
  const ids = filas.map((s) => s.id);
  const [resenas, trabajadores] = await Promise.all([
    prisma.resenas.findMany({ where: { solicitud_id: { in: ids }, autor_rol: "CLIENTE" }, select: { solicitud_id: true, puntuacion: true, comentario: true, created_at: true, eliminada_en: true } }),
    prisma.trabajadores.findMany({ where: { id: { in: filas.map((s) => s.trabajador_id).filter((x): x is number => x !== null) } }, select: { id: true, nombre_completo: true } }),
  ]);
  const ahora = relojDominio.ahora().getTime();
  const nombre = new Map(trabajadores.map((t) => [t.id, t.nombre_completo]));
  const ciclo = await cicloParaCliente(clienteId, ids);
  return filas.map((s) => {
    const miResena = resenaPropia(resenas.find((r) => r.solicitud_id === s.id));
    const hasta = plazoDeCalificacion(s);
    return {
      ...ciclo.get(s.id),
      id: s.id,
      estado: s.estado,
      fechaProgramada: s.fecha_hora_programada.toISOString(),
      realizadoEn: s.realizado_en?.toISOString() ?? null,
      servicio: s.servicio_nombre_aplicado ?? s.servicios.nombre,
      direccion: s.direccion_servicio,
      trabajador: s.trabajador_id === null ? null : { id: s.trabajador_id, nombre: nombre.get(s.trabajador_id) ?? "" },
      miResena,
      calificarHasta: hasta?.toISOString() ?? null,
      // Indicaciones para la interfaz; el servidor vuelve a validar todo al calificar o reportar.
      puedeCalificar: s.trabajador_id !== null && hasta !== null && ahora <= hasta.getTime() && miResena === null,
      puedeReportar: s.trabajador_id !== null && ahora >= s.fecha_hora_programada.getTime(),
    };
  });
}

/**
 * GET /api/trabajador/solicitudes — las solicitudes ASIGNADAS al trabajador y aquellas a las que
 * está INVITADO con invitación vigente (PENDIENTE o ACEPTADA).
 */
export async function solicitudesDelTrabajador(trabajadorId: number) {
  const invitaciones = await prisma.solicitud_trabajadores.findMany({
    where: { trabajador_id: trabajadorId, estado: { in: [...ESTADOS_INVITACION_VIGENTE] } },
    select: { solicitud_id: true, estado: true },
  });
  const filas = await prisma.solicitudes.findMany({
    where: { OR: [{ trabajador_id: trabajadorId }, { id: { in: invitaciones.map((i) => i.solicitud_id) } }] },
    select: CAMPOS,
    orderBy: { fecha_hora_programada: "desc" },
    take: 200,
  });
  const [resenas, clientes] = await Promise.all([
    prisma.resenas.findMany({ where: { solicitud_id: { in: filas.map((s) => s.id) }, autor_rol: "TRABAJADOR", trabajador_id: trabajadorId }, select: { solicitud_id: true, puntuacion: true, comentario: true, created_at: true, eliminada_en: true } }),
    prisma.usuarios.findMany({ where: { id: { in: filas.map((s) => s.cliente_id) } }, select: { id: true, nombre_completo: true } }),
  ]);
  const ahora = relojDominio.ahora().getTime();
  const nombre = new Map(clientes.map((c) => [c.id, c.nombre_completo]));
  const ciclo = await cicloParaTrabajador(trabajadorId, filas.map((s) => s.id));
  return filas.map((s) => {
    const asignado = s.trabajador_id === trabajadorId;
    const invitacion = invitaciones.find((i) => i.solicitud_id === s.id)?.estado ?? null;
    const miResena = asignado ? resenaPropia(resenas.find((r) => r.solicitud_id === s.id)) : null;
    const hasta = asignado ? plazoDeCalificacion(s) : null;
    return {
      ...ciclo.get(s.id),
      id: s.id,
      estado: s.estado,
      relacion: asignado ? ("ASIGNADO" as const) : ("INVITADO" as const),
      invitacion,
      fechaProgramada: s.fecha_hora_programada.toISOString(),
      realizadoEn: s.realizado_en?.toISOString() ?? null,
      servicio: s.servicio_nombre_aplicado ?? s.servicios.nombre,
      cliente: { nombre: nombre.get(s.cliente_id) ?? "" },
      miResena,
      calificarHasta: hasta?.toISOString() ?? null,
      puedeCalificar: asignado && hasta !== null && ahora <= hasta.getTime() && miResena === null,
      puedeReportar: asignado && ahora >= s.fecha_hora_programada.getTime(),
      // V5: asignado o invitado vigente.
      puedeVerReputacionCliente: true,
    };
  });
}

/**
 * GET /api/cliente/trabajadores — selección manual (decisión del 2026-11-25): solo trabajadores
 * ACTIVOS y VERIFICADOS. Con `servicioId`, solo los que tienen TODAS las especialidades que exige
 * ese servicio (servicio_especialidades). Con la fecha, además sin traslapes (doc 25); al crear la
 * solicitud se vuelve a validar todo.
 */
export async function trabajadoresParaSeleccion(servicioId?: number, fecha?: Date) {
  let exigidas: number[] = [];
  let duracionMin = 0;
  if (servicioId !== undefined) {
    const servicio = await prisma.servicios.findUnique({ where: { id: servicioId }, select: { id: true, duracion_estimada_min: true } });
    if (!servicio) throw new AppError(404, "No existe ese servicio", "SERVICIO_NO_ENCONTRADO");
    duracionMin = servicio.duracion_estimada_min;
    exigidas = (await prisma.servicio_especialidades.findMany({ where: { servicio_id: servicioId }, select: { especialidad_id: true } })).map((e) => e.especialidad_id);
  }
  const trabajadores = await prisma.trabajadores.findMany({
    where: { estado: "ACTIVO", estado_verificacion: "VERIFICADO" },
    select: { id: true, nombre_completo: true },
    orderBy: { nombre_completo: "asc" },
  });
  const ids = trabajadores.map((t) => t.id);
  const relaciones = await prisma.trabajador_especialidades.findMany({ where: { trabajador_id: { in: ids } }, select: { trabajador_id: true, especialidad_id: true } });
  const nombresEsp = new Map(
    (await prisma.especialidades.findMany({ where: { id: { in: [...new Set(relaciones.map((r) => r.especialidad_id))] } }, select: { id: true, nombre: true } })).map((e) => [e.id, e.nombre]),
  );
  const elegibles = trabajadores.filter((t) => {
    const propias = new Set(relaciones.filter((r) => r.trabajador_id === t.id).map((r) => r.especialidad_id));
    return exigidas.every((e) => propias.has(e));
  });
  // Doc 25: con fecha (y servicio), fuera los que tienen un servicio que se cruza (60 min de traslado).
  if (fecha && servicioId !== undefined) {
    const libres = await filtrarElegibles(elegibles.map((t) => t.id), exigidas, { inicio: fecha, fin: new Date(fecha.getTime() + duracionMin * 60_000) });
    elegibles.splice(0, elegibles.length, ...elegibles.filter((t) => libres.has(t.id)));
  }
  const reputaciones = await reputacionesDeTrabajadores(elegibles.map((t) => t.id));
  return elegibles.map((t) => ({
    id: t.id,
    nombre: t.nombre_completo,
    especialidades: relaciones.filter((r) => r.trabajador_id === t.id).map((r) => nombresEsp.get(r.especialidad_id) ?? "").filter(Boolean).sort(),
    reputacion: reputaciones[t.id] ?? { promedio: null, cantidad: 0 },
  }));
}
