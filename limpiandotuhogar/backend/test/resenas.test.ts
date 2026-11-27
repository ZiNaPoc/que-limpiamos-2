// Primero el entorno: apunta la app a la BD LOCAL de pruebas antes de cargar nada más.
import { ORIGEN_PANEL } from "./soporte/entorno";

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import app from "../src/app";
import { prisma } from "../src/config/prisma";
import { relojDominio } from "../src/dominio/reloj";
import { bloqueaConfirmacionAutomatica } from "../src/dominio/reportes";
import { type FotoProduccion, limpiarBdDePruebas, prepararBdDePruebas } from "./soporte/bd";
import {
  type Admin,
  type Cliente,
  crearCliente,
  crearPropietarioYModerador,
  crearSolicitud,
  crearTrabajador,
  pedirMultipart,
  type Trabajador,
} from "./soporte/fabrica";
import { crearPeticiones, iniciarServidor } from "./soporte/http";

/**
 * Fase 3a — RESEÑAS (doc 20 §1–§2): reglas, plazo de 168 h, unicidad (también tras eliminar),
 * privacidad del autor y reputaciones. BD LOCAL de pruebas.
 */

const AHORA = new Date("2026-11-25T12:00:00.000Z");
const HORA = 3600_000;
const relojOriginal = relojDominio.ahora;

let foto: FotoProduccion | undefined;
let servidor: Awaited<ReturnType<typeof iniciarServidor>> | undefined;
let pedir: ReturnType<typeof crearPeticiones>;
let ana: Cliente; // cliente principal
let beto: Cliente; // otro cliente (no es parte)
let rosa: Trabajador; // trabajadora asignada
let luis: Trabajador; // trabajador sin relación
let invitada: Trabajador; // invitada (PENDIENTE) a una solicitud de Ana
let rechazo: Trabajador; // rechazó la invitación
let moderador: Admin;
const s: Record<string, number> = {};

before(async () => {
  foto = await prepararBdDePruebas();
  relojDominio.ahora = () => new Date(AHORA);
  ana = await crearCliente("Ana Autora Secreta");
  beto = await crearCliente("Beto Ajeno");
  rosa = await crearTrabajador("Rosa Calificada");
  luis = await crearTrabajador("Luis Sin Relacion");
  invitada = await crearTrabajador("Ivon Invitada");
  rechazo = await crearTrabajador("Raul Rechazo");
  ({ moderador } = await crearPropietarioYModerador());
  const realizado = { clienteId: ana.id, trabajadorId: rosa.id, estado: "REALIZADO" as const };
  s.principal = await crearSolicitud({ ...realizado, realizadoEn: new Date(AHORA.getTime() - 2 * HORA) });
  s.pendiente = await crearSolicitud({ clienteId: ana.id, trabajadorId: rosa.id, estado: "CONFIRMADO" });
  s.vencida = await crearSolicitud({ ...realizado, realizadoEn: new Date(AHORA.getTime() - 168 * HORA - 1000) });
  s.limite = await crearSolicitud({ ...realizado, realizadoEn: new Date(AHORA.getTime() - 168 * HORA) });
  s.comentario = await crearSolicitud({ ...realizado, realizadoEn: new Date(AHORA.getTime() - HORA) });
  s.eliminar = await crearSolicitud({ ...realizado, realizadoEn: new Date(AHORA.getTime() - HORA) });
  s.invitacion = await crearSolicitud({ clienteId: ana.id, estado: "PENDIENTE" });
  await prisma.solicitud_trabajadores.create({ data: { solicitud_id: s.invitacion, trabajador_id: invitada.id, origen: "INVITACION", estado: "PENDIENTE" } });
  await prisma.solicitud_trabajadores.create({ data: { solicitud_id: s.invitacion, trabajador_id: rechazo.id, origen: "INVITACION", estado: "RECHAZADA" } });
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

const resenaCliente = (solicitud: number, cuerpo: unknown, token = ana.token) =>
  pedir("POST", `/api/cliente/solicitudes/${solicitud}/resena`, { token, cuerpo });
const resenaTrabajador = (solicitud: number, cuerpo: unknown, token = rosa.token) =>
  pedir("POST", `/api/trabajador/solicitudes/${solicitud}/resena`, { token, cuerpo });

/** Ninguna respuesta para usuarios puede delatar al autor de una reseña. */
function sinAutor(texto: string, autor: { nombre: string; correo: string }) {
  assert.ok(!texto.includes(autor.nombre), `la respuesta revela el nombre del autor: ${texto}`);
  assert.ok(!texto.includes(autor.correo), `la respuesta revela el correo del autor: ${texto}`);
  for (const clave of ['"autor', '"cliente', '"clienteId"', '"solicitud', '"servicio', '"fecha"', '"id"']) {
    assert.ok(!texto.includes(clave), `la respuesta incluye ${clave}: ${texto}`);
  }
}

describe("Reseñas: creación y reglas", () => {
  it("el cliente califica al trabajador (201) y se guarda la identidad internamente", async () => {
    const r = await resenaCliente(s.principal!, { puntuacion: 2, comentario: "  Llegó tarde  " });
    assert.equal(r.status, 201, r.texto);
    assert.equal(r.cuerpo.resena.puntuacion, 2);
    assert.equal(r.cuerpo.resena.comentario, "Llegó tarde");
    assert.equal(r.cuerpo.resena.calificaA, "TRABAJADOR");
    const fila = await prisma.resenas.findFirstOrThrow({ where: { solicitud_id: s.principal, autor_rol: "CLIENTE" } });
    assert.equal(fila.cliente_id, ana.id);
    assert.equal(fila.trabajador_id, rosa.id);
  });

  it("se publica de inmediato: el trabajador aún no calificó y la reseña ya es visible", async () => {
    assert.equal(await prisma.resenas.count({ where: { solicitud_id: s.principal, autor_rol: "TRABAJADOR" } }), 0);
    const r = await pedir("GET", `/api/cliente/trabajadores/${rosa.id}/resenas`, { token: beto.token });
    assert.equal(r.status, 200);
    assert.deepEqual(r.cuerpo.resenas, [{ puntuacion: 2, comentario: "Llegó tarde", mes: 11, anio: 2026 }]);
    assert.deepEqual(r.cuerpo.reputacion, { promedio: 2, cantidad: 1 });
  });

  it("el trabajador califica al cliente en la MISMA solicitud (el otro rol está permitido)", async () => {
    const r = await resenaTrabajador(s.principal!, { puntuacion: 5 });
    assert.equal(r.status, 201, r.texto);
    assert.equal(r.cuerpo.resena.calificaA, "CLIENTE");
    assert.equal(r.cuerpo.resena.comentario, null);
    assert.equal(await prisma.resenas.count({ where: { solicitud_id: s.principal } }), 2);
  });

  it("reseña duplicada del mismo rol → 409", async () => {
    assert.equal((await resenaCliente(s.principal!, { puntuacion: 4 })).status, 409);
    assert.equal((await resenaTrabajador(s.principal!, { puntuacion: 4 })).cuerpo.codigo, "RESENA_DUPLICADA");
  });

  it("calificación fuera de 1–5, decimal o como texto → 400", async () => {
    for (const puntuacion of [0, 6, -1, 3.5, "5", null]) {
      const r = await resenaCliente(s.comentario!, { puntuacion });
      assert.equal(r.status, 400, `puntuacion ${String(puntuacion)}`);
      assert.equal(r.cuerpo.codigo, "PUNTUACION_INVALIDA");
    }
    assert.equal((await resenaCliente(s.comentario!, {})).cuerpo.codigo, "PUNTUACION_INVALIDA");
  });

  it("comentario de más de 500 caracteres → 400; exactamente 500 → 201", async () => {
    const largo = await resenaCliente(s.comentario!, { puntuacion: 4, comentario: "x".repeat(501) });
    assert.equal(largo.status, 400);
    assert.equal(largo.cuerpo.codigo, "COMENTARIO_LARGO");
    const justo = await resenaCliente(s.comentario!, { puntuacion: 4, comentario: "ñ".repeat(500) });
    assert.equal(justo.status, 201, justo.texto);
  });

  it("sin fotografías: campo de fotos → 400 y multipart → 415", async () => {
    const conCampo = await resenaTrabajador(s.comentario!, { puntuacion: 4, fotos: ["x"] });
    assert.equal(conCampo.status, 400);
    assert.equal(conCampo.cuerpo.codigo, "FOTOS_NO_PERMITIDAS");
    const multipart = await pedirMultipart(servidor!.base, `/api/trabajador/solicitudes/${s.comentario}/resena`, {
      token: rosa.token,
      campos: { puntuacion: "4" },
      archivos: [{ nombre: "a.jpg", contenido: Buffer.from([0xff, 0xd8, 0xff]), tipo: "image/jpeg" }],
    });
    assert.equal(multipart.status, 415);
  });

  it("antes de REALIZADO → 409 SERVICIO_NO_FINALIZADO", async () => {
    const r = await resenaCliente(s.pendiente!, { puntuacion: 5 });
    assert.equal(r.status, 409);
    assert.equal(r.cuerpo.codigo, "SERVICIO_NO_FINALIZADO");
  });

  it("después de 168 horas exactas → 409 PLAZO_VENCIDO; justo a las 168 h todavía se puede", async () => {
    const vencida = await resenaCliente(s.vencida!, { puntuacion: 5 });
    assert.equal(vencida.status, 409);
    assert.equal(vencida.cuerpo.codigo, "PLAZO_VENCIDO");
    assert.equal((await resenaTrabajador(s.vencida!, { puntuacion: 5 })).cuerpo.codigo, "PLAZO_VENCIDO");
    assert.equal((await resenaCliente(s.limite!, { puntuacion: 3 })).status, 201);
  });

  it("quien no es parte del servicio → 403; solicitud inexistente → 404", async () => {
    assert.equal((await resenaCliente(s.principal!, { puntuacion: 1 }, beto.token)).status, 403);
    assert.equal((await resenaTrabajador(s.principal!, { puntuacion: 1 }, luis.token)).status, 403);
    assert.equal((await resenaCliente(99999999, { puntuacion: 1 })).status, 404);
  });

  it("sin token → 401; el token de otra audiencia no sirve", async () => {
    assert.equal((await pedir("POST", `/api/cliente/solicitudes/${s.comentario}/resena`, { cuerpo: { puntuacion: 5 } })).status, 401);
    assert.equal((await pedir("POST", `/api/cliente/solicitudes/${s.comentario}/resena`, { token: rosa.token, cuerpo: { puntuacion: 5 } })).status, 401);
  });
});

describe("Reseñas: historial, edición y eliminación por el usuario", () => {
  it("cada usuario ve en su historial las reseñas que escribió", async () => {
    const cliente = await pedir("GET", "/api/cliente/resenas", { token: ana.token });
    assert.equal(cliente.status, 200);
    assert.ok(cliente.cuerpo.resenas.length >= 2);
    assert.ok(cliente.cuerpo.resenas.every((r: { calificaA: string }) => r.calificaA === "TRABAJADOR"));
    const trabajador = await pedir("GET", "/api/trabajador/resenas", { token: rosa.token });
    assert.deepEqual(trabajador.cuerpo.resenas.map((r: { calificaA: string; puntuacion: number }) => [r.calificaA, r.puntuacion]), [["CLIENTE", 5]]);
  });

  it("el usuario no puede editar ni eliminar reseñas (propias o ajenas): no hay rutas", async () => {
    const [propia] = (await pedir("GET", "/api/cliente/resenas", { token: ana.token })).cuerpo.resenas;
    for (const [metodo, ruta, token] of [
      ["PATCH", `/api/cliente/resenas/${propia.id}`, ana.token],
      ["DELETE", `/api/cliente/resenas/${propia.id}`, ana.token],
      ["PUT", `/api/cliente/resenas/${propia.id}`, ana.token],
      ["PATCH", `/api/trabajador/resenas/${propia.id}`, rosa.token],
      ["DELETE", `/api/trabajador/resenas/${propia.id}`, rosa.token],
    ] as const) {
      const r = await pedir(metodo, ruta, { token, cuerpo: { puntuacion: 5 } });
      assert.equal(r.status, 404, `${metodo} ${ruta}`);
    }
    // Ni con el token de usuario en las rutas de moderación.
    const admin = await pedir("PATCH", `/api/admin/resenas/${propia.id}`, { token: ana.token, origen: ORIGEN_PANEL, cuerpo: { puntuacion: 5, motivo: "x" } });
    assert.equal(admin.status, 401);
    const fila = await prisma.resenas.findUniqueOrThrow({ where: { id: propia.id } });
    assert.equal(fila.editada_en, null);
  });

  it("la eliminación LÓGICA conserva el lugar único: no se puede volver a calificar", async () => {
    const creada = await resenaCliente(s.eliminar!, { puntuacion: 1, comentario: "Para eliminar" });
    assert.equal(creada.status, 201);
    const borrar = await pedir("DELETE", `/api/admin/resenas/${creada.cuerpo.resena.id}`, {
      cookie: moderador.cookie,
      origen: ORIGEN_PANEL,
      cuerpo: { motivo: "Contenido ofensivo (prueba)" },
    });
    assert.equal(borrar.status, 200, borrar.texto);
    const fila = await prisma.resenas.findUniqueOrThrow({ where: { id: creada.cuerpo.resena.id } });
    assert.ok(fila.eliminada_en, "la fila sigue existiendo, marcada como eliminada");
    const otraVez = await resenaCliente(s.eliminar!, { puntuacion: 5 });
    assert.equal(otraVez.status, 409);
    assert.equal(otraVez.cuerpo.codigo, "RESENA_DUPLICADA");
    const historial = await pedir("GET", "/api/cliente/resenas", { token: ana.token });
    const enHistorial = historial.cuerpo.resenas.find((r: { id: number }) => r.id === creada.cuerpo.resena.id);
    assert.equal(enHistorial.eliminadaPorModeracion, true);
  });
});

describe("Reseñas: privacidad del autor", () => {
  it("el cliente consulta las reseñas de un trabajador sin autor, servicio ni fecha exacta", async () => {
    const r = await pedir("GET", `/api/cliente/trabajadores/${rosa.id}/resenas`, { token: beto.token });
    assert.equal(r.status, 200);
    for (const resena of r.cuerpo.resenas) assert.deepEqual(Object.keys(resena).sort(), ["anio", "comentario", "mes", "puntuacion"]);
    sinAutor(r.texto, ana);
  });

  it("el trabajador ve las reseñas que recibió sin saber quién las escribió", async () => {
    const r = await pedir("GET", "/api/trabajador/resenas/recibidas", { token: rosa.token });
    assert.equal(r.status, 200);
    assert.ok(r.cuerpo.resenas.length >= 3);
    for (const resena of r.cuerpo.resenas) assert.deepEqual(Object.keys(resena).sort(), ["anio", "comentario", "mes", "puntuacion"]);
    sinAutor(r.texto, ana);
  });

  it("los demás endpoints de usuario tampoco filtran al autor", async () => {
    const rutas: [string, string][] = [
      [`/api/cliente/trabajadores/${rosa.id}/reputacion`, beto.token],
      [`/api/cliente/trabajadores/reputacion?ids=${rosa.id},${luis.id}`, beto.token],
      ["/api/trabajador/resenas/recibidas", rosa.token],
      [`/api/trabajador/solicitudes/${s.principal}/reputacion-cliente`, rosa.token],
    ];
    for (const [ruta, token] of rutas) {
      const r = await pedir("GET", ruta, { token });
      assert.equal(r.status, 200, `${ruta}: ${r.texto}`);
      assert.ok(!r.texto.includes(ana.nombre) && !r.texto.includes(ana.correo), `${ruta} revela al autor`);
      assert.ok(!/"(autor|cliente|clienteId|solicitudId)"/.test(r.texto), `${ruta} incluye campos de identidad: ${r.texto}`);
    }
  });
});

describe("Reputación y promedios", () => {
  it("promedio del trabajador con reseñas válidas; la eliminada no cuenta; sin reseñas → null", async () => {
    const r = await pedir("GET", `/api/cliente/trabajadores/reputacion?ids=${rosa.id},${luis.id}`, { token: beto.token });
    // Válidas de clientes a Rosa: 2 (principal), 4 (comentario), 3 (límite). La de 1 estrella se eliminó.
    assert.deepEqual(r.cuerpo.reputaciones[String(rosa.id)], { promedio: 3, cantidad: 3 });
    assert.deepEqual(r.cuerpo.reputaciones[String(luis.id)], { promedio: null, cantidad: 0 });
  });

  it("una corrección de la moderación cuenta con su valor nuevo", async () => {
    const fila = await prisma.resenas.findFirstOrThrow({ where: { solicitud_id: s.principal, autor_rol: "CLIENTE" } });
    const r = await pedir("PATCH", `/api/admin/resenas/${fila.id}`, {
      cookie: moderador.cookie,
      origen: ORIGEN_PANEL,
      cuerpo: { puntuacion: 5, motivo: "El cliente se equivocó de estrellas (prueba)" },
    });
    assert.equal(r.status, 200, r.texto);
    const rep = await pedir("GET", `/api/cliente/trabajadores/${rosa.id}/reputacion`, { token: beto.token });
    assert.deepEqual(rep.cuerpo.reputacion, { promedio: 4, cantidad: 3 });
  });

  it("reputación del cliente: la ve el trabajador ASIGNADO o INVITADO; no un trabajador ajeno ni el que rechazó", async () => {
    const asignada = await pedir("GET", `/api/trabajador/solicitudes/${s.principal}/reputacion-cliente`, { token: rosa.token });
    assert.equal(asignada.status, 200);
    assert.deepEqual(asignada.cuerpo.reputacion, { promedio: 5, cantidad: 1 });
    assert.equal((await pedir("GET", `/api/trabajador/solicitudes/${s.invitacion}/reputacion-cliente`, { token: invitada.token })).status, 200);
    const ajeno = await pedir("GET", `/api/trabajador/solicitudes/${s.principal}/reputacion-cliente`, { token: luis.token });
    assert.equal(ajeno.status, 403);
    assert.equal(ajeno.cuerpo.codigo, "REPUTACION_NO_AUTORIZADA");
    assert.equal((await pedir("GET", `/api/trabajador/solicitudes/${s.invitacion}/reputacion-cliente`, { token: rechazo.token })).status, 403);
    // Un cliente no tiene ninguna ruta para ver la reputación de otro cliente.
    assert.equal((await pedir("GET", `/api/cliente/clientes/${ana.id}/reputacion`, { token: beto.token })).status, 404);
  });
});

describe("Las reseñas no bloquean nada", () => {
  it("calificar no cambia la solicitud ni el pago, no crea adeudos ni incidencias, y no impide nuevas solicitudes", async () => {
    const antes = await prisma.solicitudes.findUniqueOrThrow({ where: { id: s.limite } });
    const adeudosAntes = await prisma.cliente_adeudos.count();
    const r = await resenaTrabajador(s.limite!, { puntuacion: 4 });
    assert.equal(r.status, 201, r.texto);
    const despues = await prisma.solicitudes.findUniqueOrThrow({ where: { id: s.limite } });
    for (const campo of ["estado", "estado_pago", "pago_registrado_en", "pago_registrado_por", "ganancia_liberada_en", "realizado_en"] as const) {
      assert.deepEqual(despues[campo], antes[campo], campo);
    }
    assert.equal(await prisma.cliente_adeudos.count(), adeudosAntes);
    assert.equal(await bloqueaConfirmacionAutomatica(s.limite!), false, "una reseña no es una incidencia (D57)");
    const nueva = await crearSolicitud({ clienteId: ana.id, trabajadorId: rosa.id });
    assert.ok(nueva > 0);
  });
});
