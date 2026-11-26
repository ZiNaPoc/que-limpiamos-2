// Primero el entorno: apunta la app a la BD LOCAL de pruebas antes de cargar nada más.
import "./soporte/entorno";

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import app from "../src/app";
import { prisma } from "../src/config/prisma";
import { relojDominio } from "../src/dominio/reloj";
import { type FotoProduccion, limpiarBdDePruebas, prepararBdDePruebas } from "./soporte/bd";
import { type Cliente, crearCliente, crearSolicitud, crearTrabajador, type Trabajador } from "./soporte/fabrica";
import { crearPeticiones, iniciarServidor } from "./soporte/http";

/**
 * Fase 3b — consultas de solo lectura para las apps (doc 23 §2): historial del cliente, historial e
 * invitaciones del trabajador, y la lista de selección manual. BD LOCAL de pruebas.
 */

const AHORA = new Date("2026-11-25T12:00:00.000Z");
const HORA = 3600_000;
const relojOriginal = relojDominio.ahora;

let foto: FotoProduccion | undefined;
let servidor: Awaited<ReturnType<typeof iniciarServidor>> | undefined;
let pedir: ReturnType<typeof crearPeticiones>;
let ana: Cliente;
let beto: Cliente;
let rosa: Trabajador; // asignada, verificada
let ivon: Trabajador; // invitada (PENDIENTE), verificada
let raul: Trabajador; // rechazó la invitación, sin verificar
let inactivo: Trabajador;
const s: Record<string, number> = {};
let servicioConEspecialidades = 0;

before(async () => {
  foto = await prepararBdDePruebas();
  relojDominio.ahora = () => new Date(AHORA);
  ana = await crearCliente("Ana Historial");
  beto = await crearCliente("Beto Ajeno");
  rosa = await crearTrabajador("Rosa Asignada");
  ivon = await crearTrabajador("Ivon Invitada");
  raul = await crearTrabajador("Raul Sin Verificar");
  inactivo = await crearTrabajador("Ines Inactiva");
  await prisma.trabajadores.updateMany({ where: { id: { in: [rosa.id, ivon.id] } }, data: { estado_verificacion: "VERIFICADO" } });
  await prisma.trabajadores.update({ where: { id: inactivo.id }, data: { estado_verificacion: "VERIFICADO", estado: "INACTIVO" } });

  const realizado = { clienteId: ana.id, trabajadorId: rosa.id, estado: "REALIZADO" as const, programada: new Date(AHORA.getTime() - 10 * HORA) };
  s.calificable = await crearSolicitud({ ...realizado, realizadoEn: new Date(AHORA.getTime() - 2 * HORA) });
  s.vencida = await crearSolicitud({ ...realizado, realizadoEn: new Date(AHORA.getTime() - 169 * HORA) });
  s.futura = await crearSolicitud({ clienteId: ana.id, trabajadorId: rosa.id, estado: "CONFIRMADO", programada: new Date(AHORA.getTime() + 5 * HORA) });
  s.sinTrabajador = await crearSolicitud({ clienteId: ana.id, estado: "PENDIENTE", programada: new Date(AHORA.getTime() + 24 * HORA) });
  s.ajena = await crearSolicitud({ clienteId: beto.id, trabajadorId: rosa.id, estado: "CONFIRMADO" });
  await prisma.solicitud_trabajadores.create({ data: { solicitud_id: s.sinTrabajador, trabajador_id: ivon.id, origen: "INVITACION", estado: "PENDIENTE" } });
  await prisma.solicitud_trabajadores.create({ data: { solicitud_id: s.sinTrabajador, trabajador_id: raul.id, origen: "INVITACION", estado: "RECHAZADA" } });

  // Especialidades: el servicio exige "Vidrios" y "Alturas"; Rosa tiene las dos e Ivon solo una.
  const vidrios = await prisma.especialidades.create({ data: { nombre: "Vidrios (prueba)" } });
  const alturas = await prisma.especialidades.create({ data: { nombre: "Alturas (prueba)" } });
  servicioConEspecialidades = (await prisma.servicios.create({ data: { nombre: "Ventanas altas (prueba)", descripcion: "x", precio_base: 800 } })).id;
  await prisma.servicio_especialidades.createMany({ data: [{ servicio_id: servicioConEspecialidades, especialidad_id: vidrios.id }, { servicio_id: servicioConEspecialidades, especialidad_id: alturas.id }] });
  await prisma.trabajador_especialidades.createMany({
    data: [
      { trabajador_id: rosa.id, especialidad_id: vidrios.id },
      { trabajador_id: rosa.id, especialidad_id: alturas.id },
      { trabajador_id: ivon.id, especialidad_id: vidrios.id },
    ],
  });

  servidor = await iniciarServidor(app);
  pedir = crearPeticiones(servidor.base);
});

after(async () => {
  relojDominio.ahora = relojOriginal;
  await servidor?.cerrar();
  await prisma.$disconnect().catch(() => undefined);
  const resultado = await limpiarBdDePruebas(foto);
  assert.deepEqual(resultado.tablasRestantes, [], "BD de pruebas sin vaciar");
});

const porId = (lista: { id: number }[], id: number) => lista.find((x) => x.id === id) as any;

describe("GET /api/cliente/solicitudes", () => {
  it("solo las solicitudes del cliente, con el id real y el trabajador asignado (sin correo ni teléfono)", async () => {
    const r = await pedir("GET", "/api/cliente/solicitudes", { token: ana.token });
    assert.equal(r.status, 200, r.texto);
    const ids = r.cuerpo.solicitudes.map((x: { id: number }) => x.id).sort();
    assert.deepEqual(ids, [s.calificable, s.vencida, s.futura, s.sinTrabajador].sort());
    const una = porId(r.cuerpo.solicitudes, s.calificable!);
    assert.deepEqual(una.trabajador, { id: rosa.id, nombre: rosa.nombre });
    assert.equal(una.servicio, "Limpieza de prueba");
    assert.ok(!r.texto.includes(rosa.correo), "no expone el correo del trabajador");
  });

  it("puedeCalificar: REALIZADO dentro de 168 h y sin reseña; con el plazo vencido o sin finalizar, no", async () => {
    const lista = (await pedir("GET", "/api/cliente/solicitudes", { token: ana.token })).cuerpo.solicitudes;
    assert.equal(porId(lista, s.calificable!).puedeCalificar, true);
    assert.equal(porId(lista, s.calificable!).calificarHasta, new Date(AHORA.getTime() - 2 * HORA + 168 * HORA).toISOString());
    assert.equal(porId(lista, s.vencida!).puedeCalificar, false);
    assert.equal(porId(lista, s.futura!).puedeCalificar, false);
    assert.equal(porId(lista, s.futura!).calificarHasta, null);
  });

  it("puedeReportar: desde la hora programada y con trabajador asignado", async () => {
    const lista = (await pedir("GET", "/api/cliente/solicitudes", { token: ana.token })).cuerpo.solicitudes;
    assert.equal(porId(lista, s.calificable!).puedeReportar, true);
    assert.equal(porId(lista, s.futura!).puedeReportar, false);
    assert.equal(porId(lista, s.sinTrabajador!).puedeReportar, false);
  });

  it("tras calificar, la solicitud trae miResena y deja de ser calificable; no trae la reseña que el cliente RECIBIÓ", async () => {
    assert.equal((await pedir("POST", `/api/cliente/solicitudes/${s.calificable}/resena`, { token: ana.token, cuerpo: { puntuacion: 4, comentario: "Bien" } })).status, 201);
    assert.equal((await pedir("POST", `/api/trabajador/solicitudes/${s.calificable}/resena`, { token: rosa.token, cuerpo: { puntuacion: 2, comentario: "Comentario del trabajador" } })).status, 201);
    const r = await pedir("GET", "/api/cliente/solicitudes", { token: ana.token });
    const una = porId(r.cuerpo.solicitudes, s.calificable!);
    assert.deepEqual({ ...una.miResena, fecha: undefined }, { puntuacion: 4, comentario: "Bien", fecha: undefined, eliminadaPorModeracion: false });
    assert.equal(una.puedeCalificar, false);
    assert.ok(!r.texto.includes("Comentario del trabajador"), "la reputación del cliente no se expone al propio cliente");
  });

  it("sin token → 401", async () => {
    assert.equal((await pedir("GET", "/api/cliente/solicitudes")).status, 401);
  });
});

describe("GET /api/trabajador/solicitudes", () => {
  it("asignadas (de cualquier cliente) e invitaciones vigentes; no las rechazadas ni ajenas", async () => {
    const r = await pedir("GET", "/api/trabajador/solicitudes", { token: rosa.token });
    assert.equal(r.status, 200, r.texto);
    assert.deepEqual(r.cuerpo.solicitudes.map((x: { id: number }) => x.id).sort(), [s.calificable, s.vencida, s.futura, s.ajena].sort());
    assert.ok(r.cuerpo.solicitudes.every((x: { relacion: string }) => x.relacion === "ASIGNADO"));
    assert.ok(!r.texto.includes(ana.correo), "no expone el correo del cliente");
    const invitada = (await pedir("GET", "/api/trabajador/solicitudes", { token: ivon.token })).cuerpo.solicitudes;
    assert.deepEqual(invitada.map((x: { id: number; relacion: string; invitacion: string }) => [x.id, x.relacion, x.invitacion]), [[s.sinTrabajador, "INVITADO", "PENDIENTE"]]);
    assert.equal(invitada[0].puedeCalificar, false);
    assert.equal(invitada[0].puedeReportar, false);
    assert.equal(invitada[0].puedeVerReputacionCliente, true);
    assert.deepEqual((await pedir("GET", "/api/trabajador/solicitudes", { token: raul.token })).cuerpo.solicitudes, []);
  });

  it("trae miResena del trabajador y el nombre del cliente, sin su correo ni teléfono", async () => {
    const lista = (await pedir("GET", "/api/trabajador/solicitudes", { token: rosa.token })).cuerpo.solicitudes;
    const una = porId(lista, s.calificable!);
    assert.equal(una.miResena.puntuacion, 2);
    assert.equal(una.puedeCalificar, false);
    assert.deepEqual(una.cliente, { nombre: ana.nombre });
    assert.equal(porId(lista, s.vencida!).puedeCalificar, false);
    assert.ok(!JSON.stringify(lista).includes(ana.correo));
  });

  it("sin token de trabajador → 401", async () => {
    assert.equal((await pedir("GET", "/api/trabajador/solicitudes", { token: ana.token })).status, 401);
  });
});

describe("GET /api/cliente/trabajadores (selección manual)", () => {
  it("solo ACTIVOS y VERIFICADOS, con estrellas y especialidades, sin datos de contacto", async () => {
    const r = await pedir("GET", "/api/cliente/trabajadores", { token: ana.token });
    assert.equal(r.status, 200, r.texto);
    const ids = r.cuerpo.trabajadores.map((t: { id: number }) => t.id);
    assert.ok(ids.includes(rosa.id) && ids.includes(ivon.id));
    assert.ok(!ids.includes(raul.id), "sin verificar no aparece");
    assert.ok(!ids.includes(inactivo.id), "inactivo no aparece");
    const r2 = r.cuerpo.trabajadores.find((t: { id: number }) => t.id === rosa.id);
    assert.deepEqual(r2.reputacion, { promedio: 4, cantidad: 1 });
    assert.deepEqual(r2.especialidades, ["Alturas (prueba)", "Vidrios (prueba)"]);
    assert.deepEqual(Object.keys(r2).sort(), ["especialidades", "id", "nombre", "reputacion"]);
    assert.ok(!r.texto.includes(rosa.correo));
  });

  it("con servicioId: solo quien tiene TODAS las especialidades que exige el servicio; servicio inexistente → 404", async () => {
    const r = await pedir("GET", `/api/cliente/trabajadores?servicioId=${servicioConEspecialidades}`, { token: ana.token });
    assert.deepEqual(r.cuerpo.trabajadores.map((t: { id: number }) => t.id), [rosa.id]);
    assert.equal((await pedir("GET", "/api/cliente/trabajadores?servicioId=99999999", { token: ana.token })).status, 404);
    assert.equal((await pedir("GET", "/api/cliente/trabajadores?servicioId=abc", { token: ana.token })).status, 400);
  });
});
