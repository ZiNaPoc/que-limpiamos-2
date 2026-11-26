import { Prisma } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { AppError } from "../shared/errors/AppError";
import type { Cuerpo } from "../shared/validation/campos";
import { relojDominio } from "./reloj";
import { reputacionesDeTrabajadores } from "./resenas";
import { alertasDe } from "./supervision";

/**
 * Módulos del panel con datos REALES (doc 27):
 *  - Resumen para Inicio (cualquier admin: D24 "ve el dashboard"). Solo conteos.
 *  - Clientes y trabajadores: listas de solo lectura (con SUPERVISAR_SOLICITUDES o el propietario; lo
 *    comprueba la ruta). La revisión de INE y documentos es de la fase de documentos (no aquí).
 *  - Catálogo (D24: el admin administra el catálogo): servicios, extras y áreas. Los cambios no
 *    afectan a solicitudes ya creadas (cada una guarda su copia de nombres y precios).
 */

const ABIERTOS = ["PENDIENTE", "CONFIRMADO", "EN_PROCESO"] as const;

export async function resumen() {
  const ahora = relojDominio.ahora();
  const [porEstado, clientes, clientesVerificados, trabajadores, trabajadoresDisponibles, reportesAbiertos, resenas, abiertas] = await Promise.all([
    prisma.solicitudes.groupBy({ by: ["estado"], _count: { _all: true } }),
    prisma.usuarios.count({ where: { rol: "CLIENTE" } }),
    prisma.usuarios.count({ where: { rol: "CLIENTE", estado_verificacion: "VERIFICADO" } }),
    prisma.trabajadores.count(),
    prisma.trabajadores.count({ where: { estado: "ACTIVO", estado_verificacion: "VERIFICADO" } }),
    prisma.solicitud_reportes.count({ where: { estado: { not: "RESUELTO" }, eliminado_en: null } }),
    prisma.resenas.count({ where: { eliminada_en: null } }),
    prisma.solicitudes.findMany({
      where: { estado: { in: [...ABIERTOS] } },
      select: { estado: true, fecha_hora_programada: true, fecha_hora_fin_estimada: true, trabajador_marco_realizado_en: true, _count: { select: { solicitud_reportes: { where: { estado: { not: "RESUELTO" }, eliminado_en: null } } } } },
    }),
  ]);
  const estados: Record<string, number> = { PENDIENTE: 0, CONFIRMADO: 0, EN_PROCESO: 0, REALIZADO: 0, CANCELADO: 0, RECHAZADO: 0 };
  for (const g of porEstado) estados[g.estado] = g._count._all;
  const alertas: Record<string, number> = { REPORTE_ACTIVO: 0, SIN_INICIAR: 0, ESPERANDO_CONFIRMACION: 0, POR_VENCER: 0 };
  let requierenAtencion = 0;
  for (const s of abiertas) {
    const a = alertasDe(s, s._count.solicitud_reportes, ahora);
    if (a.length) requierenAtencion++;
    for (const x of a) alertas[x] = (alertas[x] ?? 0) + 1;
  }
  return {
    actualizadoEn: ahora.toISOString(),
    solicitudes: { porEstado: estados, total: Object.values(estados).reduce((a, b) => a + b, 0), requierenAtencion, alertas },
    clientes: { total: clientes, verificados: clientesVerificados },
    trabajadores: { total: trabajadores, disponibles: trabajadoresDisponibles },
    reportesAbiertos,
    resenas,
  };
}

function busqueda(q: unknown): string | undefined {
  if (typeof q !== "string" || !q.trim()) return undefined;
  if (q.length > 100) throw new AppError(400, "La búsqueda admite como máximo 100 caracteres", "FILTRO_INVALIDO");
  return q.trim();
}

export async function listarClientes(query: Record<string, unknown>) {
  const q = busqueda(query.q);
  const verificacion = typeof query.verificacion === "string" && ["PENDIENTE", "VERIFICADO", "RECHAZADO"].includes(query.verificacion) ? (query.verificacion as "PENDIENTE") : undefined;
  const filas = await prisma.usuarios.findMany({
    where: {
      rol: "CLIENTE",
      ...(verificacion ? { estado_verificacion: verificacion } : {}),
      ...(q ? { OR: [{ nombre_completo: { contains: q } }, { correo: { contains: q } }, { telefono: { contains: q } }] } : {}),
    },
    orderBy: { id: "desc" },
    take: 200,
    select: { id: true, nombre_completo: true, correo: true, telefono: true, estado_cuenta: true, estado_verificacion: true, created_at: true },
  });
  const ids = filas.map((f) => f.id);
  const [porCliente, inmuebles] = await Promise.all([
    prisma.solicitudes.groupBy({ by: ["cliente_id", "estado"], where: { cliente_id: { in: ids } }, _count: { _all: true } }),
    prisma.inmuebles.groupBy({ by: ["usuario_id"], where: { usuario_id: { in: ids }, archivado_en: null }, _count: { _all: true } }),
  ]);
  return {
    clientes: filas.map((c) => {
      const propias = porCliente.filter((g) => g.cliente_id === c.id);
      return {
        id: c.id,
        nombre: c.nombre_completo,
        correo: c.correo,
        telefono: c.telefono,
        estadoCuenta: c.estado_cuenta,
        verificacion: c.estado_verificacion ?? "PENDIENTE",
        registradoEn: c.created_at.toISOString(),
        solicitudes: {
          total: propias.reduce((a, g) => a + g._count._all, 0),
          activas: propias.filter((g) => (ABIERTOS as readonly string[]).includes(g.estado)).reduce((a, g) => a + g._count._all, 0),
          realizadas: propias.filter((g) => g.estado === "REALIZADO").reduce((a, g) => a + g._count._all, 0),
        },
        inmueblesGuardados: inmuebles.find((i) => i.usuario_id === c.id)?._count._all ?? 0,
      };
    }),
  };
}

export async function listarTrabajadores(query: Record<string, unknown>) {
  const q = busqueda(query.q);
  const filas = await prisma.trabajadores.findMany({
    where: q ? { OR: [{ nombre_completo: { contains: q } }, { correo: { contains: q } }, { telefono: { contains: q } }] } : {},
    orderBy: { id: "desc" },
    take: 200,
    select: { id: true, nombre_completo: true, correo: true, telefono: true, direccion: true, estado: true, estado_verificacion: true, created_at: true },
  });
  const ids = filas.map((f) => f.id);
  const [especialidades, porTrabajador, reputaciones] = await Promise.all([
    prisma.trabajador_especialidades.findMany({ where: { trabajador_id: { in: ids } }, include: { especialidades: { select: { nombre: true } } } }),
    prisma.solicitudes.groupBy({ by: ["trabajador_id", "estado"], where: { trabajador_id: { in: ids } }, _count: { _all: true } }),
    reputacionesDeTrabajadores(ids),
  ]);
  return {
    trabajadores: filas.map((t) => {
      const propias = porTrabajador.filter((g) => g.trabajador_id === t.id);
      return {
        id: t.id,
        nombre: t.nombre_completo,
        correo: t.correo,
        telefono: t.telefono,
        direccion: t.direccion,
        estado: t.estado,
        verificacion: t.estado_verificacion,
        disponibleParaSolicitudes: t.estado === "ACTIVO" && t.estado_verificacion === "VERIFICADO",
        registradoEn: t.created_at.toISOString(),
        especialidades: especialidades.filter((e) => e.trabajador_id === t.id).map((e) => e.especialidades.nombre).sort(),
        servicios: {
          activos: propias.filter((g) => g.estado === "CONFIRMADO" || g.estado === "EN_PROCESO").reduce((a, g) => a + g._count._all, 0),
          realizados: propias.filter((g) => g.estado === "REALIZADO").reduce((a, g) => a + g._count._all, 0),
        },
        reputacion: reputaciones[t.id] ?? { promedio: null, cantidad: 0 },
      };
    }),
  };
}

// ── Catálogo ──

export async function catalogoAdmin() {
  const [servicios, extras, areas, especialidades] = await Promise.all([
    prisma.servicios.findMany({ orderBy: { id: "asc" }, include: { servicio_especialidades: { select: { especialidad_id: true } }, _count: { select: { solicitudes: true } } } }),
    prisma.servicios_extra.findMany({ orderBy: { id: "asc" } }),
    prisma.areas_limpieza.findMany({ orderBy: [{ orden: "asc" }, { id: "asc" }] }),
    prisma.especialidades.findMany({ orderBy: { nombre: "asc" } }),
  ]);
  return {
    servicios: servicios.map((s) => ({
      id: s.id,
      nombre: s.nombre,
      descripcion: s.descripcion,
      precioBase: Number(s.precio_base),
      duracionMin: s.duracion_estimada_min,
      estado: s.estado,
      especialidadIds: s.servicio_especialidades.map((e) => e.especialidad_id),
      solicitudes: s._count.solicitudes,
    })),
    extras: extras.map((e) => ({ id: e.id, nombre: e.nombre, descripcion: e.descripcion, precio: Number(e.precio), duracionMin: e.duracion_estimada_min, estado: e.estado })),
    areas: areas.map((a) => ({ id: a.id, nombre: a.nombre, orden: a.orden, estado: a.estado })),
    especialidades: especialidades.map((e) => ({ id: e.id, nombre: e.nombre, estado: e.estado })),
  };
}

const invalido = (m: string) => new AppError(400, m, "DATOS_INVALIDOS");

function texto(v: unknown, etiqueta: string, min: number, max: number, opcional = false): string | null {
  if ((v === undefined || v === null || v === "") && opcional) return null;
  if (typeof v !== "string") throw invalido(`${etiqueta} es obligatorio`);
  const t = v.trim().replace(/\s+/g, " ");
  if ([...t].length < min || [...t].length > max) throw invalido(`${etiqueta} debe tener entre ${min} y ${max} caracteres`);
  return t;
}

function numero(v: unknown, etiqueta: string, min: number, max: number, entero = false): number {
  const n = typeof v === "string" && v.trim() !== "" ? Number(v) : v;
  if (typeof n !== "number" || !Number.isFinite(n) || n < min || n > max || (entero && !Number.isInteger(n))) throw invalido(`${etiqueta} debe ser un número de ${min} a ${max}`);
  return n;
}

function estado(v: unknown): "ACTIVO" | "INACTIVO" {
  if (v !== "ACTIVO" && v !== "INACTIVO") throw invalido("El estado debe ser ACTIVO o INACTIVO");
  return v;
}

const dinero = (n: number) => new Prisma.Decimal(n.toFixed(2));

async function conNombreUnico<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") throw new AppError(409, "Ya existe uno con ese nombre", "NOMBRE_DUPLICADO");
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2025") throw new AppError(404, "No existe ese elemento del catálogo", "NO_ENCONTRADO");
    throw e;
  }
}

async function especialidadesValidas(v: unknown): Promise<number[]> {
  if (!Array.isArray(v) || v.length === 0) throw invalido("Elige al menos una especialidad");
  const ids = [...new Set(v.map(Number))];
  if (!ids.every((i) => Number.isSafeInteger(i) && i > 0)) throw invalido("Especialidades no válidas");
  if ((await prisma.especialidades.count({ where: { id: { in: ids } } })) !== ids.length) throw new AppError(404, "Alguna especialidad no existe", "ESPECIALIDAD_NO_ENCONTRADA");
  return ids;
}

export async function crearServicio(c: Cuerpo) {
  const datos = {
    nombre: texto(c.nombre, "El nombre", 2, 100)!,
    descripcion: texto(c.descripcion, "La descripción", 5, 1000)!,
    precio_base: dinero(numero(c.precioBase, "El precio base", 1, 100_000)),
    duracion_estimada_min: numero(c.duracionMin, "La duración (min)", 30, 1440, true),
  };
  const esp = await especialidadesValidas(c.especialidadIds);
  return conNombreUnico(() =>
    prisma.$transaction(async (tx) => {
      const s = await tx.servicios.create({ data: { ...datos, estado: "ACTIVO" } });
      await tx.servicio_especialidades.createMany({ data: esp.map((e) => ({ servicio_id: s.id, especialidad_id: e })) });
      await tx.servicio_calculo.create({ data: { servicio_id: s.id } });
      return { id: s.id };
    }),
  );
}

export async function editarServicio(id: number, c: Cuerpo) {
  const data: Prisma.serviciosUpdateInput = { updated_at: relojDominio.ahora() };
  if (c.nombre !== undefined) data.nombre = texto(c.nombre, "El nombre", 2, 100)!;
  if (c.descripcion !== undefined) data.descripcion = texto(c.descripcion, "La descripción", 5, 1000)!;
  if (c.precioBase !== undefined) data.precio_base = dinero(numero(c.precioBase, "El precio base", 1, 100_000));
  if (c.duracionMin !== undefined) data.duracion_estimada_min = numero(c.duracionMin, "La duración (min)", 30, 1440, true);
  if (c.estado !== undefined) data.estado = estado(c.estado);
  const esp = c.especialidadIds !== undefined ? await especialidadesValidas(c.especialidadIds) : null;
  return conNombreUnico(() =>
    prisma.$transaction(async (tx) => {
      await tx.servicios.update({ where: { id }, data });
      if (esp) {
        await tx.servicio_especialidades.deleteMany({ where: { servicio_id: id } });
        await tx.servicio_especialidades.createMany({ data: esp.map((e) => ({ servicio_id: id, especialidad_id: e })) });
      }
      return { id };
    }),
  );
}

export async function crearExtra(c: Cuerpo) {
  const data = {
    nombre: texto(c.nombre, "El nombre", 2, 100)!,
    descripcion: texto(c.descripcion, "La descripción", 0, 255, true),
    precio: dinero(numero(c.precio, "El precio", 0, 100_000)),
    duracion_estimada_min: numero(c.duracionMin ?? 0, "La duración (min)", 0, 600, true),
    estado: "ACTIVO" as const,
  };
  return conNombreUnico(async () => ({ id: (await prisma.servicios_extra.create({ data })).id }));
}

export async function editarExtra(id: number, c: Cuerpo) {
  const data: Prisma.servicios_extraUpdateInput = { updated_at: relojDominio.ahora() };
  if (c.nombre !== undefined) data.nombre = texto(c.nombre, "El nombre", 2, 100)!;
  if (c.descripcion !== undefined) data.descripcion = texto(c.descripcion, "La descripción", 0, 255, true);
  if (c.precio !== undefined) data.precio = dinero(numero(c.precio, "El precio", 0, 100_000));
  if (c.duracionMin !== undefined) data.duracion_estimada_min = numero(c.duracionMin, "La duración (min)", 0, 600, true);
  if (c.estado !== undefined) data.estado = estado(c.estado);
  return conNombreUnico(async () => ({ id: (await prisma.servicios_extra.update({ where: { id }, data })).id }));
}

export async function crearArea(c: Cuerpo) {
  const nombre = texto(c.nombre, "El nombre", 2, 60)!;
  const orden = await prisma.areas_limpieza.count();
  return conNombreUnico(async () => ({ id: (await prisma.areas_limpieza.create({ data: { nombre, orden: Math.min(orden + 1, 255), estado: "ACTIVO" } })).id }));
}

export async function editarArea(id: number, c: Cuerpo) {
  const data: Prisma.areas_limpiezaUpdateInput = {};
  if (c.nombre !== undefined) data.nombre = texto(c.nombre, "El nombre", 2, 60)!;
  if (c.estado !== undefined) data.estado = estado(c.estado);
  return conNombreUnico(async () => ({ id: (await prisma.areas_limpieza.update({ where: { id }, data })).id }));
}
