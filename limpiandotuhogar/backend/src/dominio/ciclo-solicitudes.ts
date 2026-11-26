import { Prisma, type solicitudes, type solicitudes_estado } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { almacenamiento, type ObjetoGuardado, segundosUrlTemporal } from "../shared/almacenamiento";
import { AppError } from "../shared/errors/AppError";
import type { Cuerpo } from "../shared/validation/campos";
import type { Tx } from "./auditoria";
import { crearInmueble, type DatosInmueble, inmueblePropio, leerDatosInmueble, leerNombreInmueble } from "./inmuebles";
import { avisarCliente, avisarTrabajador } from "./notificaciones";
import { relojDominio } from "./reloj";
import { type ArchivoRecibido, LIMITES_FOTOS, validarFotos } from "./reportes";

/**
 * CICLO DE LAS SOLICITUDES SIN DINERO (doc 25 v2, autorizado el 2026-11-25).
 *
 * Reglas (doc 25 §2):
 *  - Precio = precio base del servicio + extras (D4; incrementos por tamaño y tipo en 0). La
 *    duración = la del servicio + los minutos de los extras. Todo lo calcula el SERVIDOR.
 *  - Crear exige la INE VERIFICADA (D65 → 403 IDENTIDAD_NO_VERIFICADA). Cotizar, no.
 *  - Un colaborador elegido → una invitación (MANUAL). Sin colaborador → bolsa (AUTOMATICA).
 *  - Elegible = ACTIVO + VERIFICADO + todas las especialidades exigidas + sin traslape con sus
 *    servicios CONFIRMADO/EN_PROCESO contando el traslado (MARGEN_TRASLADO_MIN, 60). Sin horario (D17).
 *  - Cancelar solo sin cargo: PENDIENTE, o CONFIRMADO con 24 h o más. Con menos → 409.
 *  - Iniciar: de 30 min antes a 30 min después de la hora programada.
 *  - Terminar: 1 a 5 fotos (las mismas reglas que los reportes).
 *  - NO se escribe nada de dinero: estado_pago queda PENDIENTE; los importes son una copia informativa.
 * Cada cambio de estado es un UPDATE condicional en una transacción, con su historial y sus avisos.
 */

const MIN = 60_000;
const HORA = 60 * MIN;
export const VENTANA_INICIO_MIN = 30;
export const HORAS_CANCELACION_SIN_CARGO = 24;
export const DIAS_MAXIMOS_DE_ANTICIPACION = 365;
const MAX_NOTAS = 500;
const MAX_AREAS = 20;
const MAX_EXTRAS = 10;
/** Valores decididos (`11` §1). Si la fila de parametros_negocio existe, manda la fila. */
const PARAMETROS_POR_DEFECTO = { PORCENTAJE_TRABAJADOR: 85, MARGEN_TRASLADO_MIN: 60, MAX_INVITACIONES_PENDIENTES: 5 } as const;
type Parametro = keyof typeof PARAMETROS_POR_DEFECTO;

const ESTADOS_ABIERTOS: solicitudes_estado[] = ["PENDIENTE", "CONFIRMADO", "EN_PROCESO"];

export async function parametro(clave: Parametro, tx: Tx = prisma): Promise<number> {
  const fila = await tx.parametros_negocio.findUnique({ where: { clave } });
  return fila ? Number(fila.valor) : PARAMETROS_POR_DEFECTO[clave];
}

const dinero = (n: number) => new Prisma.Decimal(n.toFixed(2));
const aSegundo = (d: Date) => new Date(Math.floor(d.getTime() / 1000) * 1000);
const fechaIso = (d: Date | null | undefined) => (d ? d.toISOString() : null);

function conflicto(mensaje: string, codigo: string): AppError {
  return new AppError(409, mensaje, codigo);
}
function invalido(mensaje: string, codigo = "DATOS_INVALIDOS"): AppError {
  return new AppError(400, mensaje, codigo);
}

/** Bloquea la fila de la solicitud (FOR UPDATE) y la devuelve, o 404. */
export async function bloquearSolicitud(tx: Tx, id: number): Promise<solicitudes> {
  const filas = await tx.$queryRaw<{ id: number }[]>`SELECT id FROM solicitudes WHERE id = ${id} FOR UPDATE`;
  if (!filas.length) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  return tx.solicitudes.findUniqueOrThrow({ where: { id } });
}

async function bloquearTrabajador(tx: Tx, id: number) {
  await tx.$queryRaw`SELECT id FROM trabajadores WHERE id = ${id} FOR UPDATE`;
}

/** ¿Hay reportes ACTIVOS (no resueltos ni eliminados)? Bloquean la confirmación (D57, X5). */
export async function tieneReportesActivos(tx: Tx, solicitudId: number): Promise<boolean> {
  return (await tx.solicitud_reportes.count({ where: { solicitud_id: solicitudId, estado: { not: "RESUELTO" }, eliminado_en: null } })) > 0;
}

async function historial(
  tx: Tx,
  solicitudId: number,
  d: { anterior: solicitudes_estado | null; nuevo: solicitudes_estado; actor: "CLIENTE" | "TRABAJADOR" | "ADMIN" | "SISTEMA"; actorId: number | null; motivo: string },
) {
  await tx.solicitud_historial.create({
    data: { solicitud_id: solicitudId, estado_anterior: d.anterior, estado_nuevo: d.nuevo, actor: d.actor, actor_id: d.actorId, motivo: d.motivo.slice(0, 255), created_at: relojDominio.ahora() },
  });
}

/** UPDATE condicional: solo cambia si la fila sigue en el estado esperado. Si no, 409. */
async function cambiarEstado(tx: Tx, id: number, desde: solicitudes_estado, datos: Prisma.solicitudesUncheckedUpdateManyInput, mensaje: string, codigo: string) {
  const r = await tx.solicitudes.updateMany({ where: { id, estado: desde }, data: { ...datos, updated_at: relojDominio.ahora() } });
  if (r.count !== 1) throw conflicto(mensaje, codigo);
}

const nombreServicio = (s: { servicio_nombre_aplicado: string | null }) => s.servicio_nombre_aplicado ?? "tu servicio";
const enLocal = (d: Date) =>
  d.toLocaleString("es-MX", { timeZone: "America/Cancun", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

// ════════════════════════════════════════════════════════════════════
// Catálogo y cotización
// ════════════════════════════════════════════════════════════════════

/** GET /api/cliente/catalogo — servicios, áreas y extras ACTIVOS, con sus ids. */
export async function catalogo() {
  const [servicios, areas, extras] = await Promise.all([
    prisma.servicios.findMany({
      where: { estado: "ACTIVO" },
      orderBy: { precio_base: "asc" },
      include: { servicio_especialidades: { include: { especialidades: { select: { nombre: true } } } } },
    }),
    prisma.areas_limpieza.findMany({ where: { estado: "ACTIVO" }, orderBy: [{ orden: "asc" }, { nombre: "asc" }] }),
    prisma.servicios_extra.findMany({ where: { estado: "ACTIVO" }, orderBy: { nombre: "asc" } }),
  ]);
  return {
    servicios: servicios.map((s) => ({
      id: s.id,
      nombre: s.nombre,
      descripcion: s.descripcion,
      precioBase: Number(s.precio_base),
      duracionMin: s.duracion_estimada_min,
      especialidades: s.servicio_especialidades.map((e) => e.especialidades.nombre).sort(),
    })),
    areas: areas.map((a) => ({ id: a.id, nombre: a.nombre })),
    extras: extras.map((e) => ({ id: e.id, nombre: e.nombre, descripcion: e.descripcion, precio: Number(e.precio), duracionMin: e.duracion_estimada_min })),
  };
}

export type Pedido = {
  servicioId: number;
  programada: Date;
  areaIds: number[];
  extraIds: number[];
  notas: string | null;
  inmueble: { inmuebleId: number } | { datos: DatosInmueble; guardarComo: string | null };
  trabajadorId: number | null;
};

function idsDe(valor: unknown, etiqueta: string, max: number): number[] {
  if (valor === undefined || valor === null) return [];
  if (!Array.isArray(valor)) throw invalido(`${etiqueta} debe ser una lista de ids`);
  const ids = valor.map((v) => (typeof v === "string" && /^\d+$/.test(v) ? Number(v) : v));
  if (!ids.every((v) => typeof v === "number" && Number.isSafeInteger(v) && v > 0)) throw invalido(`${etiqueta} debe ser una lista de ids`);
  const unicos = [...new Set(ids as number[])];
  if (unicos.length > max) throw invalido(`${etiqueta}: máximo ${max}`);
  return unicos;
}

function idPositivo(valor: unknown, etiqueta: string): number {
  const n = typeof valor === "string" && /^\d+$/.test(valor) ? Number(valor) : valor;
  if (typeof n !== "number" || !Number.isSafeInteger(n) || n <= 0) throw invalido(`Indica ${etiqueta}`);
  return n;
}

/** Lee y valida el cuerpo de una cotización o solicitud (sin consultar la BD). */
export function leerPedido(cuerpo: Cuerpo, opciones: { conTrabajador: boolean }): Pedido {
  const servicioId = idPositivo(cuerpo.servicioId, "el servicio (servicioId)");
  if (typeof cuerpo.fechaProgramada !== "string") throw invalido("Indica la fecha y hora del servicio (fechaProgramada, ISO 8601)");
  const programada = new Date(cuerpo.fechaProgramada);
  if (Number.isNaN(programada.getTime())) throw invalido("La fecha del servicio no es válida");
  let notas: string | null = null;
  if (cuerpo.notas !== undefined && cuerpo.notas !== null) {
    if (typeof cuerpo.notas !== "string") throw invalido("Las notas deben ser texto");
    notas = cuerpo.notas.trim() || null;
    if (notas && [...notas].length > MAX_NOTAS) throw invalido(`Las notas admiten como máximo ${MAX_NOTAS} caracteres`);
  }
  let inmueble: Pedido["inmueble"];
  if (cuerpo.inmuebleId !== undefined && cuerpo.inmuebleId !== null) {
    if (cuerpo.inmueble !== undefined && cuerpo.inmueble !== null) throw invalido("Indica un inmueble guardado (inmuebleId) o uno nuevo (inmueble), no los dos");
    inmueble = { inmuebleId: idPositivo(cuerpo.inmuebleId, "el inmueble") };
  } else {
    const datos = cuerpo.inmueble;
    if (typeof datos !== "object" || datos === null || Array.isArray(datos)) throw invalido("Indica el inmueble: uno guardado (inmuebleId) o sus datos (inmueble)");
    const d = datos as Cuerpo;
    inmueble = { datos: leerDatosInmueble(d), guardarComo: d.guardarComo === undefined || d.guardarComo === null || d.guardarComo === "" ? null : leerNombreInmueble(d.guardarComo) };
  }
  let trabajadorId: number | null = null;
  if (opciones.conTrabajador && cuerpo.trabajadorId !== undefined && cuerpo.trabajadorId !== null) trabajadorId = idPositivo(cuerpo.trabajadorId, "el colaborador");
  return {
    servicioId,
    programada: aSegundo(programada),
    areaIds: idsDe(cuerpo.areaIds, "Las áreas", MAX_AREAS),
    extraIds: idsDe(cuerpo.extraIds, "Los extras", MAX_EXTRAS),
    notas,
    inmueble,
    trabajadorId,
  };
}

type Calculo = Awaited<ReturnType<typeof calcular>>;

/** Precio, duración, especialidades exigidas y snapshot del inmueble. Valida contra la BD. */
async function calcular(clienteId: number, p: Pedido, tx: Tx = prisma) {
  const ahora = relojDominio.ahora();
  if (p.programada.getTime() <= ahora.getTime()) throw invalido("La fecha del servicio debe ser futura", "FECHA_PASADA");
  if (p.programada.getTime() > ahora.getTime() + DIAS_MAXIMOS_DE_ANTICIPACION * 24 * HORA) {
    throw invalido(`Solo se puede programar con ${DIAS_MAXIMOS_DE_ANTICIPACION} días de anticipación como máximo`, "FECHA_DEMASIADO_LEJANA");
  }
  const servicio = await tx.servicios.findUnique({ where: { id: p.servicioId } });
  if (!servicio || servicio.estado !== "ACTIVO") throw new AppError(404, "Ese servicio no está disponible", "SERVICIO_NO_ENCONTRADO");
  const extras = p.extraIds.length ? await tx.servicios_extra.findMany({ where: { id: { in: p.extraIds }, estado: "ACTIVO" } }) : [];
  if (extras.length !== p.extraIds.length) throw new AppError(404, "Algún servicio extra no está disponible", "EXTRA_NO_ENCONTRADO");
  const areas = p.areaIds.length ? await tx.areas_limpieza.findMany({ where: { id: { in: p.areaIds }, estado: "ACTIVO" } }) : [];
  if (areas.length !== p.areaIds.length) throw new AppError(404, "Algún área no está disponible", "AREA_NO_ENCONTRADA");

  let inmueble: { id: number | null; nombre: string | null; datos: DatosInmueble; guardarComo: string | null };
  if ("inmuebleId" in p.inmueble) {
    const fila = await inmueblePropio(clienteId, p.inmueble.inmuebleId, tx);
    inmueble = {
      id: fila.id,
      nombre: fila.alias,
      datos: { tipo: fila.tipo, direccion: fila.direccion, habitaciones: fila.habitaciones, banos: fila.banos, mediosBanos: fila.medios_banos, pisos: fila.pisos },
      guardarComo: null,
    };
  } else {
    inmueble = { id: null, nombre: p.inmueble.guardarComo, datos: p.inmueble.datos, guardarComo: p.inmueble.guardarComo };
  }

  const especialidadesServicio = await tx.servicio_especialidades.findMany({ where: { servicio_id: servicio.id }, include: { especialidades: true } });
  const especialidadesExtras = extras.length
    ? await tx.extra_especialidades.findMany({ where: { extra_id: { in: extras.map((e) => e.id) } }, include: { especialidades: true } })
    : [];
  const exigidas = new Map<number, string>();
  for (const e of [...especialidadesServicio, ...especialidadesExtras]) exigidas.set(e.especialidad_id, e.especialidades.nombre);

  const base = Number(servicio.precio_base);
  const precioExtras = extras.reduce((a, e) => a + Number(e.precio), 0);
  const total = base + precioExtras;
  const duracionMin = servicio.duracion_estimada_min + extras.reduce((a, e) => a + e.duracion_estimada_min, 0);
  const fin = new Date(p.programada.getTime() + duracionMin * MIN);
  const porcentaje = await parametro("PORCENTAJE_TRABAJADOR", tx);
  return { servicio, extras, areas, inmueble, exigidas, base, precioExtras, total, duracionMin, fin, porcentaje };
}

function dtoCotizacion(c: Calculo, programada: Date) {
  return {
    servicio: { id: c.servicio.id, nombre: c.servicio.nombre },
    fechaProgramada: programada.toISOString(),
    duracionMin: c.duracionMin,
    finEstimado: c.fin.toISOString(),
    precio: { base: c.base, extras: c.precioExtras, total: c.total, moneda: "MXN" },
    extras: c.extras.map((e) => ({ id: e.id, nombre: e.nombre, precio: Number(e.precio), duracionMin: e.duracion_estimada_min })),
    areas: c.areas.map((a) => ({ id: a.id, nombre: a.nombre })),
    inmueble: { id: c.inmueble.id, nombre: c.inmueble.nombre, ...c.inmueble.datos },
    especialidadesRequeridas: [...c.exigidas.values()].sort(),
    metodoPago: "EFECTIVO" as const,
  };
}

/** POST /api/cliente/cotizaciones — no crea nada; se permite con la INE en revisión (D65). */
export async function cotizar(clienteId: number, cuerpo: Cuerpo) {
  const pedido = leerPedido(cuerpo, { conTrabajador: false });
  return dtoCotizacion(await calcular(clienteId, pedido), pedido.programada);
}

// ════════════════════════════════════════════════════════════════════
// Elegibilidad y traslapes
// ════════════════════════════════════════════════════════════════════

/** Hay traslape si inicio < finOtro + margen y fin + margen > inicioOtro (`11` §4.2). */
export function seTraslapan(a: { inicio: Date; fin: Date }, b: { inicio: Date; fin: Date }, margenMin: number): boolean {
  const m = margenMin * MIN;
  return a.inicio.getTime() < b.fin.getTime() + m && a.fin.getTime() + m > b.inicio.getTime();
}

type Intervalo = { inicio: Date; fin: Date };
const intervaloDe = (s: { fecha_hora_programada: Date; fecha_hora_fin_estimada: Date | null; duracion_estimada_min: number | null }): Intervalo => ({
  inicio: s.fecha_hora_programada,
  fin: s.fecha_hora_fin_estimada ?? new Date(s.fecha_hora_programada.getTime() + (s.duracion_estimada_min ?? 0) * MIN),
});

/** Servicios del trabajador que ocupan su agenda: CONFIRMADO y EN_PROCESO aún sin marcar terminado. */
async function agendaOcupada(tx: Tx, trabajadorId: number, excluirId?: number) {
  return tx.solicitudes.findMany({
    where: {
      trabajador_id: trabajadorId,
      ...(excluirId ? { id: { not: excluirId } } : {}),
      OR: [{ estado: "CONFIRMADO" }, { estado: "EN_PROCESO", trabajador_marco_realizado_en: null }],
    },
    select: { id: true, estado: true, fecha_hora_programada: true, fecha_hora_fin_estimada: true, duracion_estimada_min: true },
  });
}

export type MotivoNoElegible = "NO_ACTIVO" | "NO_VERIFICADO" | "SIN_ESPECIALIDADES" | "TRASLAPE";

/** null si el trabajador es elegible para ese intervalo y esas especialidades; si no, el motivo. */
export async function motivoNoElegible(tx: Tx, trabajadorId: number, exigidas: number[], intervalo: Intervalo, excluirSolicitudId?: number): Promise<MotivoNoElegible | null> {
  const t = await tx.trabajadores.findUnique({ where: { id: trabajadorId }, select: { estado: true, estado_verificacion: true } });
  if (!t || t.estado !== "ACTIVO") return "NO_ACTIVO";
  if (t.estado_verificacion !== "VERIFICADO") return "NO_VERIFICADO";
  if (exigidas.length) {
    const propias = await tx.trabajador_especialidades.count({ where: { trabajador_id: trabajadorId, especialidad_id: { in: exigidas } } });
    if (propias < exigidas.length) return "SIN_ESPECIALIDADES";
  }
  const margen = await parametro("MARGEN_TRASLADO_MIN", tx);
  const agenda = await agendaOcupada(tx, trabajadorId, excluirSolicitudId);
  if (agenda.some((s) => seTraslapan(intervalo, intervaloDe(s), margen))) return "TRASLAPE";
  return null;
}

const MENSAJES_NO_ELEGIBLE: Record<MotivoNoElegible, string> = {
  NO_ACTIVO: "Ese colaborador no está disponible",
  NO_VERIFICADO: "Ese colaborador aún no está verificado",
  SIN_ESPECIALIDADES: "Ese colaborador no tiene las especialidades que requiere el servicio",
  TRASLAPE: "Ese colaborador ya tiene un servicio en ese horario (se consideran 60 min de traslado)",
};

/** Ids de trabajadores elegibles para un intervalo (selección manual con fecha). */
export async function filtrarElegibles(ids: number[], exigidas: number[], intervalo: Intervalo): Promise<Set<number>> {
  const elegibles = new Set<number>();
  for (const id of ids) if ((await motivoNoElegible(prisma, id, exigidas, intervalo)) === null) elegibles.add(id);
  return elegibles;
}

// ════════════════════════════════════════════════════════════════════
// Crear
// ════════════════════════════════════════════════════════════════════

/** POST /api/cliente/solicitudes */
export async function crearSolicitud(clienteId: number, cuerpo: Cuerpo) {
  const pedido = leerPedido(cuerpo, { conTrabajador: true });
  const cliente = await prisma.usuarios.findUnique({ where: { id: clienteId }, select: { estado_verificacion: true, estado_cuenta: true, nombre_completo: true } });
  if (!cliente || cliente.estado_cuenta !== "ACTIVA") throw new AppError(403, "Tu cuenta no está activa", "CUENTA_SUSPENDIDA");
  if (cliente.estado_verificacion !== "VERIFICADO") {
    throw new AppError(
      403,
      `Para enviar una solicitud necesitas tener tu identidad (INE) aprobada. Estado actual: ${cliente.estado_verificacion ?? "PENDIENTE"}`,
      "IDENTIDAD_NO_VERIFICADA",
    );
  }

  const creada = await prisma.$transaction(async (tx) => {
    const c = await calcular(clienteId, pedido, tx);
    const duplicada = await tx.solicitudes.findFirst({
      where: { cliente_id: clienteId, servicio_id: c.servicio.id, fecha_hora_programada: pedido.programada, direccion_servicio: c.inmueble.datos.direccion, estado: "PENDIENTE" },
      select: { id: true },
    });
    if (duplicada) throw conflicto("Ya enviaste una solicitud igual que sigue pendiente", "SOLICITUD_DUPLICADA");

    let inmuebleId = c.inmueble.id;
    if (c.inmueble.guardarComo) inmuebleId = (await crearInmueble(clienteId, c.inmueble.guardarComo, c.inmueble.datos, tx)).id;

    const exigidas = [...c.exigidas.keys()];
    if (pedido.trabajadorId !== null) {
      const motivo = await motivoNoElegible(tx, pedido.trabajadorId, exigidas, { inicio: pedido.programada, fin: c.fin });
      if (motivo) throw conflicto(MENSAJES_NO_ELEGIBLE[motivo], `COLABORADOR_${motivo}`);
    }

    const ahora = relojDominio.ahora();
    const ganancia = (c.total * c.porcentaje) / 100;
    const s = await tx.solicitudes.create({
      data: {
        cliente_id: clienteId,
        servicio_id: c.servicio.id,
        servicio_nombre_aplicado: c.servicio.nombre,
        inmueble_id: inmuebleId,
        inmueble_alias_aplicado: c.inmueble.nombre,
        inmueble_tipo_aplicado: c.inmueble.datos.tipo,
        habitaciones_aplicado: c.inmueble.datos.habitaciones,
        banos_aplicado: c.inmueble.datos.banos,
        medios_banos_aplicado: c.inmueble.datos.mediosBanos,
        pisos_aplicado: c.inmueble.datos.pisos,
        direccion_servicio: c.inmueble.datos.direccion,
        fecha_hora_programada: pedido.programada,
        duracion_estimada_min: c.duracionMin,
        fecha_hora_fin_estimada: c.fin,
        notas: pedido.notas,
        precio_estimado: dinero(c.total),
        precio_base_aplicado: dinero(c.base),
        precio_tamano_aplicado: dinero(0),
        precio_ajuste_tipo_aplicado: dinero(0),
        precio_extras_aplicado: dinero(c.precioExtras),
        precio_descuento_aplicado: dinero(0),
        porcentaje_trabajador_aplicado: dinero(c.porcentaje),
        ganancia_trabajador: dinero(ganancia),
        comision_plataforma: dinero(c.total - ganancia),
        metodo_pago: "EFECTIVO",
        estado_pago: "PENDIENTE",
        modo_eleccion: pedido.trabajadorId === null ? "AUTOMATICA" : "MANUAL",
        estado: "PENDIENTE",
        created_at: ahora,
        updated_at: ahora,
      },
    });
    if (c.exigidas.size) {
      await tx.solicitud_especialidades.createMany({ data: [...c.exigidas].map(([id, nombre]) => ({ solicitud_id: s.id, especialidad_id: id, nombre_aplicado: nombre })) });
    }
    if (c.areas.length) await tx.solicitud_areas.createMany({ data: c.areas.map((a) => ({ solicitud_id: s.id, area_id: a.id, nombre_aplicado: a.nombre })) });
    if (c.extras.length) {
      await tx.solicitud_extras.createMany({
        data: c.extras.map((e) => ({ solicitud_id: s.id, extra_id: e.id, nombre_aplicado: e.nombre, precio_aplicado: e.precio, duracion_aplicada_min: e.duracion_estimada_min })),
      });
    }
    await historial(tx, s.id, { anterior: null, nuevo: "PENDIENTE", actor: "CLIENTE", actorId: clienteId, motivo: pedido.trabajadorId ? "Solicitud creada con invitación" : "Solicitud creada en la bolsa" });
    if (pedido.trabajadorId !== null) await invitar(tx, s, pedido.trabajadorId, cliente.nombre_completo);
    return s.id;
  });
  return detalleParaCliente(clienteId, creada);
}

/** Crea (o reabre si estaba CERRADA) la invitación y avisa al trabajador. */
async function invitar(tx: Tx, s: solicitudes, trabajadorId: number, nombreCliente: string) {
  const ahora = relojDominio.ahora();
  const previa = await tx.solicitud_trabajadores.findUnique({ where: { solicitud_id_trabajador_id: { solicitud_id: s.id, trabajador_id: trabajadorId } } });
  if (previa && previa.estado !== "CERRADA") {
    throw conflicto(
      previa.estado === "RECHAZADA" || previa.estado === "CANCELADA" ? "Ese colaborador ya rechazó o canceló esta solicitud" : "Ese colaborador ya está invitado",
      "INVITACION_NO_PERMITIDA",
    );
  }
  if (previa) {
    await tx.solicitud_trabajadores.update({ where: { id: previa.id }, data: { origen: "INVITACION", estado: "PENDIENTE", motivo_cierre: null, respondida_en: null, updated_at: ahora } });
  } else {
    await tx.solicitud_trabajadores.create({ data: { solicitud_id: s.id, trabajador_id: trabajadorId, origen: "INVITACION", estado: "PENDIENTE", created_at: ahora, updated_at: ahora } });
  }
  await avisarTrabajador(tx, trabajadorId, {
    tipo: "INVITACION_NUEVA",
    clave: `INVITACION_NUEVA:sol:${s.id}:${ahora.getTime()}`,
    titulo: "Tienes una invitación nueva",
    mensaje: `${nombreCliente.split(" ")[0]} te invitó a ${nombreServicio(s)} el ${enLocal(s.fecha_hora_programada)}.`,
    solicitudId: s.id,
  });
}

// ════════════════════════════════════════════════════════════════════
// Acciones del cliente
// ════════════════════════════════════════════════════════════════════

async function solicitudDelCliente(tx: Tx, clienteId: number, id: number) {
  const s = await bloquearSolicitud(tx, id);
  if (s.cliente_id !== clienteId) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  return s;
}

/** Tras un rechazo: enviar a la bolsa (cierra las invitaciones pendientes). */
export async function enviarABolsa(clienteId: number, id: number) {
  await prisma.$transaction(async (tx) => {
    const s = await solicitudDelCliente(tx, clienteId, id);
    if (s.estado !== "PENDIENTE") throw conflicto("Solo una solicitud pendiente se puede enviar a la bolsa", "ESTADO_NO_PERMITIDO");
    if (s.modo_eleccion === "AUTOMATICA") throw conflicto("La solicitud ya está en la bolsa", "YA_EN_BOLSA");
    if (s.fecha_hora_programada.getTime() <= relojDominio.ahora().getTime()) throw conflicto("La hora del servicio ya pasó", "SOLICITUD_VENCIDA");
    const ahora = relojDominio.ahora();
    await tx.solicitud_trabajadores.updateMany({ where: { solicitud_id: id, estado: "PENDIENTE" }, data: { estado: "CERRADA", motivo_cierre: "CAMBIO_A_AUTOMATICA", updated_at: ahora } });
    await cambiarEstado(tx, id, "PENDIENTE", { modo_eleccion: "AUTOMATICA" }, "La solicitud cambió mientras tanto", "ESTADO_CAMBIO");
    await historial(tx, id, { anterior: "PENDIENTE", nuevo: "PENDIENTE", actor: "CLIENTE", actorId: clienteId, motivo: "Enviada a la bolsa" });
  });
  return detalleParaCliente(clienteId, id);
}

/** Tras un rechazo: invitar a otro colaborador elegible (máx. MAX_INVITACIONES_PENDIENTES). */
export async function invitarOtro(clienteId: number, id: number, cuerpo: Cuerpo) {
  const trabajadorId = idPositivo(cuerpo.trabajadorId, "el colaborador (trabajadorId)");
  await prisma.$transaction(async (tx) => {
    const s = await solicitudDelCliente(tx, clienteId, id);
    if (s.estado !== "PENDIENTE") throw conflicto("Solo se puede invitar en una solicitud pendiente", "ESTADO_NO_PERMITIDO");
    if (s.modo_eleccion === "AUTOMATICA") throw conflicto("La solicitud está en la bolsa: cualquier colaborador elegible puede tomarla", "YA_EN_BOLSA");
    if (s.fecha_hora_programada.getTime() <= relojDominio.ahora().getTime()) throw conflicto("La hora del servicio ya pasó", "SOLICITUD_VENCIDA");
    const pendientes = await tx.solicitud_trabajadores.count({ where: { solicitud_id: id, estado: "PENDIENTE" } });
    if (pendientes >= (await parametro("MAX_INVITACIONES_PENDIENTES", tx))) throw conflicto("Ya tienes el máximo de invitaciones pendientes", "MAXIMO_INVITACIONES");
    const exigidas = (await tx.solicitud_especialidades.findMany({ where: { solicitud_id: id }, select: { especialidad_id: true } })).map((e) => e.especialidad_id);
    const motivo = await motivoNoElegible(tx, trabajadorId, exigidas, intervaloDe(s));
    if (motivo) throw conflicto(MENSAJES_NO_ELEGIBLE[motivo], `COLABORADOR_${motivo}`);
    const cliente = await tx.usuarios.findUniqueOrThrow({ where: { id: clienteId }, select: { nombre_completo: true } });
    await invitar(tx, s, trabajadorId, cliente.nombre_completo);
    await historial(tx, id, { anterior: "PENDIENTE", nuevo: "PENDIENTE", actor: "CLIENTE", actorId: clienteId, motivo: `Invitó a otro colaborador (#${trabajadorId})` });
  });
  return detalleParaCliente(clienteId, id);
}

/** ¿Se puede cancelar sin cargo? (PENDIENTE, o CONFIRMADO con 24 h o más). */
function evaluarCancelacion(s: Pick<solicitudes, "estado" | "fecha_hora_programada">, ahora: Date): { ok: true } | { ok: false; codigo: string; mensaje: string } {
  if (s.estado === "PENDIENTE") return { ok: true };
  if (s.estado === "CONFIRMADO") {
    if (s.fecha_hora_programada.getTime() - ahora.getTime() >= HORAS_CANCELACION_SIN_CARGO * HORA) return { ok: true };
    return {
      ok: false,
      codigo: "CANCELACION_NO_DISPONIBLE",
      mensaje: `Con menos de ${HORAS_CANCELACION_SIN_CARGO} h de anticipación la cancelación tiene cargo y todavía no está disponible`,
    };
  }
  return { ok: false, codigo: "NO_CANCELABLE", mensaje: "Esta solicitud ya no se puede cancelar" };
}

function leerMotivoOpcional(cuerpo: Cuerpo): string | null {
  const v = cuerpo.motivo;
  if (v === undefined || v === null) return null;
  if (typeof v !== "string") throw invalido("El motivo debe ser texto");
  const t = v.trim();
  if ([...t].length > 200) throw invalido("El motivo admite como máximo 200 caracteres");
  return t || null;
}

export async function cancelarPorCliente(clienteId: number, id: number, cuerpo: Cuerpo) {
  const motivo = leerMotivoOpcional(cuerpo);
  await prisma.$transaction(async (tx) => {
    const s = await solicitudDelCliente(tx, clienteId, id);
    const ev = evaluarCancelacion(s, relojDominio.ahora());
    if (!ev.ok) throw conflicto(ev.mensaje, ev.codigo);
    const ahora = relojDominio.ahora();
    const afectados = await tx.solicitud_trabajadores.findMany({ where: { solicitud_id: id, estado: { in: ["PENDIENTE", "ACEPTADA"] } }, select: { trabajador_id: true } });
    await tx.solicitud_trabajadores.updateMany({ where: { solicitud_id: id, estado: { in: ["PENDIENTE", "ACEPTADA"] } }, data: { estado: "CERRADA", motivo_cierre: "CLIENTE_CANCELO", updated_at: ahora } });
    await cambiarEstado(tx, id, s.estado, { estado: "CANCELADO" }, "La solicitud cambió mientras tanto", "ESTADO_CAMBIO");
    await historial(tx, id, { anterior: s.estado, nuevo: "CANCELADO", actor: "CLIENTE", actorId: clienteId, motivo: motivo ? `Cancelada por el cliente: ${motivo}` : "Cancelada por el cliente" });
    for (const a of afectados) {
      await avisarTrabajador(tx, a.trabajador_id, {
        tipo: "SOLICITUD_CANCELADA_POR_CLIENTE",
        clave: `SOLICITUD_CANCELADA_POR_CLIENTE:sol:${id}`,
        titulo: "El cliente canceló la solicitud",
        mensaje: `${nombreServicio(s)} del ${enLocal(s.fecha_hora_programada)} fue cancelada por el cliente.`,
        solicitudId: id,
      });
    }
  });
  return detalleParaCliente(clienteId, id);
}

/** El cliente confirma que se realizó (D54). Con un reporte activo, decide el admin (D57). */
export async function confirmarPorCliente(clienteId: number, id: number) {
  await prisma.$transaction(async (tx) => {
    const s = await solicitudDelCliente(tx, clienteId, id);
    if (s.estado !== "EN_PROCESO") throw conflicto("Solo se puede confirmar un servicio en proceso", "ESTADO_NO_PERMITIDO");
    if (await tieneReportesActivos(tx, id)) throw conflicto("Hay un reporte en revisión: la administración resolverá el servicio", "REPORTE_EN_REVISION");
    const ahora = relojDominio.ahora();
    await cambiarEstado(tx, id, "EN_PROCESO", { estado: "REALIZADO", cliente_marco_realizado_en: ahora, realizado_en: ahora, realizado_via: "CLIENTE" }, "El servicio cambió mientras tanto", "ESTADO_CAMBIO");
    await historial(tx, id, { anterior: "EN_PROCESO", nuevo: "REALIZADO", actor: "CLIENTE", actorId: clienteId, motivo: "El cliente confirmó que se realizó" });
  });
  return detalleParaCliente(clienteId, id);
}

// ════════════════════════════════════════════════════════════════════
// Acciones del trabajador
// ════════════════════════════════════════════════════════════════════

/** Acepta una invitación o una solicitud de la bolsa (transacción pesimista, `11` §4.2). */
export async function aceptar(trabajadorId: number, id: number) {
  await prisma.$transaction(async (tx) => {
    await bloquearTrabajador(tx, trabajadorId); // serializa las aceptaciones de ESTE trabajador
    const s = await bloquearSolicitud(tx, id); // el segundo que llegue espera aquí y ve el cambio
    const ahora = relojDominio.ahora();
    const fila = await tx.solicitud_trabajadores.findUnique({ where: { solicitud_id_trabajador_id: { solicitud_id: id, trabajador_id: trabajadorId } } });
    const invitado = fila?.estado === "PENDIENTE" && fila.origen === "INVITACION";
    const enBolsa = s.modo_eleccion === "AUTOMATICA" && (!fila || fila.estado === "CERRADA" || fila.estado === "PENDIENTE");
    if (!invitado && !enBolsa) throw new AppError(404, "No tienes acceso a esa solicitud", "SOLICITUD_NO_DISPONIBLE");
    if (s.estado !== "PENDIENTE" || s.trabajador_id !== null) throw conflicto("Otro colaborador ya tomó esta solicitud o ya no está disponible", "SOLICITUD_YA_TOMADA");
    if (s.fecha_hora_programada.getTime() <= ahora.getTime()) throw conflicto("La hora del servicio ya pasó", "SOLICITUD_VENCIDA");
    const exigidas = (await tx.solicitud_especialidades.findMany({ where: { solicitud_id: id }, select: { especialidad_id: true } })).map((e) => e.especialidad_id);
    const motivo = await motivoNoElegible(tx, trabajadorId, exigidas, intervaloDe(s), id);
    if (motivo) throw conflicto(MENSAJES_NO_ELEGIBLE[motivo].replace("Ese colaborador", "Tu cuenta").replace("ya tiene", "tiene"), `NO_ELEGIBLE_${motivo}`);

    const r = await tx.solicitudes.updateMany({ where: { id, estado: "PENDIENTE", trabajador_id: null }, data: { estado: "CONFIRMADO", trabajador_id: trabajadorId, updated_at: ahora } });
    if (r.count !== 1) throw conflicto("Otro colaborador ya tomó esta solicitud", "SOLICITUD_YA_TOMADA");
    if (fila) {
      await tx.solicitud_trabajadores.update({ where: { id: fila.id }, data: { estado: "ACEPTADA", motivo_cierre: null, respondida_en: ahora, updated_at: ahora } });
    } else {
      await tx.solicitud_trabajadores.create({ data: { solicitud_id: id, trabajador_id: trabajadorId, origen: "BOLSA", estado: "ACEPTADA", created_at: ahora, respondida_en: ahora, updated_at: ahora } });
    }
    await tx.solicitud_trabajadores.updateMany({
      where: { solicitud_id: id, estado: "PENDIENTE", trabajador_id: { not: trabajadorId } },
      data: { estado: "CERRADA", motivo_cierre: "OTRO_TRABAJADOR_ACEPTO", updated_at: ahora },
    });
    // Sus otras invitaciones pendientes que ahora se cruzan con este servicio.
    const margen = await parametro("MARGEN_TRASLADO_MIN", tx);
    const otras = await tx.solicitud_trabajadores.findMany({
      where: { trabajador_id: trabajadorId, estado: "PENDIENTE", solicitud_id: { not: id } },
      include: { solicitudes: { select: { fecha_hora_programada: true, fecha_hora_fin_estimada: true, duracion_estimada_min: true } } },
    });
    const cruzadas = otras.filter((o) => seTraslapan(intervaloDe(s), intervaloDe(o.solicitudes), margen)).map((o) => o.id);
    if (cruzadas.length) await tx.solicitud_trabajadores.updateMany({ where: { id: { in: cruzadas } }, data: { estado: "CERRADA", motivo_cierre: "TRABAJADOR_OCUPADO", updated_at: ahora } });

    await historial(tx, id, { anterior: "PENDIENTE", nuevo: "CONFIRMADO", actor: "TRABAJADOR", actorId: trabajadorId, motivo: invitado ? "Aceptó la invitación" : "Tomó la solicitud de la bolsa" });
    const trabajador = await tx.trabajadores.findUniqueOrThrow({ where: { id: trabajadorId }, select: { nombre_completo: true } });
    await avisarCliente(tx, s.cliente_id, {
      tipo: "SERVICIO_CONFIRMADO",
      clave: `SERVICIO_CONFIRMADO:sol:${id}:t:${trabajadorId}`,
      titulo: "¡Tu servicio está confirmado!",
      mensaje: `${trabajador.nombre_completo} atenderá ${nombreServicio(s)} el ${enLocal(s.fecha_hora_programada)}.`,
      solicitudId: id,
    });
  });
  return detalleParaTrabajador(trabajadorId, id);
}

/** Rechaza una invitación (avisa al cliente) o una solicitud de la bolsa (deja de verla). Definitivo. */
export async function rechazar(trabajadorId: number, id: number) {
  await prisma.$transaction(async (tx) => {
    const s = await bloquearSolicitud(tx, id);
    const ahora = relojDominio.ahora();
    const fila = await tx.solicitud_trabajadores.findUnique({ where: { solicitud_id_trabajador_id: { solicitud_id: id, trabajador_id: trabajadorId } } });
    if (fila?.estado === "PENDIENTE") {
      if (s.estado !== "PENDIENTE") throw conflicto("Esta solicitud ya no está disponible", "ESTADO_NO_PERMITIDO");
      await tx.solicitud_trabajadores.update({ where: { id: fila.id }, data: { estado: "RECHAZADA", respondida_en: ahora, updated_at: ahora } });
      const trabajador = await tx.trabajadores.findUniqueOrThrow({ where: { id: trabajadorId }, select: { nombre_completo: true } });
      await avisarCliente(tx, s.cliente_id, {
        tipo: "INVITACION_RECHAZADA",
        clave: `INVITACION_RECHAZADA:sol:${id}:t:${trabajadorId}`,
        titulo: "Tu invitación fue rechazada",
        mensaje: `${trabajador.nombre_completo} no puede atender ${nombreServicio(s)}. Puedes enviarla a la bolsa, invitar a otro colaborador o cancelarla.`,
        solicitudId: id,
      });
      return;
    }
    const enBolsa = s.estado === "PENDIENTE" && s.modo_eleccion === "AUTOMATICA" && s.trabajador_id === null && (!fila || fila.estado === "CERRADA");
    if (!enBolsa) throw new AppError(404, "No tienes acceso a esa solicitud", "SOLICITUD_NO_DISPONIBLE");
    if (fila) await tx.solicitud_trabajadores.update({ where: { id: fila.id }, data: { estado: "RECHAZADA", motivo_cierre: null, respondida_en: ahora, updated_at: ahora } });
    else await tx.solicitud_trabajadores.create({ data: { solicitud_id: id, trabajador_id: trabajadorId, origen: "BOLSA", estado: "RECHAZADA", created_at: ahora, respondida_en: ahora, updated_at: ahora } });
  });
  return { id, rechazada: true };
}

async function solicitudAsignada(tx: Tx, trabajadorId: number, id: number) {
  const s = await bloquearSolicitud(tx, id);
  if (s.trabajador_id !== trabajadorId) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  return s;
}

/** El trabajador cancela un CONFIRMADO con 24 h o más: vuelve a la bolsa (`11` §4.4), sin cargo. */
export async function cancelarPorTrabajador(trabajadorId: number, id: number, cuerpo: Cuerpo) {
  const motivo = leerMotivoOpcional(cuerpo);
  await prisma.$transaction(async (tx) => {
    const s = await solicitudAsignada(tx, trabajadorId, id);
    if (s.estado !== "CONFIRMADO") throw conflicto("Solo se puede cancelar un servicio confirmado que no ha iniciado", "NO_CANCELABLE");
    const ev = evaluarCancelacion(s, relojDominio.ahora());
    if (!ev.ok) throw conflicto(ev.mensaje, ev.codigo);
    const ahora = relojDominio.ahora();
    await cambiarEstado(tx, id, "CONFIRMADO", { estado: "PENDIENTE", trabajador_id: null, modo_eleccion: "AUTOMATICA" }, "El servicio cambió mientras tanto", "ESTADO_CAMBIO");
    await tx.solicitud_trabajadores.updateMany({ where: { solicitud_id: id, trabajador_id: trabajadorId }, data: { estado: "CANCELADA", motivo_cierre: "TRABAJADOR_CANCELO", updated_at: ahora } });
    await historial(tx, id, {
      anterior: "CONFIRMADO",
      nuevo: "PENDIENTE",
      actor: "TRABAJADOR",
      actorId: trabajadorId,
      motivo: motivo ? `El colaborador canceló: ${motivo}. Vuelve a la bolsa` : "El colaborador canceló. Vuelve a la bolsa",
    });
    await avisarCliente(tx, s.cliente_id, {
      tipo: "SOLICITUD_DEVUELTA_A_BOLSA",
      clave: `SOLICITUD_DEVUELTA_A_BOLSA:sol:${id}:t:${trabajadorId}`,
      titulo: "Tu colaborador canceló",
      mensaje: `${nombreServicio(s)} del ${enLocal(s.fecha_hora_programada)} volvió a la bolsa para que otro colaborador la tome.`,
      solicitudId: id,
    });
  });
  return { id, cancelada: true };
}

/** Ventana para iniciar: [programada − 30 min, programada + 30 min]. */
export function ventanaDeInicio(programada: Date) {
  return { desde: new Date(programada.getTime() - VENTANA_INICIO_MIN * MIN), hasta: new Date(programada.getTime() + VENTANA_INICIO_MIN * MIN) };
}

export async function iniciar(trabajadorId: number, id: number) {
  await prisma.$transaction(async (tx) => {
    await bloquearTrabajador(tx, trabajadorId);
    const s = await solicitudAsignada(tx, trabajadorId, id);
    if (s.estado !== "CONFIRMADO") throw conflicto("Solo se puede iniciar un servicio confirmado", "ESTADO_NO_PERMITIDO");
    const ahora = relojDominio.ahora();
    const v = ventanaDeInicio(s.fecha_hora_programada);
    if (ahora.getTime() < v.desde.getTime()) throw conflicto(`Podrás iniciar desde ${VENTANA_INICIO_MIN} min antes de la hora programada`, "ANTES_DE_LA_VENTANA");
    if (ahora.getTime() > v.hasta.getTime()) {
      throw conflicto(`Pasaron más de ${VENTANA_INICIO_MIN} min de la hora programada: ya no se puede iniciar. La administración revisará el caso`, "DESPUES_DE_LA_VENTANA");
    }
    const t = await tx.trabajadores.findUniqueOrThrow({ where: { id: trabajadorId }, select: { estado: true, estado_verificacion: true } });
    if (t.estado !== "ACTIVO" || t.estado_verificacion !== "VERIFICADO") throw conflicto("Tu cuenta no está activa y verificada", "NO_ELEGIBLE_NO_ACTIVO");
    const agenda = await agendaOcupada(tx, trabajadorId, id);
    if (agenda.some((o) => o.estado === "EN_PROCESO")) throw conflicto("Tienes otro servicio en curso: márcalo como terminado antes de iniciar este", "OTRO_SERVICIO_EN_CURSO");
    const duracion = s.duracion_estimada_min ?? Math.round(((s.fecha_hora_fin_estimada?.getTime() ?? ahora.getTime()) - s.fecha_hora_programada.getTime()) / MIN);
    const real = { inicio: ahora, fin: new Date(ahora.getTime() + duracion * MIN) };
    const margen = await parametro("MARGEN_TRASLADO_MIN", tx);
    if (agenda.some((o) => seTraslapan(real, intervaloDe(o), margen))) {
      throw conflicto("Iniciar ahora se cruzaría con otro de tus servicios (se consideran 60 min de traslado)", "TRASLAPE");
    }
    await cambiarEstado(tx, id, "CONFIRMADO", { estado: "EN_PROCESO" }, "El servicio cambió mientras tanto", "ESTADO_CAMBIO");
    await historial(tx, id, { anterior: "CONFIRMADO", nuevo: "EN_PROCESO", actor: "TRABAJADOR", actorId: trabajadorId, motivo: "Inició el servicio" });
  });
  return detalleParaTrabajador(trabajadorId, id);
}

/** «Terminado» con 1 a 5 fotos de evidencia (D54). Las fotos se guardan antes; si la BD falla, se borran. */
export async function terminar(trabajadorId: number, id: number, archivos: ArchivoRecibido[]) {
  if (archivos.length === 0) throw invalido("Sube al menos 1 fotografía del trabajo terminado", "FOTOS_REQUERIDAS");
  const previa = await prisma.solicitudes.findUnique({ where: { id }, select: { trabajador_id: true, estado: true, trabajador_marco_realizado_en: true } });
  if (!previa || previa.trabajador_id !== trabajadorId) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  if (previa.estado !== "EN_PROCESO") throw conflicto("Solo se puede terminar un servicio en proceso", "ESTADO_NO_PERMITIDO");
  if (previa.trabajador_marco_realizado_en) throw conflicto("Ya marcaste este servicio como terminado", "YA_TERMINADO");
  const validados = validarFotos(archivos);
  const guardados: ObjetoGuardado[] = [];
  try {
    for (const a of validados) guardados.push(await almacenamiento().guardar("evidencias", `solicitud-${id}`, a));
    await prisma.$transaction(async (tx) => {
      const s = await solicitudAsignada(tx, trabajadorId, id);
      const ahora = relojDominio.ahora();
      const r = await tx.solicitudes.updateMany({ where: { id, estado: "EN_PROCESO", trabajador_marco_realizado_en: null }, data: { trabajador_marco_realizado_en: ahora, updated_at: ahora } });
      if (r.count !== 1) throw conflicto("El servicio cambió mientras tanto", "ESTADO_CAMBIO");
      for (const g of guardados) {
        await tx.evidencias_solicitud.create({
          data: { solicitud_id: s.id, reporte_id: null, aportada_por: "TRABAJADOR", archivo_url: g.clave, tipo_mime: g.mime, tamano_bytes: g.bytes, sha256: g.sha256, descripcion: "Trabajo terminado", created_at: ahora },
        });
      }
      await historial(tx, id, { anterior: "EN_PROCESO", nuevo: "EN_PROCESO", actor: "TRABAJADOR", actorId: trabajadorId, motivo: `Marcó el servicio como terminado (${guardados.length} foto(s))` });
    });
  } catch (error) {
    await Promise.all(guardados.map((g) => almacenamiento().eliminar(g.clave).catch(() => undefined)));
    throw error;
  }
  return detalleParaTrabajador(trabajadorId, id);
}
export { LIMITES_FOTOS };

// ════════════════════════════════════════════════════════════════════
// Vistas (lo que ve cada app). El servidor vuelve a validar todo al actuar.
// ════════════════════════════════════════════════════════════════════

type SolicitudCompleta = Prisma.solicitudesGetPayload<{
  include: {
    solicitud_areas: true;
    solicitud_extras: true;
    solicitud_trabajadores: { include: { trabajadores: { select: { id: true; nombre_completo: true } } } };
    evidencias_solicitud: { select: { id: true; tipo_mime: true; tamano_bytes: true; created_at: true; reporte_id: true; aportada_por: true; eliminada_en: true } };
  };
}>;

const INCLUIR_COMPLETA = {
  solicitud_areas: true,
  solicitud_extras: true,
  solicitud_trabajadores: { include: { trabajadores: { select: { id: true, nombre_completo: true } } } },
  evidencias_solicitud: { select: { id: true, tipo_mime: true, tamano_bytes: true, created_at: true, reporte_id: true, aportada_por: true, eliminada_en: true } },
} as const;

/** Fotos de «terminado» (del trabajador, sin reporte, no eliminadas). */
export function fotosDeTerminado(s: Pick<SolicitudCompleta, "evidencias_solicitud">) {
  return s.evidencias_solicitud
    .filter((e) => e.reporte_id === null && e.aportada_por === "TRABAJADOR" && e.eliminada_en === null)
    .map((e) => ({ id: e.id, tipoMime: e.tipo_mime, tamanoBytes: e.tamano_bytes, fecha: e.created_at.toISOString() }));
}

function datosComunes(s: SolicitudCompleta) {
  return {
    id: s.id,
    estado: s.estado,
    modo: s.modo_eleccion === "MANUAL" ? ("INVITACION" as const) : ("BOLSA" as const),
    servicio: s.servicio_nombre_aplicado ?? "",
    fechaProgramada: s.fecha_hora_programada.toISOString(),
    finEstimado: fechaIso(s.fecha_hora_fin_estimada),
    duracionMin: s.duracion_estimada_min,
    inmueble: {
      nombre: s.inmueble_alias_aplicado,
      tipo: s.inmueble_tipo_aplicado,
      habitaciones: s.habitaciones_aplicado,
      banos: s.banos_aplicado,
      mediosBanos: s.medios_banos_aplicado,
      pisos: s.pisos_aplicado,
    },
    areas: s.solicitud_areas.map((a) => a.nombre_aplicado),
    extras: s.solicitud_extras.map((e) => ({ nombre: e.nombre_aplicado, precio: Number(e.precio_aplicado) })),
    notas: s.notas,
    precio: Number(s.precio_estimado),
    metodoPago: s.metodo_pago,
    marcas: {
      trabajadorTerminoEn: fechaIso(s.trabajador_marco_realizado_en),
      clienteConfirmoEn: fechaIso(s.cliente_marco_realizado_en),
      confirmacionSolicitadaEn: fechaIso(s.confirmacion_solicitada_en),
      avisoEvidenciaEn: fechaIso(s.aviso_evidencia_en),
      realizadoEn: fechaIso(s.realizado_en),
      realizadoVia: s.realizado_via,
    },
    fotosTerminado: fotosDeTerminado(s),
    creadaEn: s.created_at.toISOString(),
  };
}

/** Detalle para el CLIENTE dueño (otro → 404). */
export async function detalleParaCliente(clienteId: number, id: number) {
  const s = await prisma.solicitudes.findFirst({ where: { id, cliente_id: clienteId }, include: INCLUIR_COMPLETA });
  if (!s) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  const ahora = relojDominio.ahora();
  const reportesActivos = await tieneReportesActivos(prisma, id);
  const pendientes = s.solicitud_trabajadores.filter((t) => t.estado === "PENDIENTE");
  const asignado = s.solicitud_trabajadores.find((t) => t.estado === "ACEPTADA" && t.trabajador_id === s.trabajador_id);
  const ultimoRechazo = s.solicitud_trabajadores.filter((t) => t.estado === "RECHAZADA" && t.origen === "INVITACION").sort((a, b) => (b.respondida_en?.getTime() ?? 0) - (a.respondida_en?.getTime() ?? 0))[0];
  const ev = evaluarCancelacion(s, ahora);
  const vigente = s.estado === "PENDIENTE" && s.fecha_hora_programada.getTime() > ahora.getTime();
  return {
    ...datosComunes(s),
    direccion: s.direccion_servicio,
    trabajador: asignado ? { id: asignado.trabajador_id, nombre: asignado.trabajadores.nombre_completo } : null,
    invitaciones: s.solicitud_trabajadores
      .filter((t) => t.origen === "INVITACION")
      .map((t) => ({ trabajador: { id: t.trabajador_id, nombre: t.trabajadores.nombre_completo }, estado: t.estado, motivoCierre: t.motivo_cierre, respondidaEn: fechaIso(t.respondida_en) })),
    invitacionRechazada: s.estado === "PENDIENTE" && s.modo_eleccion === "MANUAL" && pendientes.length === 0 && ultimoRechazo ? { trabajador: ultimoRechazo.trabajadores.nombre_completo } : null,
    reporteEnRevision: reportesActivos,
    acciones: {
      puedeCancelar: ev.ok,
      motivoNoCancelar: ev.ok ? null : ev.mensaje,
      puedeEnviarABolsa: vigente && s.modo_eleccion === "MANUAL",
      puedeInvitarOtro: vigente && s.modo_eleccion === "MANUAL",
      puedeConfirmar: s.estado === "EN_PROCESO" && !reportesActivos,
    },
  };
}

/** Lo que ve el TRABAJADOR: asignado, invitado (pendiente) o en la bolsa. La dirección exacta, solo si está asignado. */
function vistaTrabajador(s: SolicitudCompleta, trabajadorId: number, relacion: "ASIGNADO" | "INVITADO" | "BOLSA", nombreCliente: string, ahora: Date) {
  const asignado = relacion === "ASIGNADO";
  const v = ventanaDeInicio(s.fecha_hora_programada);
  const ev = evaluarCancelacion(s, ahora);
  let motivoNoIniciar: string | null = null;
  if (asignado && s.estado === "CONFIRMADO") {
    if (ahora.getTime() < v.desde.getTime()) motivoNoIniciar = `Podrás iniciar desde ${enLocal(v.desde)}`;
    else if (ahora.getTime() > v.hasta.getTime()) motivoNoIniciar = "Pasó la ventana para iniciar (30 min después de la hora). La administración revisará el caso";
  }
  return {
    ...datosComunes(s),
    relacion,
    direccion: asignado ? s.direccion_servicio : null,
    cliente: { nombre: nombreCliente },
    gananciaEstimada: s.ganancia_trabajador === null ? null : Number(s.ganancia_trabajador),
    ventanaInicio: asignado ? { desde: v.desde.toISOString(), hasta: v.hasta.toISOString() } : null,
    fotosTerminado: asignado ? fotosDeTerminado(s) : [],
    acciones: {
      puedeAceptar: !asignado && s.estado === "PENDIENTE" && s.fecha_hora_programada.getTime() > ahora.getTime(),
      puedeRechazar: !asignado && s.estado === "PENDIENTE",
      puedeIniciar: asignado && s.estado === "CONFIRMADO" && motivoNoIniciar === null,
      motivoNoIniciar,
      puedeTerminar: asignado && s.estado === "EN_PROCESO" && s.trabajador_marco_realizado_en === null,
      puedeCancelar: asignado && s.estado === "CONFIRMADO" && ev.ok,
      motivoNoCancelar: asignado && s.estado === "CONFIRMADO" && !ev.ok ? ev.mensaje : null,
    },
    trabajadorId,
  };
}

async function nombresDeClientes(ids: number[]) {
  const filas = await prisma.usuarios.findMany({ where: { id: { in: [...new Set(ids)] } }, select: { id: true, nombre_completo: true } });
  return new Map(filas.map((f) => [f.id, f.nombre_completo]));
}

/** Detalle para el trabajador asignado o invitado/elegible en la bolsa (si no, 404). */
export async function detalleParaTrabajador(trabajadorId: number, id: number) {
  const s = await prisma.solicitudes.findUnique({ where: { id }, include: INCLUIR_COMPLETA });
  if (!s) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  const ahora = relojDominio.ahora();
  const fila = s.solicitud_trabajadores.find((t) => t.trabajador_id === trabajadorId);
  let relacion: "ASIGNADO" | "INVITADO" | "BOLSA" | null = null;
  if (s.trabajador_id === trabajadorId) relacion = "ASIGNADO";
  else if (fila?.estado === "PENDIENTE" && fila.origen === "INVITACION") relacion = "INVITADO";
  else if (s.estado === "PENDIENTE" && s.modo_eleccion === "AUTOMATICA" && s.trabajador_id === null && (!fila || fila.estado === "CERRADA")) relacion = "BOLSA";
  if (!relacion) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  const nombres = await nombresDeClientes([s.cliente_id]);
  return vistaTrabajador(s, trabajadorId, relacion, nombres.get(s.cliente_id) ?? "", ahora);
}

/**
 * GET /api/trabajador/solicitudes/disponibles — sus invitaciones pendientes y la bolsa en la que es
 * elegible (ACTIVO + VERIFICADO, especialidades, sin traslape), con hora programada futura.
 */
export async function disponiblesParaTrabajador(trabajadorId: number) {
  const ahora = relojDominio.ahora();
  const t = await prisma.trabajadores.findUnique({ where: { id: trabajadorId }, select: { estado: true, estado_verificacion: true } });
  const verificado = t?.estado === "ACTIVO" && t.estado_verificacion === "VERIFICADO";
  if (!verificado) return { verificado: false, solicitudes: [] };
  const filas = await prisma.solicitud_trabajadores.findMany({ where: { trabajador_id: trabajadorId }, select: { solicitud_id: true, estado: true, origen: true } });
  const invitadas = filas.filter((f) => f.estado === "PENDIENTE" && f.origen === "INVITACION").map((f) => f.solicitud_id);
  const vetadas = filas.filter((f) => f.estado === "RECHAZADA" || f.estado === "CANCELADA" || f.estado === "ACEPTADA").map((f) => f.solicitud_id);
  const candidatas = await prisma.solicitudes.findMany({
    where: {
      estado: "PENDIENTE",
      trabajador_id: null,
      fecha_hora_programada: { gt: ahora },
      OR: [{ id: { in: invitadas } }, { modo_eleccion: "AUTOMATICA", id: { notIn: vetadas } }],
    },
    include: { ...INCLUIR_COMPLETA, solicitud_especialidades: { select: { especialidad_id: true } } },
    orderBy: { fecha_hora_programada: "asc" },
    take: 100,
  });
  const propias = new Set((await prisma.trabajador_especialidades.findMany({ where: { trabajador_id: trabajadorId }, select: { especialidad_id: true } })).map((e) => e.especialidad_id));
  const margen = await parametro("MARGEN_TRASLADO_MIN");
  const agenda = await agendaOcupada(prisma, trabajadorId);
  const nombres = await nombresDeClientes(candidatas.map((c) => c.cliente_id));
  const visibles = candidatas.filter((c) => {
    if (!c.solicitud_especialidades.every((e) => propias.has(e.especialidad_id))) return false;
    return !agenda.some((a) => seTraslapan(intervaloDe(c), intervaloDe(a), margen));
  });
  return {
    verificado: true,
    solicitudes: visibles.map((c) => vistaTrabajador(c, trabajadorId, invitadas.includes(c.id) ? "INVITADO" : "BOLSA", nombres.get(c.cliente_id) ?? "", ahora)),
  };
}

/** Datos del ciclo para el historial del trabajador (asignadas e invitaciones vigentes). */
export async function cicloParaTrabajador(trabajadorId: number, ids: number[]) {
  const ahora = relojDominio.ahora();
  const filas = await prisma.solicitudes.findMany({ where: { id: { in: ids } }, include: INCLUIR_COMPLETA });
  const nombres = await nombresDeClientes(filas.map((f) => f.cliente_id));
  const mapa = new Map<number, ReturnType<typeof vistaTrabajador>>();
  for (const s of filas) {
    const fila = s.solicitud_trabajadores.find((t) => t.trabajador_id === trabajadorId);
    const relacion = s.trabajador_id === trabajadorId ? "ASIGNADO" : fila?.estado === "PENDIENTE" ? "INVITADO" : null;
    if (relacion) mapa.set(s.id, vistaTrabajador(s, trabajadorId, relacion, nombres.get(s.cliente_id) ?? "", ahora));
  }
  return mapa;
}

/** Datos del ciclo para el historial del cliente. */
export async function cicloParaCliente(clienteId: number, ids: number[]) {
  const mapa = new Map<number, Awaited<ReturnType<typeof detalleParaCliente>>>();
  for (const id of ids) mapa.set(id, await detalleParaCliente(clienteId, id));
  return mapa;
}

/** URL temporal de una foto de «terminado»: la ven el cliente dueño y el trabajador asignado. */
export async function urlFotoTerminado(parte: { rol: "CLIENTE" | "TRABAJADOR"; id: number }, solicitudId: number, evidenciaId: number) {
  const s = await prisma.solicitudes.findUnique({ where: { id: solicitudId }, select: { cliente_id: true, trabajador_id: true } });
  const esParte = s && (parte.rol === "CLIENTE" ? s.cliente_id === parte.id : s.trabajador_id === parte.id);
  if (!esParte) throw new AppError(404, "No existe esa solicitud", "SOLICITUD_NO_ENCONTRADA");
  return urlDeFotoDeSolicitud(solicitudId, evidenciaId, { soloTerminado: true });
}

export async function urlDeFotoDeSolicitud(solicitudId: number, evidenciaId: number, opciones: { soloTerminado: boolean }) {
  const e = await prisma.evidencias_solicitud.findFirst({
    where: { id: evidenciaId, solicitud_id: solicitudId, eliminada_en: null, ...(opciones.soloTerminado ? { reporte_id: null, aportada_por: "TRABAJADOR" as const } : {}) },
    select: { archivo_url: true, tipo_mime: true },
  });
  if (!e || !e.tipo_mime) throw new AppError(404, "No existe esa fotografía", "EVIDENCIA_NO_ENCONTRADA");
  const segundos = segundosUrlTemporal("otros");
  const url = await almacenamiento().urlTemporal(e.archivo_url, { mime: e.tipo_mime as "image/jpeg", segundos });
  return { url, expiraEnSegundos: segundos };
}

export { ESTADOS_ABIERTOS, evaluarCancelacion, intervaloDe };
