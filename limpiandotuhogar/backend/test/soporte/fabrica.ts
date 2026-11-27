import { ORIGEN_PANEL } from "./entorno";

import type { solicitudes_estado } from "../../generated/prisma/client";
import { prisma } from "../../src/config/prisma";
import { asignacionInicialPropietario, otorgarPermiso } from "../../src/dominio/permisos";
import { emitirTokenAdmin, NOMBRE_COOKIE_ADMIN } from "../../src/modules/admin/auth/token";
import { emitirTokenCliente } from "../../src/modules/cliente/auth/token";
import { emitirTokenTrabajador } from "../../src/modules/trabajador/auth/token";
import { hashPassword } from "../../src/shared/auth/password";
import { jpegConMetadatos } from "./imagenes";

/**
 * Datos de PRUEBA para la Fase 3a, creados en la BD LOCAL de pruebas. Nada de esto es una cuenta
 * real: son usuarios inventados que se borran al terminar cada archivo de prueba.
 */

let contador = 0;
let hash: string | undefined;
async function hashDePrueba() {
  hash ??= await hashPassword("contrasena-de-prueba-123");
  return hash;
}
const sufijo = () => `${++contador}-${process.pid}`;
const telefono = () => `9${String(Date.now() % 1e5).padStart(5, "0")}${String(contador % 1e4).padStart(4, "0")}`;

export type Persona = { id: number; nombre: string; correo: string };
export type Cliente = Persona & { token: string };
export type Trabajador = Persona & { token: string };
export type Admin = Persona & { cookie: string };

export async function crearCliente(nombre = `Cliente Prueba ${contador + 1}`): Promise<Cliente> {
  const s = sufijo();
  const u = await prisma.usuarios.create({
    data: { nombre_completo: nombre, correo: `cliente.${s}@pruebas.test`, telefono: telefono(), password_hash: await hashDePrueba() },
  });
  return { id: u.id, nombre: u.nombre_completo, correo: u.correo, token: emitirTokenCliente(u) };
}

export async function crearTrabajador(nombre = `Trabajador Prueba ${contador + 1}`): Promise<Trabajador> {
  const s = sufijo();
  const t = await prisma.trabajadores.create({
    data: { nombre_completo: nombre, correo: `trabajador.${s}@pruebas.test`, telefono: telefono(), direccion: "Calle de prueba 1", password_hash: await hashDePrueba() },
  });
  return { id: t.id, nombre: t.nombre_completo, correo: t.correo, token: emitirTokenTrabajador({ id: t.id, password_hash: t.password_hash! }) };
}

export async function crearAdmin(nombre = `Admin Prueba ${contador + 1}`): Promise<Admin> {
  const s = sufijo();
  const u = await prisma.usuarios.create({
    data: { rol: "ADMIN", nombre_completo: nombre, correo: `admin.${s}@pruebas.test`, password_hash: await hashDePrueba() },
  });
  return { id: u.id, nombre: u.nombre_completo, correo: u.correo, cookie: `${NOMBRE_COOKIE_ADMIN}=${emitirTokenAdmin(u)}` };
}

/** Propietario de PRUEBA (asignación inicial auditada, igual que la real) + un moderador. */
export async function crearPropietarioYModerador() {
  const propietario = await crearAdmin("Propietaria Prueba");
  await asignacionInicialPropietario(propietario.correo, "Propietario de PRUEBA para las pruebas automáticas");
  const moderador = await crearAdmin("Moderador Prueba");
  await otorgarPermiso(propietario.id, { usuarioId: moderador.id, permiso: "MODERAR_CONTENIDO", motivo: "Moderador de PRUEBA" });
  return { propietario, moderador };
}

let servicioId: number | undefined;
async function servicioDePrueba() {
  if (servicioId) return servicioId;
  const existente = await prisma.servicios.findFirst({ where: { nombre: "Limpieza de prueba" } });
  servicioId = existente?.id ?? (await prisma.servicios.create({ data: { nombre: "Limpieza de prueba", descripcion: "Solo pruebas", precio_base: 500 } })).id;
  return servicioId;
}

export async function crearSolicitud(o: {
  clienteId: number;
  trabajadorId?: number | null;
  estado?: solicitudes_estado;
  programada?: Date;
  realizadoEn?: Date | null;
  reportePagoHasta?: Date | null;
}) {
  const s = await prisma.solicitudes.create({
    data: {
      cliente_id: o.clienteId,
      trabajador_id: o.trabajadorId ?? null,
      servicio_id: await servicioDePrueba(),
      servicio_nombre_aplicado: "Limpieza de prueba",
      fecha_hora_programada: o.programada ?? new Date(Date.now() - 3 * 3600_000),
      direccion_servicio: "Calle de prueba 1",
      precio_estimado: 500,
      estado: o.estado ?? "PENDIENTE",
      realizado_en: o.realizadoEn ?? null,
      reporte_pago_hasta: o.reportePagoHasta ?? null,
    },
  });
  return s.id;
}

/** JPEG VÁLIDO de exactamente `bytes` bytes (rellena los datos de imagen, que se copian tal cual). */
export function jpegDeTamano(bytes: number): Buffer {
  const base = jpegConMetadatos({ sinExif: true });
  const fin = base.subarray(base.length - 2); // FF D9
  const cuerpo = base.subarray(0, base.length - 2);
  const relleno = bytes - base.length;
  if (relleno < 0) throw new Error("tamaño demasiado chico");
  return Buffer.concat([cuerpo, Buffer.alloc(relleno, 0x12), fin]);
}

export type ArchivoDePrueba = { nombre: string; contenido: Buffer; tipo: string };

/** POST multipart/form-data (fotos de reportes). */
export async function pedirMultipart(base: string, ruta: string, o: { token: string; campos?: Record<string, string>; archivos?: ArchivoDePrueba[]; campoArchivos?: string }) {
  const form = new FormData();
  for (const [k, v] of Object.entries(o.campos ?? {})) form.append(k, v);
  for (const a of o.archivos ?? []) form.append(o.campoArchivos ?? "fotos", new Blob([new Uint8Array(a.contenido)], { type: a.tipo }), a.nombre);
  const r = await fetch(base + ruta, { method: "POST", headers: { authorization: `Bearer ${o.token}` }, body: form });
  const texto = await r.text();
  let cuerpo: any = null;
  try {
    cuerpo = texto ? JSON.parse(texto) : null;
  } catch {
    cuerpo = texto;
  }
  return { status: r.status, cuerpo, texto };
}

export { ORIGEN_PANEL };
