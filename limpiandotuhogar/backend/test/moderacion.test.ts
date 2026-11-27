// Primero el entorno: apunta la app a la BD LOCAL de pruebas antes de cargar nada más.
import { ORIGEN_PANEL } from "./soporte/entorno";

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import app from "../src/app";
import { prisma } from "../src/config/prisma";
import { asignacionInicialPropietario } from "../src/dominio/permisos";
import { relojDominio } from "../src/dominio/reloj";
import { type FotoProduccion, limpiarBdDePruebas, prepararBdDePruebas } from "./soporte/bd";
import { type Admin, type Cliente, crearAdmin, crearCliente, crearSolicitud, crearTrabajador, type Trabajador } from "./soporte/fabrica";
import { crearPeticiones, iniciarServidor } from "./soporte/http";

/**
 * Fase 3a — MODERACIÓN de reseñas, PERMISO MODERAR_CONTENIDO y AUDITORÍA (doc 20 §4–§6).
 * BD LOCAL de pruebas. Los "propietarios" y admins de aquí son cuentas de PRUEBA.
 */

const AHORA = new Date("2026-11-25T12:00:00.000Z");
const relojOriginal = relojDominio.ahora;

let foto: FotoProduccion | undefined;
let servidor: Awaited<ReturnType<typeof iniciarServidor>> | undefined;
let pedir: ReturnType<typeof crearPeticiones>;
let propietario: Admin;
let moderador: Admin;
let comun: Admin; // admin sin permisos
let cliente: Cliente;
let trabajador: Trabajador;
let resenaId = 0;

before(async () => {
  foto = await prepararBdDePruebas();
  relojDominio.ahora = () => new Date(AHORA);
  propietario = await crearAdmin("Propietaria Prueba");
  moderador = await crearAdmin("Mora Moderadora");
  comun = await crearAdmin("Admin Comun");
  cliente = await crearCliente("Clara Autora");
  trabajador = await crearTrabajador("Tadeo Calificado");
  const solicitud = await crearSolicitud({ clienteId: cliente.id, trabajadorId: trabajador.id, estado: "REALIZADO", realizadoEn: new Date(AHORA.getTime() - 3600_000) });
  servidor = await iniciarServidor(app);
  pedir = crearPeticiones(servidor.base);
  const r = await pedir("POST", `/api/cliente/solicitudes/${solicitud}/resena`, { token: cliente.token, cuerpo: { puntuacion: 1, comentario: "Pésimo" } });
  assert.equal(r.status, 201, r.texto);
  resenaId = r.cuerpo.resena.id;
});

after(async () => {
  relojDominio.ahora = relojOriginal;
  await servidor?.cerrar();
  await prisma.$disconnect().catch(() => undefined);
  const resultado = await limpiarBdDePruebas(foto);
  assert.deepEqual(resultado.tablasRestantes, [], "BD de pruebas sin vaciar");
});

const adminPide = (quien: Admin, metodo: string, ruta: string, cuerpo?: unknown) =>
  pedir(metodo, ruta, { cookie: quien.cookie, origen: ORIGEN_PANEL, cuerpo });

describe("Permiso MODERAR_CONTENIDO: asignación inicial, otorgamiento y revocación auditados", () => {
  it("asignación inicial al propietario: permisos con origen ASIGNACION_INICIAL y su evento sin actor", async () => {
    const r = await asignacionInicialPropietario(propietario.correo, "Propietario de PRUEBA");
    assert.deepEqual(r.permisos.map((p) => p.permiso), ["ADMINISTRAR_PERMISOS", "MODERAR_CONTENIDO"]);
    const eventos = await prisma.moderacion_eventos.findMany({ where: { entidad: "PERMISO" }, orderBy: { id: "asc" } });
    assert.deepEqual(eventos.map((e) => [e.operacion, e.admin_id, e.admin_permiso_id]), [["ASIGNACION_INICIAL", null, null], ["ASIGNACION_INICIAL", null, null]]);
    assert.ok(eventos.every((e) => e.motivo === "Propietario de PRUEBA"));
    // No hay una segunda asignación inicial.
    await assert.rejects(() => asignacionInicialPropietario(moderador.correo, "otra"), /Ya hay un propietario/);
  });

  it("la asignación inicial NO crea cuentas ni acepta cuentas que no sean ADMIN", async () => {
    await assert.rejects(() => asignacionInicialPropietario("nadie@pruebas.test", "x"), /No existe ninguna cuenta/);
    await assert.rejects(() => asignacionInicialPropietario(cliente.correo, "x"), /(no es de administrador|Ya hay un propietario)/);
    assert.equal(await prisma.usuarios.count({ where: { correo: "nadie@pruebas.test" } }), 0);
  });

  it("sin MODERAR_CONTENIDO: 403 en GET /api/admin/resenas (X0) y en todas las acciones de moderación", async () => {
    for (const [metodo, ruta, cuerpo] of [
      ["GET", "/api/admin/resenas", undefined],
      ["PATCH", `/api/admin/resenas/${resenaId}`, { puntuacion: 5, motivo: "x" }],
      ["DELETE", `/api/admin/resenas/${resenaId}`, { motivo: "x" }],
      ["GET", "/api/admin/moderacion/eventos", undefined],
    ] as const) {
      const r = await adminPide(moderador, metodo, ruta, cuerpo);
      assert.equal(r.status, 403, `${metodo} ${ruta}`);
      assert.equal(r.cuerpo.codigo, "PERMISO_REQUERIDO");
    }
    const mios = await adminPide(moderador, "GET", "/api/admin/permisos/mios");
    assert.deepEqual(mios.cuerpo.permisos, []);
  });

  it("solo el propietario otorga; nadie se lo otorga a sí mismo; el permiso no se duplica", async () => {
    assert.equal((await adminPide(comun, "POST", "/api/admin/permisos", { usuarioId: moderador.id, permiso: "MODERAR_CONTENIDO", motivo: "x" })).status, 403);
    const propio = await adminPide(propietario, "POST", "/api/admin/permisos", { usuarioId: propietario.id, permiso: "MODERAR_CONTENIDO", motivo: "x" });
    assert.equal(propio.status, 403);
    assert.equal(propio.cuerpo.codigo, "AUTO_OTORGAMIENTO");
    assert.equal((await adminPide(propietario, "POST", "/api/admin/permisos", { usuarioId: moderador.id, permiso: "ADMINISTRAR_PERMISOS", motivo: "x" })).cuerpo.codigo, "PERMISO_NO_OTORGABLE");
    assert.equal((await adminPide(propietario, "POST", "/api/admin/permisos", { usuarioId: cliente.id, permiso: "MODERAR_CONTENIDO", motivo: "x" })).status, 404);
    assert.equal((await adminPide(propietario, "POST", "/api/admin/permisos", { usuarioId: moderador.id, permiso: "MODERAR_CONTENIDO" })).cuerpo.codigo, "MOTIVO_REQUERIDO");
    const ok = await adminPide(propietario, "POST", "/api/admin/permisos", { usuarioId: moderador.id, permiso: "MODERAR_CONTENIDO", motivo: "Moderará las reseñas" });
    assert.equal(ok.status, 201, ok.texto);
    assert.equal((await adminPide(propietario, "POST", "/api/admin/permisos", { usuarioId: moderador.id, permiso: "MODERAR_CONTENIDO", motivo: "otra vez" })).cuerpo.codigo, "PERMISO_YA_VIGENTE");
    const evento = await prisma.moderacion_eventos.findFirstOrThrow({ where: { entidad: "PERMISO", operacion: "OTORGAR" } });
    assert.equal(evento.admin_id, propietario.id);
    assert.equal(evento.motivo, "Moderará las reseñas");
    assert.deepEqual(evento.datos_anteriores, { usuario_id: moderador.id, permiso: "MODERAR_CONTENIDO", vigente: false });
    assert.deepEqual((await adminPide(moderador, "GET", "/api/admin/permisos/mios")).cuerpo.permisos, ["MODERAR_CONTENIDO"]);
    const lista = await adminPide(propietario, "GET", "/api/admin/permisos");
    assert.equal(lista.status, 200);
    assert.equal((await adminPide(moderador, "GET", "/api/admin/permisos")).status, 403);
  });
});

describe("Moderación de reseñas con auditoría", () => {
  it("el moderador ve al AUTOR y al calificado (X0)", async () => {
    const r = await adminPide(moderador, "GET", "/api/admin/resenas");
    assert.equal(r.status, 200, r.texto);
    const [resena] = r.cuerpo.resenas;
    assert.deepEqual(resena.autor, { id: String(cliente.id), rol: "CLIENTE", nombre: cliente.nombre });
    assert.deepEqual(resena.calificado, { id: String(trabajador.id), rol: "TRABAJADOR", nombre: trabajador.nombre });
    assert.equal(resena.servicio, "Limpieza de prueba");
  });

  it("corrige 1 → 5 estrellas: guarda antes/después, motivo, admin, permiso y fecha UTC", async () => {
    const sinMotivo = await adminPide(moderador, "PATCH", `/api/admin/resenas/${resenaId}`, { puntuacion: 5 });
    assert.equal(sinMotivo.status, 400);
    assert.equal(sinMotivo.cuerpo.codigo, "MOTIVO_REQUERIDO");
    assert.equal(await prisma.moderacion_eventos.count({ where: { resena_id: resenaId } }), 0, "sin motivo no hay cambio ni evento");
    const r = await adminPide(moderador, "PATCH", `/api/admin/resenas/${resenaId}`, { puntuacion: 5, motivo: "El cliente confirmó que quería 5 estrellas" });
    assert.equal(r.status, 200, r.texto);
    const fila = await prisma.resenas.findUniqueOrThrow({ where: { id: resenaId } });
    assert.equal(fila.puntuacion, 5);
    assert.equal(fila.comentario, "Pésimo", "el comentario no cambia si no se envía");
    const [evento] = await prisma.moderacion_eventos.findMany({ where: { resena_id: resenaId } });
    assert.equal(evento!.operacion, "EDITAR");
    assert.equal(evento!.admin_id, moderador.id);
    const permiso = await prisma.admin_permisos.findFirstOrThrow({ where: { usuario_id: moderador.id, permiso: "MODERAR_CONTENIDO", revocado_en: null } });
    assert.equal(evento!.admin_permiso_id, permiso.id);
    assert.deepEqual(evento!.datos_anteriores, { puntuacion: 1, comentario: "Pésimo" }, "el ORIGINAL queda guardado");
    assert.deepEqual(evento!.datos_nuevos, { puntuacion: 5, comentario: "Pésimo" });
    assert.equal(evento!.created_at.toISOString().endsWith("Z"), true);
  });

  it("una corrección inválida (comentario de 501 caracteres o puntuación 9) → 400 sin evento", async () => {
    const antes = await prisma.moderacion_eventos.count();
    assert.equal((await adminPide(moderador, "PATCH", `/api/admin/resenas/${resenaId}`, { comentario: "x".repeat(501), motivo: "m" })).status, 400);
    assert.equal((await adminPide(moderador, "PATCH", `/api/admin/resenas/${resenaId}`, { puntuacion: 9, motivo: "m" })).status, 400);
    assert.equal(await prisma.moderacion_eventos.count(), antes);
  });

  it("elimina LÓGICAMENTE: la fila y sus eventos permanecen; no aparece salvo con incluirEliminadas", async () => {
    const r = await adminPide(moderador, "DELETE", `/api/admin/resenas/${resenaId}`, { motivo: "Lenguaje ofensivo" });
    assert.equal(r.status, 200, r.texto);
    assert.ok((await prisma.resenas.findUniqueOrThrow({ where: { id: resenaId } })).eliminada_en);
    const eventos = await prisma.moderacion_eventos.findMany({ where: { resena_id: resenaId }, orderBy: { id: "asc" } });
    assert.deepEqual(eventos.map((e) => e.operacion), ["EDITAR", "ELIMINAR"]);
    assert.equal((await adminPide(moderador, "GET", "/api/admin/resenas")).cuerpo.total, 0);
    const todas = await adminPide(moderador, "GET", "/api/admin/resenas?incluirEliminadas=1");
    assert.equal(todas.cuerpo.resenas[0].eliminada, true);
    assert.equal((await adminPide(moderador, "DELETE", `/api/admin/resenas/${resenaId}`, { motivo: "otra vez" })).status, 409);
    const historial = await adminPide(moderador, "GET", `/api/admin/moderacion/eventos?entidad=RESENA&id=${resenaId}`);
    assert.equal(historial.cuerpo.total, 2);
    assert.equal(historial.cuerpo.eventos[0].admin.nombre, moderador.nombre);
  });

  it("revocar: el moderador pierde el acceso al instante; la revocación queda auditada", async () => {
    const permiso = await prisma.admin_permisos.findFirstOrThrow({ where: { usuario_id: moderador.id, permiso: "MODERAR_CONTENIDO", revocado_en: null } });
    assert.equal((await adminPide(moderador, "POST", `/api/admin/permisos/${permiso.id}/revocar`, { motivo: "x" })).status, 403, "solo el propietario revoca");
    const r = await adminPide(propietario, "POST", `/api/admin/permisos/${permiso.id}/revocar`, { motivo: "Dejó el equipo de moderación" });
    assert.equal(r.status, 200, r.texto);
    assert.equal((await adminPide(moderador, "GET", "/api/admin/resenas")).status, 403);
    const evento = await prisma.moderacion_eventos.findFirstOrThrow({ where: { permiso_id: permiso.id, operacion: "REVOCAR" } });
    assert.equal(evento.admin_id, propietario.id);
    const fila = await prisma.admin_permisos.findUniqueOrThrow({ where: { id: permiso.id } });
    assert.equal(fila.revocado_por, propietario.id);
    assert.equal(fila.motivo_revocacion, "Dejó el equipo de moderación");
    const propioPermiso = await prisma.admin_permisos.findFirstOrThrow({ where: { usuario_id: propietario.id, permiso: "MODERAR_CONTENIDO" } });
    assert.equal((await adminPide(propietario, "POST", `/api/admin/permisos/${propioPermiso.id}/revocar`, { motivo: "x" })).cuerpo.codigo, "AUTO_REVOCACION");
  });
});

describe("Auditoría: el historial no se puede alterar", () => {
  it("no existen rutas para editar o borrar eventos (404), ni con permisos", async () => {
    const [evento] = await prisma.moderacion_eventos.findMany({ take: 1 });
    for (const metodo of ["PATCH", "PUT", "DELETE"]) {
      for (const quien of [propietario, comun]) {
        const r = await adminPide(quien, metodo, `/api/admin/moderacion/eventos/${evento!.id}`, { motivo: "x" });
        assert.equal(r.status, 404, `${metodo} con ${quien.nombre}`);
      }
    }
    for (const ruta of ["/api/cliente/moderacion/eventos", "/api/trabajador/moderacion/eventos"]) {
      assert.equal((await pedir("GET", ruta, { token: cliente.token })).status, 404);
    }
    assert.equal((await adminPide(comun, "GET", "/api/admin/moderacion/eventos")).status, 403);
    const permisoEventos = await adminPide(propietario, "GET", "/api/admin/moderacion/eventos?entidad=PERMISO");
    assert.equal(permisoEventos.status, 200);
  });

  it("la BD impide borrar físicamente contenido o permisos con historial (FK RESTRICT)", async () => {
    await assert.rejects(() => prisma.resenas.delete({ where: { id: resenaId } }));
    const permiso = await prisma.admin_permisos.findFirstOrThrow({ where: { usuario_id: moderador.id } });
    await assert.rejects(() => prisma.admin_permisos.delete({ where: { id: permiso.id } }));
    await assert.rejects(() => prisma.usuarios.delete({ where: { id: moderador.id } }));
    assert.equal(await prisma.moderacion_eventos.count({ where: { resena_id: resenaId } }), 2);
  });

  it("la BD rechaza eventos incompletos: sin motivo, sin objetivo, sin actor o con JSON que no es objeto (CHECK)", async () => {
    const permiso = await prisma.admin_permisos.findFirstOrThrow({ where: { usuario_id: propietario.id, permiso: "MODERAR_CONTENIDO" } });
    const base = { admin_id: propietario.id, admin_permiso_id: permiso.id, entidad: "RESENA" as const, resena_id: resenaId, operacion: "EDITAR" as const, datos_anteriores: {}, datos_nuevos: {}, motivo: "ok" };
    await assert.rejects(() => prisma.moderacion_eventos.create({ data: { ...base, motivo: "   " } }), "motivo vacío");
    await assert.rejects(() => prisma.moderacion_eventos.create({ data: { ...base, resena_id: null } }), "sin objetivo");
    await assert.rejects(() => prisma.moderacion_eventos.create({ data: { ...base, admin_id: null, admin_permiso_id: null } }), "sin actor");
    await assert.rejects(() => prisma.moderacion_eventos.create({ data: { ...base, datos_nuevos: [1, 2] } }), "JSON que no es objeto");
    await assert.rejects(() => prisma.moderacion_eventos.create({ data: { ...base, operacion: "OTORGAR" } }), "operación de otra entidad");
    // Un evento con el permiso de OTRO admin viola la FK compuesta.
    await assert.rejects(() => prisma.moderacion_eventos.create({ data: { ...base, admin_id: comun.id } }), "permiso ajeno");
  });

  it("la BD rechaza auto-otorgamiento y asignación inicial sin motivo (CHECK de admin_permisos)", async () => {
    await assert.rejects(() => prisma.admin_permisos.create({ data: { usuario_id: comun.id, permiso: "MODERAR_CONTENIDO", origen: "OTORGADO_POR_ADMIN", otorgado_por: comun.id } }));
    await assert.rejects(() => prisma.admin_permisos.create({ data: { usuario_id: comun.id, permiso: "MODERAR_CONTENIDO", origen: "ASIGNACION_INICIAL", otorgado_por: null } }));
    await assert.rejects(() => prisma.admin_permisos.create({ data: { usuario_id: comun.id, permiso: "MODERAR_CONTENIDO", origen: "OTORGADO_POR_ADMIN", otorgado_por: null } }));
  });

  it("la reseña sigue ocupando su lugar único en la BD (UNIQUE) aunque esté eliminada", async () => {
    const fila = await prisma.resenas.findUniqueOrThrow({ where: { id: resenaId } });
    await assert.rejects(() =>
      prisma.resenas.create({ data: { solicitud_id: fila.solicitud_id, autor_rol: "CLIENTE", cliente_id: fila.cliente_id, trabajador_id: fila.trabajador_id, puntuacion: 5 } }),
    );
  });
});
