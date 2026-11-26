// Primero el entorno: apunta la app a la BD LOCAL de pruebas antes de cargar nada más.
import { ORIGEN_PANEL } from "./soporte/entorno";

import assert from "node:assert/strict";
import { rmSync } from "node:fs";
import { after, before, describe, it } from "node:test";

import app from "../src/app";
import { prisma } from "../src/config/prisma";
import { otorgarPermiso } from "../src/dominio/permisos";
import { relojDominio } from "../src/dominio/reloj";
import { ejecutarCiclo } from "../src/dominio/tarea-ciclo";
import { type FotoProduccion, limpiarBdDePruebas, prepararBdDePruebas } from "./soporte/bd";
import { type Admin, type Cliente, crearAdmin, crearCliente, crearPropietarioYModerador, crearTrabajador, pedirMultipart, type Trabajador } from "./soporte/fabrica";
import { crearPeticiones, iniciarServidor } from "./soporte/http";
import { jpegConMetadatos, PDF_MINIMO } from "./soporte/imagenes";

/**
 * Ciclo de las solicitudes sin dinero (doc 25 v2): cotizar, «Mis inmuebles», crear (invitación o
 * bolsa), rechazar, bolsa, aceptar (con concurrencia), cancelar, iniciar (ventana), terminar con
 * fotos, confirmar, D54, vencimiento, reportes que bloquean, resolución inmutable, supervisión y
 * permisos. Todo en la BD LOCAL de pruebas, con el reloj del dominio controlado.
 */

const AHORA = new Date("2026-12-10T15:00:00.000Z");
const MIN = 60_000;
const HORA = 60 * MIN;
const relojOriginal = relojDominio.ahora;
let reloj = AHORA.getTime();
const fijarReloj = (ms: number) => {
  reloj = ms;
};

let foto: FotoProduccion | undefined;
let servidor: Awaited<ReturnType<typeof iniciarServidor>> | undefined;
let pedir: ReturnType<typeof crearPeticiones>;
let ana: Cliente; // verificada
let beto: Cliente; // INE pendiente
let rosa: Trabajador; // verificada, todas las especialidades
let ivan: Trabajador; // verificado, todas las especialidades
let lalo: Trabajador; // verificado, SIN la especialidad del extra
let propietario: Admin;
let moderador: Admin;
let supervisor: Admin; // solo SUPERVISAR_SOLICITUDES
let incA: Admin; // SUPERVISAR + INCIDENCIAS
let incB: Admin; // SUPERVISAR + INCIDENCIAS
let sinPermisos: Admin;
const ids: Record<string, number> = {};

const cli = (c: Cliente, metodo: string, ruta: string, cuerpo?: unknown) => pedir(metodo, `/api/cliente${ruta}`, { token: c.token, cuerpo });
const tra = (t: Trabajador, metodo: string, ruta: string, cuerpo?: unknown) => pedir(metodo, `/api/trabajador${ruta}`, { token: t.token, cuerpo });
const adm = (a: Admin, metodo: string, ruta: string, cuerpo?: unknown) => pedir(metodo, `/api/admin${ruta}`, { cookie: a.cookie, origen: ORIGEN_PANEL, cuerpo });
const jpeg = (nombre = "terminado.jpg") => ({ nombre, contenido: jpegConMetadatos(), tipo: "image/jpeg" });
const inmuebleNuevo = (direccion = "Av. Tulum 100, Cancún") => ({ tipo: "CASA", direccion, habitaciones: 2, banos: 1, mediosBanos: 1, pisos: 2 });
const pedido = (o: Record<string, unknown> = {}) => ({
  servicioId: ids.servicio,
  fechaProgramada: new Date(AHORA.getTime() + 48 * HORA).toISOString(),
  extraIds: [ids.extra],
  areaIds: [ids.cocina, ids.sala],
  notas: "Hay un perro amistoso",
  inmueble: inmuebleNuevo(),
  ...o,
});
const crear = async (o: Record<string, unknown> = {}, quien: Cliente = ana) => {
  const r = await cli(quien, "POST", "/solicitudes", pedido(o));
  assert.equal(r.status, 201, r.texto);
  return r.cuerpo.solicitud.id as number;
};

before(async () => {
  foto = await prepararBdDePruebas();
  relojDominio.ahora = () => new Date(reloj);
  ana = await crearCliente("Ana Ciclo");
  beto = await crearCliente("Beto Sin INE");
  await prisma.usuarios.update({ where: { id: ana.id }, data: { estado_verificacion: "VERIFICADO" } });
  rosa = await crearTrabajador("Rosa Ciclo");
  ivan = await crearTrabajador("Ivan Ciclo");
  lalo = await crearTrabajador("Lalo Sin Vidrios");
  await prisma.trabajadores.updateMany({ where: { id: { in: [rosa.id, ivan.id, lalo.id] } }, data: { estado: "ACTIVO", estado_verificacion: "VERIFICADO" } });

  const general = await prisma.especialidades.create({ data: { nombre: "General (ciclo)" } });
  const vidrios = await prisma.especialidades.create({ data: { nombre: "Vidrios (ciclo)" } });
  ids.servicio = (await prisma.servicios.create({ data: { nombre: "Limpieza regular (ciclo)", descripcion: "x", precio_base: 400, duracion_estimada_min: 180 } })).id;
  await prisma.servicio_especialidades.create({ data: { servicio_id: ids.servicio, especialidad_id: general.id } });
  ids.extra = (await prisma.servicios_extra.create({ data: { nombre: "Ventanas (ciclo)", precio: 150, duracion_estimada_min: 60 } })).id;
  await prisma.extra_especialidades.create({ data: { extra_id: ids.extra, especialidad_id: vidrios.id } });
  ids.inactivo = (await prisma.servicios_extra.create({ data: { nombre: "Inactivo (ciclo)", precio: 99, estado: "INACTIVO" } })).id;
  ids.cocina = (await prisma.areas_limpieza.create({ data: { nombre: "Cocina (ciclo)", orden: 1 } })).id;
  ids.sala = (await prisma.areas_limpieza.create({ data: { nombre: "Sala (ciclo)", orden: 2 } })).id;
  await prisma.trabajador_especialidades.createMany({
    data: [
      { trabajador_id: rosa.id, especialidad_id: general.id },
      { trabajador_id: rosa.id, especialidad_id: vidrios.id },
      { trabajador_id: ivan.id, especialidad_id: general.id },
      { trabajador_id: ivan.id, especialidad_id: vidrios.id },
      { trabajador_id: lalo.id, especialidad_id: general.id },
    ],
  });

  ({ propietario, moderador } = await crearPropietarioYModerador());
  supervisor = await crearAdmin("Supervisor Ciclo");
  incA = await crearAdmin("Incidencias A");
  incB = await crearAdmin("Incidencias B");
  sinPermisos = await crearAdmin("Sin Permisos");
  await otorgarPermiso(propietario.id, { usuarioId: supervisor.id, permiso: "SUPERVISAR_SOLICITUDES", motivo: "Supervisión de PRUEBA" });
  for (const a of [incA, incB]) {
    await otorgarPermiso(propietario.id, { usuarioId: a.id, permiso: "SUPERVISAR_SOLICITUDES", motivo: "Supervisión de PRUEBA" });
    await otorgarPermiso(propietario.id, { usuarioId: a.id, permiso: "GESTIONAR_INCIDENCIAS_FINANZAS", motivo: "Incidencias de PRUEBA" });
  }
  servidor = await iniciarServidor(app);
  pedir = crearPeticiones(servidor.base);
});

after(async () => {
  relojDominio.ahora = relojOriginal;
  await servidor?.cerrar();
  await prisma.$disconnect().catch(() => undefined);
  rmSync(process.env.ALMACENAMIENTO_LOCAL_DIR as string, { recursive: true, force: true });
  const resultado = await limpiarBdDePruebas(foto);
  assert.deepEqual(resultado.tablasRestantes, [], "BD de pruebas sin vaciar");
});

describe("Catálogo y cotización", () => {
  it("el catálogo trae los servicios, áreas y extras ACTIVOS con sus ids", async () => {
    const r = await cli(ana, "GET", "/catalogo");
    assert.equal(r.status, 200, r.texto);
    assert.ok(r.cuerpo.servicios.some((s: { id: number; precioBase: number }) => s.id === ids.servicio && s.precioBase === 400));
    assert.ok(r.cuerpo.extras.some((e: { id: number }) => e.id === ids.extra));
    assert.ok(!r.cuerpo.extras.some((e: { id: number }) => e.id === ids.inactivo), "sin extras inactivos");
    assert.equal((await pedir("GET", "/api/cliente/catalogo")).status, 401);
  });

  it("precio = base + extras y duración = servicio + extras; no crea nada; se permite con la INE pendiente (D65)", async () => {
    const antes = await prisma.solicitudes.count();
    const r = await cli(beto, "POST", "/cotizaciones", pedido());
    assert.equal(r.status, 200, r.texto);
    assert.deepEqual(r.cuerpo.cotizacion.precio, { base: 400, extras: 150, total: 550, moneda: "MXN" });
    assert.equal(r.cuerpo.cotizacion.duracionMin, 240);
    assert.equal(r.cuerpo.cotizacion.finEstimado, new Date(AHORA.getTime() + 52 * HORA).toISOString());
    assert.deepEqual(r.cuerpo.cotizacion.especialidadesRequeridas, ["General (ciclo)", "Vidrios (ciclo)"]);
    assert.equal(r.cuerpo.cotizacion.metodoPago, "EFECTIVO");
    assert.equal(await prisma.solicitudes.count(), antes, "la cotización no crea solicitudes");
  });

  it("rechaza fechas pasadas o a más de 365 días, extras inactivos y precios del cliente no se aceptan", async () => {
    assert.equal((await cli(ana, "POST", "/cotizaciones", pedido({ fechaProgramada: new Date(AHORA.getTime() - MIN).toISOString() }))).cuerpo.codigo, "FECHA_PASADA");
    assert.equal((await cli(ana, "POST", "/cotizaciones", pedido({ fechaProgramada: new Date(AHORA.getTime() + 366 * 24 * HORA).toISOString() }))).cuerpo.codigo, "FECHA_DEMASIADO_LEJANA");
    assert.equal((await cli(ana, "POST", "/cotizaciones", pedido({ extraIds: [ids.inactivo] }))).status, 404);
    const conPrecio = await cli(ana, "POST", "/cotizaciones", pedido({ total: 1, precio: 1 }));
    assert.equal(conPrecio.cuerpo.cotizacion.precio.total, 550, "el precio siempre lo calcula el servidor (D4)");
    assert.equal((await cli(ana, "POST", "/cotizaciones", pedido({ inmueble: { ...inmuebleNuevo(), pisos: 0 } }))).status, 400);
  });
});

describe("Mis inmuebles", () => {
  it("crear, listar, editar y eliminar (archivar); solo los propios", async () => {
    const c = await cli(ana, "POST", "/inmuebles", { nombre: "Airbnb Centro", ...inmuebleNuevo("Calle 5 Centro") });
    assert.equal(c.status, 201, c.texto);
    ids.airbnb = c.cuerpo.inmueble.id;
    const playa = await cli(ana, "POST", "/inmuebles", { nombre: "Casa Playa", tipo: "DEPARTAMENTO", direccion: "Zona Hotelera km 9", habitaciones: 3, banos: 2, mediosBanos: 0, pisos: 1 });
    assert.equal(playa.status, 201);
    ids.playa = playa.cuerpo.inmueble.id;
    assert.deepEqual((await cli(ana, "GET", "/inmuebles")).cuerpo.inmuebles.map((i: { nombre: string }) => i.nombre), ["Airbnb Centro", "Casa Playa"]);
    assert.equal((await cli(beto, "GET", "/inmuebles")).cuerpo.inmuebles.length, 0, "beto no ve los de ana");
    assert.equal((await cli(beto, "PATCH", `/inmuebles/${ids.airbnb}`, { nombre: "Mío" })).status, 404);
    assert.equal((await cli(ana, "POST", "/inmuebles", { nombre: "", ...inmuebleNuevo() })).status, 400, "el nombre es obligatorio");
    const e = await cli(ana, "PATCH", `/inmuebles/${ids.playa}`, { habitaciones: 4 });
    assert.equal(e.cuerpo.inmueble.habitaciones, 4);
    assert.equal(e.cuerpo.inmueble.nombre, "Casa Playa");
  });

  it("la solicitud guarda una COPIA inmutable: editar o eliminar el inmueble no la cambia", async () => {
    ids.conInmueble = await crear({ inmueble: undefined, inmuebleId: ids.airbnb, fechaProgramada: new Date(AHORA.getTime() + 72 * HORA).toISOString() });
    const antes = await prisma.solicitudes.findUniqueOrThrow({ where: { id: ids.conInmueble } });
    assert.equal(antes.inmueble_alias_aplicado, "Airbnb Centro");
    assert.equal(antes.direccion_servicio, "Calle 5 Centro");
    await cli(ana, "PATCH", `/inmuebles/${ids.airbnb}`, { nombre: "Airbnb renombrado", direccion: "Otra calle 99", habitaciones: 7 });
    const borrar = await cli(ana, "DELETE", `/inmuebles/${ids.airbnb}`);
    assert.equal(borrar.status, 200, borrar.texto);
    const despues = await prisma.solicitudes.findUniqueOrThrow({ where: { id: ids.conInmueble } });
    for (const campo of ["inmueble_alias_aplicado", "direccion_servicio", "habitaciones_aplicado", "banos_aplicado", "medios_banos_aplicado", "pisos_aplicado", "inmueble_tipo_aplicado"] as const) {
      assert.equal(despues[campo], antes[campo], `${campo} no cambia`);
    }
    assert.ok((await prisma.inmuebles.findUniqueOrThrow({ where: { id: ids.airbnb } })).archivado_en, "eliminar = archivar; la fila se conserva");
    assert.equal((await cli(ana, "GET", "/inmuebles")).cuerpo.inmuebles.length, 1);
    assert.equal((await cli(ana, "POST", "/solicitudes", pedido({ inmueble: undefined, inmuebleId: ids.airbnb }))).status, 404, "uno eliminado ya no se puede elegir");
    await cli(ana, "POST", `/solicitudes/${ids.conInmueble}/cancelar`);
  });

  it("un inmueble nuevo en la solicitud no se guarda, salvo que se pida (guardarComo)", async () => {
    const antes = await prisma.inmuebles.count({ where: { usuario_id: ana.id } });
    const sinGuardar = await crear({ fechaProgramada: new Date(AHORA.getTime() + 80 * HORA).toISOString(), inmueble: inmuebleNuevo("Solo esta vez 1") });
    assert.equal((await prisma.solicitudes.findUniqueOrThrow({ where: { id: sinGuardar } })).inmueble_id, null);
    assert.equal(await prisma.inmuebles.count({ where: { usuario_id: ana.id } }), antes);
    const guardada = await crear({ fechaProgramada: new Date(AHORA.getTime() + 81 * HORA).toISOString(), inmueble: { ...inmuebleNuevo("Oficina nueva 2"), guardarComo: "Oficina" } });
    const s = await prisma.solicitudes.findUniqueOrThrow({ where: { id: guardada } });
    assert.ok(s.inmueble_id);
    assert.equal(s.inmueble_alias_aplicado, "Oficina");
    assert.equal(await prisma.inmuebles.count({ where: { usuario_id: ana.id } }), antes + 1);
    for (const id of [sinGuardar, guardada]) await cli(ana, "POST", `/solicitudes/${id}/cancelar`);
  });
});

describe("Crear, invitar, rechazar y bolsa", () => {
  it("sin la INE verificada no se crea (403 IDENTIDAD_NO_VERIFICADA)", async () => {
    const r = await cli(beto, "POST", "/solicitudes", pedido());
    assert.equal(r.status, 403);
    assert.equal(r.cuerpo.codigo, "IDENTIDAD_NO_VERIFICADA");
  });

  it("con colaborador: PENDIENTE MANUAL, snapshot, especialidades del servicio y del extra, invitación y aviso", async () => {
    ids.invitada = await crear({ trabajadorId: rosa.id });
    const s = await prisma.solicitudes.findUniqueOrThrow({ where: { id: ids.invitada }, include: { solicitud_especialidades: true, solicitud_extras: true, solicitud_areas: true, solicitud_trabajadores: true } });
    assert.equal(s.estado, "PENDIENTE");
    assert.equal(s.modo_eleccion, "MANUAL");
    assert.equal(Number(s.precio_estimado), 550);
    assert.equal(s.estado_pago, "PENDIENTE");
    assert.equal(s.duracion_estimada_min, 240);
    assert.equal(s.inmueble_id, null);
    assert.deepEqual(s.solicitud_especialidades.map((e) => e.nombre_aplicado).sort(), ["General (ciclo)", "Vidrios (ciclo)"]);
    assert.equal(s.solicitud_extras[0]!.nombre_aplicado, "Ventanas (ciclo)");
    assert.equal(s.solicitud_areas.length, 2);
    assert.deepEqual(s.solicitud_trabajadores.map((t) => [t.trabajador_id, t.origen, t.estado]), [[rosa.id, "INVITACION", "PENDIENTE"]]);
    assert.equal(await prisma.notificaciones_trabajador.count({ where: { trabajador_id: rosa.id, tipo: "INVITACION_NUEVA", solicitud_id: ids.invitada } }), 1);
    assert.equal((await cli(ana, "POST", "/solicitudes", pedido({ trabajadorId: rosa.id }))).cuerpo.codigo, "SOLICITUD_DUPLICADA");
  });

  it("no se invita a quien no tiene las especialidades (el extra exige «Vidrios»)", async () => {
    const r = await cli(ana, "POST", "/solicitudes", pedido({ trabajadorId: lalo.id, fechaProgramada: new Date(AHORA.getTime() + 90 * HORA).toISOString() }));
    assert.equal(r.status, 409);
    assert.equal(r.cuerpo.codigo, "COLABORADOR_SIN_ESPECIALIDADES");
  });

  it("el invitado la ve en disponibles; los demás no (no está en la bolsa)", async () => {
    const r = await tra(rosa, "GET", "/solicitudes/disponibles");
    const propia = r.cuerpo.solicitudes.find((x: { id: number }) => x.id === ids.invitada);
    assert.equal(propia.relacion, "INVITADO");
    assert.equal(propia.direccion, null, "sin la dirección exacta hasta aceptar");
    assert.equal(propia.acciones.puedeAceptar, true);
    assert.ok(!(await tra(ivan, "GET", "/solicitudes/disponibles")).cuerpo.solicitudes.some((x: { id: number }) => x.id === ids.invitada));
  });

  it("rechazar avisa al cliente; el cliente elige: bolsa, invitar a otro o cancelar", async () => {
    const r = await tra(rosa, "POST", `/solicitudes/${ids.invitada}/rechazar`);
    assert.equal(r.status, 200, r.texto);
    assert.equal(await prisma.notificaciones.count({ where: { usuario_id: ana.id, tipo: "INVITACION_RECHAZADA", solicitud_id: ids.invitada } }), 1);
    const d = (await cli(ana, "GET", `/solicitudes/${ids.invitada}`)).cuerpo.solicitud;
    assert.equal(d.estado, "PENDIENTE");
    assert.equal(d.invitacionRechazada.trabajador, "Rosa Ciclo");
    assert.deepEqual([d.acciones.puedeEnviarABolsa, d.acciones.puedeInvitarOtro, d.acciones.puedeCancelar], [true, true, true]);
    const otraVez = await cli(ana, "POST", `/solicitudes/${ids.invitada}/invitaciones`, { trabajadorId: rosa.id });
    assert.equal(otraVez.cuerpo.codigo, "INVITACION_NO_PERMITIDA", "no se reinvita a quien rechazó");
    assert.equal((await cli(ana, "POST", `/solicitudes/${ids.invitada}/invitaciones`, { trabajadorId: lalo.id })).cuerpo.codigo, "COLABORADOR_SIN_ESPECIALIDADES");
  });

  it("enviar a la bolsa: la ven los elegibles, no quien la rechazó ni quien no tiene las especialidades", async () => {
    const r = await cli(ana, "POST", `/solicitudes/${ids.invitada}/bolsa`);
    assert.equal(r.status, 200, r.texto);
    assert.equal(r.cuerpo.solicitud.modo, "BOLSA");
    assert.ok((await tra(ivan, "GET", "/solicitudes/disponibles")).cuerpo.solicitudes.some((x: { id: number; relacion: string }) => x.id === ids.invitada && x.relacion === "BOLSA"));
    assert.ok(!(await tra(rosa, "GET", "/solicitudes/disponibles")).cuerpo.solicitudes.some((x: { id: number }) => x.id === ids.invitada), "la rechazó: definitivo");
    assert.ok(!(await tra(lalo, "GET", "/solicitudes/disponibles")).cuerpo.solicitudes.some((x: { id: number }) => x.id === ids.invitada));
    assert.equal((await cli(ana, "POST", `/solicitudes/${ids.invitada}/bolsa`)).cuerpo.codigo, "YA_EN_BOLSA");
  });
});

describe("Aceptar (concurrencia y traslapes)", () => {
  it("dos trabajadores aceptan a la vez la misma de la bolsa: solo uno gana, el otro recibe 409", async () => {
    ids.carrera = await crear({ fechaProgramada: new Date(AHORA.getTime() + 30 * HORA).toISOString() });
    const [a, b] = await Promise.all([tra(rosa, "POST", `/solicitudes/${ids.carrera}/aceptar`), tra(ivan, "POST", `/solicitudes/${ids.carrera}/aceptar`)]);
    assert.deepEqual([a.status, b.status].sort(), [200, 409], `${a.texto} | ${b.texto}`);
    const ganador = a.status === 200 ? rosa : ivan;
    const s = await prisma.solicitudes.findUniqueOrThrow({ where: { id: ids.carrera } });
    assert.equal(s.estado, "CONFIRMADO");
    assert.equal(s.trabajador_id, ganador.id);
    assert.equal(await prisma.solicitud_trabajadores.count({ where: { solicitud_id: ids.carrera, estado: "ACEPTADA" } }), 1);
    assert.equal(await prisma.notificaciones.count({ where: { usuario_id: ana.id, tipo: "SERVICIO_CONFIRMADO", solicitud_id: ids.carrera } }), 1);
    ids.ganador = ganador.id;
  });

  it("con traslape (60 min de traslado) no la ve ni puede aceptarla", async () => {
    const ganador = ids.ganador === rosa.id ? rosa : ivan;
    // La carrera es a T+30 h (4 h); otra a T+35 h empieza 1 h después de que termina: se cruza por el traslado.
    ids.cruzada = await crear({ fechaProgramada: new Date(AHORA.getTime() + 34.5 * HORA).toISOString(), inmueble: inmuebleNuevo("Cruzada 1") });
    assert.ok(!(await tra(ganador, "GET", "/solicitudes/disponibles")).cuerpo.solicitudes.some((x: { id: number }) => x.id === ids.cruzada));
    const r = await tra(ganador, "POST", `/solicitudes/${ids.cruzada}/aceptar`);
    assert.equal(r.status, 409);
    assert.equal(r.cuerpo.codigo, "NO_ELEGIBLE_TRASLAPE");
    await cli(ana, "POST", `/solicitudes/${ids.cruzada}/cancelar`);
  });
});

describe("Cancelaciones sin cargo", () => {
  it("el cliente cancela una PENDIENTE: CANCELADO, invitaciones cerradas y aviso al invitado", async () => {
    const id = await crear({ trabajadorId: ivan.id, fechaProgramada: new Date(AHORA.getTime() + 100 * HORA).toISOString(), inmueble: inmuebleNuevo("Cancelar 1") });
    const r = await cli(ana, "POST", `/solicitudes/${id}/cancelar`, { motivo: "Cambié de planes" });
    assert.equal(r.status, 200, r.texto);
    assert.equal(r.cuerpo.solicitud.estado, "CANCELADO");
    assert.equal((await prisma.solicitud_trabajadores.findFirstOrThrow({ where: { solicitud_id: id } })).motivo_cierre, "CLIENTE_CANCELO");
    assert.equal(await prisma.notificaciones_trabajador.count({ where: { trabajador_id: ivan.id, tipo: "SOLICITUD_CANCELADA_POR_CLIENTE", solicitud_id: id } }), 1);
    assert.equal((await cli(ana, "POST", `/solicitudes/${id}/cancelar`)).cuerpo.codigo, "NO_CANCELABLE");
  });

  it("CONFIRMADO con menos de 24 h: 409 CANCELACION_NO_DISPONIBLE (cliente y trabajador); con 24 h o más: sí", async () => {
    const ganador = ids.ganador === rosa.id ? rosa : ivan;
    fijarReloj(AHORA.getTime() + 7 * HORA); // faltan 23 h para la carrera
    assert.equal((await cli(ana, "POST", `/solicitudes/${ids.carrera}/cancelar`)).cuerpo.codigo, "CANCELACION_NO_DISPONIBLE");
    assert.equal((await tra(ganador, "POST", `/solicitudes/${ids.carrera}/cancelar`)).cuerpo.codigo, "CANCELACION_NO_DISPONIBLE");
    fijarReloj(AHORA.getTime());
    // El trabajador cancela con 30 h: vuelve a la bolsa, sin él, y ya no la ve.
    const r = await tra(ganador, "POST", `/solicitudes/${ids.carrera}/cancelar`, { motivo: "Me enfermé" });
    assert.equal(r.status, 200, r.texto);
    const s = await prisma.solicitudes.findUniqueOrThrow({ where: { id: ids.carrera } });
    assert.deepEqual([s.estado, s.trabajador_id, s.modo_eleccion], ["PENDIENTE", null, "AUTOMATICA"]);
    assert.equal((await prisma.solicitud_trabajadores.findFirstOrThrow({ where: { solicitud_id: ids.carrera, trabajador_id: ganador.id } })).estado, "CANCELADA");
    assert.equal(await prisma.notificaciones.count({ where: { usuario_id: ana.id, tipo: "SOLICITUD_DEVUELTA_A_BOLSA", solicitud_id: ids.carrera } }), 1);
    assert.ok(!(await tra(ganador, "GET", "/solicitudes/disponibles")).cuerpo.solicitudes.some((x: { id: number }) => x.id === ids.carrera));
    assert.equal((await tra(ganador, "POST", `/solicitudes/${ids.carrera}/aceptar`)).status, 404);
  });
});

describe("Iniciar, terminar con fotos y confirmar", () => {
  it("iniciar solo de 30 min antes a 30 min después de la hora programada", async () => {
    const otro = ids.ganador === rosa.id ? ivan : rosa;
    assert.equal((await tra(otro, "POST", `/solicitudes/${ids.carrera}/aceptar`)).status, 200);
    ids.asignado = otro.id;
    const programada = AHORA.getTime() + 30 * HORA;
    fijarReloj(programada - 31 * MIN);
    assert.equal((await tra(otro, "POST", `/solicitudes/${ids.carrera}/iniciar`)).cuerpo.codigo, "ANTES_DE_LA_VENTANA");
    fijarReloj(programada + 31 * MIN);
    assert.equal((await tra(otro, "POST", `/solicitudes/${ids.carrera}/iniciar`)).cuerpo.codigo, "DESPUES_DE_LA_VENTANA");
    fijarReloj(programada - 30 * MIN);
    const r = await tra(otro, "POST", `/solicitudes/${ids.carrera}/iniciar`);
    assert.equal(r.status, 200, r.texto);
    assert.equal(r.cuerpo.solicitud.estado, "EN_PROCESO");
    assert.equal(r.cuerpo.solicitud.direccion, "Av. Tulum 100, Cancún", "ya asignado: ve la dirección");
  });

  it("terminar exige de 1 a 5 fotos válidas; solo una vez", async () => {
    const t = ids.asignado === rosa.id ? rosa : ivan;
    const ruta = `/api/trabajador/solicitudes/${ids.carrera}/terminar`;
    assert.equal((await pedirMultipart(servidor!.base, ruta, { token: t.token })).cuerpo.codigo, "FOTOS_REQUERIDAS");
    const pdf = await pedirMultipart(servidor!.base, ruta, { token: t.token, archivos: [{ nombre: "x.pdf", contenido: PDF_MINIMO, tipo: "application/pdf" }] });
    assert.ok(pdf.status >= 400 && pdf.status < 500, pdf.texto);
    const seis = await pedirMultipart(servidor!.base, ruta, { token: t.token, archivos: [1, 2, 3, 4, 5, 6].map((i) => jpeg(`f${i}.jpg`)) });
    assert.equal(seis.cuerpo.codigo, "DEMASIADAS_FOTOS");
    const ajeno = await pedirMultipart(servidor!.base, ruta, { token: lalo.token, archivos: [jpeg()] });
    assert.equal(ajeno.status, 404);
    const ok = await pedirMultipart(servidor!.base, ruta, { token: t.token, archivos: [jpeg("a.jpg"), jpeg("b.jpg")] });
    assert.equal(ok.status, 200, ok.texto);
    assert.equal(ok.cuerpo.solicitud.fotosTerminado.length, 2);
    assert.equal((await pedirMultipart(servidor!.base, ruta, { token: t.token, archivos: [jpeg()] })).cuerpo.codigo, "YA_TERMINADO");
    // El cliente ve las fotos (URL temporal); otro cliente no.
    const d = (await cli(ana, "GET", `/solicitudes/${ids.carrera}`)).cuerpo.solicitud;
    const fotoId = d.fotosTerminado[0].id;
    const url = await cli(ana, "GET", `/solicitudes/${ids.carrera}/evidencias/${fotoId}`);
    assert.equal(url.status, 200, url.texto);
    assert.match(url.cuerpo.url, /\/api\/archivos\/temporal\//);
    assert.equal((await pedir("GET", url.cuerpo.url)).status, 200);
    assert.equal((await cli(beto, "GET", `/solicitudes/${ids.carrera}/evidencias/${fotoId}`)).status, 404);
  });

  it("el cliente confirma: REALIZADO (CLIENTE); sin dinero", async () => {
    const r = await cli(ana, "POST", `/solicitudes/${ids.carrera}/confirmar`);
    assert.equal(r.status, 200, r.texto);
    const s = await prisma.solicitudes.findUniqueOrThrow({ where: { id: ids.carrera } });
    assert.deepEqual([s.estado, s.realizado_via, s.estado_pago, s.pago_registrado_en, s.ganancia_liberada_en], ["REALIZADO", "CLIENTE", "PENDIENTE", null, null]);
    fijarReloj(AHORA.getTime());
  });
});

/** Una solicitud confirmada e iniciada por Ivan a la hora `programada`. */
async function enProceso(programadaMs: number, direccion: string) {
  fijarReloj(AHORA.getTime());
  const id = await crear({ trabajadorId: ivan.id, fechaProgramada: new Date(programadaMs).toISOString(), inmueble: inmuebleNuevo(direccion), extraIds: [] });
  assert.equal((await tra(ivan, "POST", `/solicitudes/${id}/aceptar`)).status, 200);
  fijarReloj(programadaMs);
  assert.equal((await tra(ivan, "POST", `/solicitudes/${id}/iniciar`)).status, 200);
  return id;
}

describe("D54, vencimiento y reportes (tarea periódica)", () => {
  it("con evidencia: en T + 30 min se avisa al cliente y 15 min después queda REALIZADO; repetir no duplica", async () => {
    const p = AHORA.getTime() + 200 * HORA; // 3 h de duración (sin extras)
    const id = await enProceso(p, "Evidencia 1");
    fijarReloj(p + 60 * MIN);
    assert.equal((await pedirMultipart(servidor!.base, `/api/trabajador/solicitudes/${id}/terminar`, { token: ivan.token, archivos: [jpeg()] })).status, 200);
    fijarReloj(p + 3 * HORA + 29 * MIN);
    await ejecutarCiclo();
    assert.equal((await prisma.solicitudes.findUniqueOrThrow({ where: { id } })).aviso_evidencia_en, null, "aún no es T + 30");
    fijarReloj(p + 3 * HORA + 30 * MIN);
    await ejecutarCiclo();
    await ejecutarCiclo();
    assert.equal(await prisma.notificaciones.count({ where: { solicitud_id: id, tipo: "AVISO_CONFIRMACION_CON_EVIDENCIA" } }), 1, "un solo aviso");
    fijarReloj(p + 3 * HORA + 45 * MIN);
    await ejecutarCiclo();
    const s = await prisma.solicitudes.findUniqueOrThrow({ where: { id } });
    assert.deepEqual([s.estado, s.realizado_via, s.estado_pago], ["REALIZADO", "EVIDENCIA_TRABAJADOR", "PENDIENTE"]);
  });

  it("sin marcas: en T + 30 se pide confirmar a ambos y 30 min después se confirma solo (AUTOMATICO)", async () => {
    const p = AHORA.getTime() + 210 * HORA;
    const id = await enProceso(p, "Automatica 1");
    fijarReloj(p + 3 * HORA + 30 * MIN);
    await ejecutarCiclo();
    assert.ok((await prisma.solicitudes.findUniqueOrThrow({ where: { id } })).confirmacion_solicitada_en);
    assert.equal(await prisma.notificaciones.count({ where: { solicitud_id: id, tipo: "CONFIRMAR_SERVICIO_REALIZADO" } }), 1);
    assert.equal(await prisma.notificaciones_trabajador.count({ where: { solicitud_id: id, tipo: "SUBIR_EVIDENCIA_SERVICIO" } }), 1);
    fijarReloj(p + 4 * HORA + 1 * MIN);
    await ejecutarCiclo();
    const s = await prisma.solicitudes.findUniqueOrThrow({ where: { id } });
    assert.deepEqual([s.estado, s.realizado_via], ["REALIZADO", "AUTOMATICO"]);
    assert.equal(await prisma.notificaciones_trabajador.count({ where: { solicitud_id: id, tipo: "SERVICIO_CONFIRMADO_AUTOMATICAMENTE" } }), 1);
  });

  it("un reporte activo bloquea la confirmación automática y la del cliente (D57)", async () => {
    const p = AHORA.getTime() + 220 * HORA;
    ids.bloqueada = await enProceso(p, "Bloqueada 1");
    const rep = await pedirMultipart(servidor!.base, `/api/cliente/solicitudes/${ids.bloqueada}/reportes`, { token: ana.token, campos: { tipo: "NO_SE_PUDO_COMPLETAR", descripcion: "Faltó la cocina" } });
    assert.equal(rep.status, 201, rep.texto);
    ids.reporteBloqueo = rep.cuerpo.reporte.id;
    fijarReloj(p + 6 * HORA);
    await ejecutarCiclo();
    await ejecutarCiclo();
    assert.equal((await prisma.solicitudes.findUniqueOrThrow({ where: { id: ids.bloqueada } })).estado, "EN_PROCESO");
    assert.equal((await cli(ana, "POST", `/solicitudes/${ids.bloqueada}/confirmar`)).cuerpo.codigo, "REPORTE_EN_REVISION");
    assert.equal((await adm(moderador, "POST", `/reportes/${ids.reporteBloqueo}/resolucion`, { resolucion: "x" })).cuerpo.codigo, "RESOLUCION_DE_SERVICIO");
  });

  it("vencer: una PENDIENTE que nadie aceptó se cancela sola, con motivo VENCIDA y aviso; sin cargos; idempotente", async () => {
    fijarReloj(AHORA.getTime());
    const p = AHORA.getTime() + 240 * HORA;
    const id = await crear({ trabajadorId: rosa.id, fechaProgramada: new Date(p).toISOString(), inmueble: inmuebleNuevo("Vencida 1"), extraIds: [] });
    fijarReloj(p);
    await ejecutarCiclo();
    await ejecutarCiclo();
    const s = await prisma.solicitudes.findUniqueOrThrow({ where: { id }, include: { solicitud_trabajadores: true, solicitud_historial: { orderBy: { id: "desc" }, take: 1 } } });
    assert.equal(s.estado, "CANCELADO");
    assert.deepEqual(s.solicitud_trabajadores.map((t) => [t.estado, t.motivo_cierre]), [["CERRADA", "VENCIDA"]]);
    assert.equal(s.solicitud_historial[0]!.actor, "SISTEMA");
    assert.equal(await prisma.notificaciones.count({ where: { solicitud_id: id, tipo: "SERVICIO_CANCELADO_POR_PLATAFORMA" } }), 1);
    assert.equal(s.cargo_cancelacion, null);
  });
});

describe("Supervisión en el panel y permisos", () => {
  it("ver solicitudes: 403 sin permiso; el propietario SIN fila propia (implícito); el supervisor con el permiso", async () => {
    assert.equal((await adm(sinPermisos, "GET", "/solicitudes")).status, 403);
    assert.equal((await adm(moderador, "GET", "/solicitudes")).status, 403, "moderar no da supervisión");
    const mios = await adm(propietario, "GET", "/permisos/mios");
    assert.ok(mios.cuerpo.permisos.includes("SUPERVISAR_SOLICITUDES"));
    assert.deepEqual(mios.cuerpo.implicitos, ["SUPERVISAR_SOLICITUDES"]);
    assert.equal(await prisma.admin_permisos.count({ where: { usuario_id: propietario.id, permiso: "SUPERVISAR_SOLICITUDES" } }), 0, "sin asignárselo");
    assert.equal((await adm(propietario, "GET", "/solicitudes")).status, 200);
    const lista = await adm(supervisor, "GET", "/solicitudes?tamano=100");
    assert.equal(lista.status, 200, lista.texto);
    assert.ok(lista.cuerpo.total >= 5);
    assert.equal((await adm(propietario, "POST", "/permisos", { usuarioId: propietario.id, permiso: "SUPERVISAR_SOLICITUDES", motivo: "x" })).cuerpo.codigo, "AUTO_OTORGAMIENTO");
  });

  it("detalle: invitaciones/bolsa con el estado de cada trabajador, historial y alertas; reportes en resumen sin el permiso de incidencias", async () => {
    const d = (await adm(supervisor, "GET", `/solicitudes/${ids.invitada}`)).cuerpo.solicitud;
    assert.equal(d.modo, "BOLSA");
    assert.deepEqual(d.trabajadores.map((t: { trabajador: { id: number }; estado: string }) => [t.trabajador.id, t.estado]), [[rosa.id, "RECHAZADA"]]);
    assert.ok(d.historial.length >= 2);
    assert.equal(d.historial[0].actorNombre, "Ana Ciclo");
    const b = (await adm(supervisor, "GET", `/solicitudes/${ids.bloqueada}`)).cuerpo.solicitud;
    assert.ok(b.alertas.includes("REPORTE_ACTIVO"));
    assert.equal(b.reportes[0].tipo, "NO_SE_PUDO_COMPLETAR");
    assert.equal(b.reportes[0].descripcion, undefined, "X6: sin el contenido");
    assert.equal(b.puedeResolver, false);
    const conIncidencias = (await adm(incA, "GET", `/solicitudes/${ids.bloqueada}`)).cuerpo.solicitud;
    assert.equal(conIncidencias.reportes[0].descripcion, "Faltó la cocina");
    assert.equal(conIncidencias.puedeResolver, true);
    const atencion = await adm(supervisor, "GET", "/solicitudes?atencion=1&tamano=100");
    assert.ok(atencion.cuerpo.solicitudes.some((s: { id: number }) => s.id === ids.bloqueada));
    assert.ok(atencion.cuerpo.solicitudes.every((s: { alertas: string[] }) => s.alertas.length > 0));
  });

  it("CONFIRMADO sin iniciar 30 min después de su hora: sigue CONFIRMADO y aparece como alerta SIN_INICIAR", async () => {
    fijarReloj(AHORA.getTime());
    const p = AHORA.getTime() + 260 * HORA;
    const id = await crear({ trabajadorId: rosa.id, fechaProgramada: new Date(p).toISOString(), inmueble: inmuebleNuevo("Sin iniciar 1"), extraIds: [] });
    assert.equal((await tra(rosa, "POST", `/solicitudes/${id}/aceptar`)).status, 200);
    fijarReloj(p + 31 * MIN);
    await ejecutarCiclo();
    const d = (await adm(supervisor, "GET", `/solicitudes/${id}`)).cuerpo.solicitud;
    assert.equal(d.estado, "CONFIRMADO");
    assert.ok(d.alertas.includes("SIN_INICIAR"));
    const inasistencia = await pedirMultipart(servidor!.base, `/api/cliente/solicitudes/${id}/reportes`, { token: ana.token, campos: { tipo: "INASISTENCIA", descripcion: "No llegó" } });
    assert.equal(inasistencia.status, 201, "el cliente puede reportar que no se presentó");
    ids.inasistencia = id;
  });

  it("el admin no tiene rutas para asignar, confirmar, finalizar ni cancelar (D24)", async () => {
    for (const [metodo, ruta] of [
      ["PATCH", `/solicitudes/${ids.bloqueada}/asignacion`],
      ["POST", `/solicitudes/${ids.bloqueada}/confirmar`],
      ["POST", `/solicitudes/${ids.bloqueada}/finalizar`],
      ["POST", `/solicitudes/${ids.bloqueada}/cancelar`],
      ["PATCH", `/solicitudes/${ids.bloqueada}`],
    ] as const) {
      assert.equal((await adm(propietario, metodo, ruta, {})).status, 404, `${metodo} ${ruta}`);
    }
  });
});

describe("Resolución administrativa (inmutable)", () => {
  it("permisos y validación: sin incidencias 403; sin reportes activos 409; motivo obligatorio", async () => {
    const cuerpo = { resultadoServicio: "NO_REALIZADO", motivo: "El trabajador no completó la cocina" };
    assert.equal((await adm(supervisor, "POST", `/solicitudes/${ids.bloqueada}/resolucion`, cuerpo)).status, 403);
    assert.equal((await adm(propietario, "POST", `/solicitudes/${ids.bloqueada}/resolucion`, cuerpo)).status, 403, "D63b: el propietario no tiene incidencias");
    assert.equal((await adm(incA, "POST", `/solicitudes/${ids.bloqueada}/resolucion`, { resultadoServicio: "NO_REALIZADO", motivo: "corto" })).cuerpo.codigo, "MOTIVO_REQUERIDO");
    assert.equal((await adm(incA, "POST", `/solicitudes/${ids.bloqueada}/resolucion`, { resultadoServicio: "TAL_VEZ", motivo: cuerpo.motivo })).cuerpo.codigo, "RESULTADO_INVALIDO");
    assert.equal((await adm(incA, "POST", `/solicitudes/${ids.carrera}/resolucion`, cuerpo)).cuerpo.codigo, "ESTADO_NO_PERMITIDO", "ya cerrada");
  });

  it("dos admins resuelven a la vez: gana la primera, la segunda recibe 409; una sola resolución y auditoría íntegra", async () => {
    const [a, b] = await Promise.all([
      adm(incA, "POST", `/solicitudes/${ids.bloqueada}/resolucion`, { resultadoServicio: "NO_REALIZADO", motivo: "Se revisaron las fotos: faltó la cocina" }),
      adm(incB, "POST", `/solicitudes/${ids.bloqueada}/resolucion`, { resultadoServicio: "REALIZADO", motivo: "Se revisaron las fotos: quedó completo" }),
    ]);
    assert.deepEqual([a.status, b.status].sort(), [201, 409], `${a.texto} | ${b.texto}`);
    const perdedor = a.status === 409 ? a : b;
    assert.equal(perdedor.cuerpo.codigo, "RESOLUCION_EXISTENTE");
    const resoluciones = await prisma.solicitud_resoluciones.findMany({ where: { solicitud_id: ids.bloqueada } });
    assert.equal(resoluciones.length, 1);
    const r = resoluciones[0]!;
    const s = await prisma.solicitudes.findUniqueOrThrow({ where: { id: ids.bloqueada } });
    assert.equal(s.estado, r.resultado_servicio === "REALIZADO" ? "REALIZADO" : "CANCELADO");
    if (r.resultado_servicio === "REALIZADO") assert.equal(s.realizado_via, "RESOLUCION_ADMIN");
    assert.equal(r.resultado_pago, null, "sin la parte de pago");
    const reporte = await prisma.solicitud_reportes.findUniqueOrThrow({ where: { id: ids.reporteBloqueo } });
    assert.deepEqual([reporte.estado, reporte.resolucion_id], ["RESUELTO", r.id]);
    const eventos = await prisma.moderacion_eventos.findMany({ where: { reporte_id: ids.reporteBloqueo, operacion: "RESOLVER" } });
    assert.equal(eventos.length, 1);
    assert.equal(eventos[0]!.admin_id, r.admin_id);
    assert.equal(eventos[0]!.admin_permiso_id, r.admin_permiso_id);
    const hist = await prisma.solicitud_historial.findFirstOrThrow({ where: { solicitud_id: ids.bloqueada, actor: "ADMIN" } });
    assert.equal(hist.actor_id, r.admin_id);
    assert.equal(await prisma.notificaciones.count({ where: { solicitud_id: ids.bloqueada, tipo: "REPORTE_RESUELTO" } }), 1);
    // Inmutable: otra resolución (aunque haya un reporte nuevo) → 409; no hay ruta para editarla.
    assert.equal((await adm(incA, "POST", `/solicitudes/${ids.bloqueada}/resolucion`, { resultadoServicio: "REALIZADO", motivo: "Cambio de opinión del admin" })).cuerpo.codigo, "RESOLUCION_EXISTENTE");
    assert.equal((await adm(incA, "PATCH", `/solicitudes/${ids.bloqueada}/resolucion`, { motivo: "x" })).status, 404);
  });

  it("la inasistencia (CONFIRMADO sin iniciar) se resuelve como NO_REALIZADO → CANCELADO", async () => {
    const r = await adm(incA, "POST", `/solicitudes/${ids.inasistencia}/resolucion`, { resultadoServicio: "NO_REALIZADO", motivo: "El colaborador no se presentó" });
    assert.equal(r.status, 201, r.texto);
    assert.equal((await prisma.solicitudes.findUniqueOrThrow({ where: { id: ids.inasistencia } })).estado, "CANCELADO");
  });
});

describe("Avisos, rutas obsoletas y sin dinero", () => {
  it("cada uno lista y marca SUS avisos; los de otro → 404", async () => {
    const r = await cli(ana, "GET", "/notificaciones");
    assert.equal(r.status, 200);
    assert.ok(r.cuerpo.noLeidas > 0);
    const primero = r.cuerpo.notificaciones[0];
    assert.equal((await cli(beto, "POST", `/notificaciones/${primero.id}/leida`)).status, 404);
    assert.equal((await cli(ana, "POST", `/notificaciones/${primero.id}/leida`)).status, 200);
    assert.equal((await cli(ana, "POST", "/notificaciones/leidas")).status, 200);
    assert.equal((await cli(ana, "GET", "/notificaciones")).cuerpo.noLeidas, 0);
    assert.equal((await tra(rosa, "GET", "/notificaciones")).status, 200);
  });

  it("las rutas obsoletas de las apps no existen (D12)", async () => {
    for (const ruta of ["/galaxias", "/hoyo-negro", "/hoyo-negro/disponibles"]) assert.equal((await pedir("POST", ruta, { token: ana.token, cuerpo: {} })).status, 404, ruta);
  });

  it("no se escribió NADA de dinero en todo el ciclo", async () => {
    assert.equal(await prisma.trabajador_movimientos.count(), 0);
    assert.equal(await prisma.cliente_adeudos.count(), 0);
    assert.equal(await prisma.descuento_usos.count(), 0);
    assert.equal(await prisma.solicitudes.count({ where: { OR: [{ estado_pago: { not: "PENDIENTE" } }, { pago_registrado_en: { not: null } }, { ganancia_liberada_en: { not: null } }, { reporte_pago_hasta: { not: null } }] } }), 0);
    assert.equal(await prisma.solicitud_resoluciones.count({ where: { resultado_pago: { not: null } } }), 0);
  });
});
