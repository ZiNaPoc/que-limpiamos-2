// Primero el entorno: apunta la app a la BD LOCAL de pruebas antes de cargar nada más.
import { ORIGEN_PANEL } from "./soporte/entorno";

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import app from "../src/app";
import { prisma } from "../src/config/prisma";
import { otorgarPermiso } from "../src/dominio/permisos";
import { type FotoProduccion, limpiarBdDePruebas, prepararBdDePruebas } from "./soporte/bd";
import { type Admin, type Cliente, crearAdmin, crearCliente, crearPropietarioYModerador, crearSolicitud, crearTrabajador } from "./soporte/fabrica";
import { crearPeticiones, iniciarServidor } from "./soporte/http";

/** Panel con datos reales (doc 27): resumen, clientes, trabajadores y catálogo. BD LOCAL de pruebas. */

let foto: FotoProduccion | undefined;
let servidor: Awaited<ReturnType<typeof iniciarServidor>> | undefined;
let pedir: ReturnType<typeof crearPeticiones>;
let propietario: Admin;
let supervisor: Admin;
let comun: Admin;
let ana: Cliente;
const adm = (a: Admin, metodo: string, ruta: string, cuerpo?: unknown) => pedir(metodo, `/api/admin${ruta}`, { cookie: a.cookie, origen: ORIGEN_PANEL, cuerpo });

before(async () => {
  foto = await prepararBdDePruebas();
  ({ propietario } = await crearPropietarioYModerador());
  supervisor = await crearAdmin("Supervisor Plataforma");
  comun = await crearAdmin("Admin Común");
  await otorgarPermiso(propietario.id, { usuarioId: supervisor.id, permiso: "SUPERVISAR_SOLICITUDES", motivo: "Prueba" });
  ana = await crearCliente("Ana Plataforma");
  await crearTrabajador("Tere Plataforma");
  await prisma.especialidades.create({ data: { nombre: "General (plataforma)" } });
  servidor = await iniciarServidor(app);
  pedir = crearPeticiones(servidor.base);
});

after(async () => {
  await servidor?.cerrar();
  await prisma.$disconnect().catch(() => undefined);
  const r = await limpiarBdDePruebas(foto);
  assert.deepEqual(r.tablasRestantes, [], "BD de pruebas sin vaciar");
});

describe("Resumen, clientes y trabajadores", () => {
  it("el resumen lo ve cualquier admin; sin sesión 401", async () => {
    const r = await adm(comun, "GET", "/resumen");
    assert.equal(r.status, 200, r.texto);
    assert.ok(r.cuerpo.clientes.total >= 1);
    assert.ok("requierenAtencion" in r.cuerpo.solicitudes);
    assert.equal((await pedir("GET", "/api/admin/resumen")).status, 401);
  });

  it("clientes y trabajadores: 403 sin supervisión; el supervisor y el propietario los ven", async () => {
    assert.equal((await adm(comun, "GET", "/clientes")).status, 403);
    assert.equal((await adm(comun, "GET", "/trabajadores")).status, 403);
    const c = await adm(supervisor, "GET", "/clientes?q=Ana");
    assert.equal(c.status, 200, c.texto);
    assert.equal(c.cuerpo.clientes[0].nombre, "Ana Plataforma");
    assert.equal(c.cuerpo.clientes[0].solicitudes.total, 0);
    const t = await adm(propietario, "GET", "/trabajadores");
    assert.equal(t.status, 200);
    assert.ok(t.cuerpo.trabajadores.some((x: { nombre: string; disponibleParaSolicitudes: boolean }) => x.nombre === "Tere Plataforma" && x.disponibleParaSolicitudes === false));
  });
});

describe("Catálogo", () => {
  it("crear, duplicado 409, validación 400 y desactivar: deja de verse en la app", async () => {
    const esp = (await prisma.especialidades.findFirstOrThrow({ where: { nombre: "General (plataforma)" } })).id;
    const nuevo = { nombre: "Limpieza de prueba plataforma", descripcion: "Servicio de prueba", precioBase: 450, duracionMin: 120, especialidadIds: [esp] };
    const c = await adm(comun, "POST", "/catalogo/servicios", nuevo);
    assert.equal(c.status, 201, c.texto);
    assert.equal((await adm(comun, "POST", "/catalogo/servicios", nuevo)).cuerpo.codigo, "NOMBRE_DUPLICADO");
    assert.equal((await adm(comun, "POST", "/catalogo/servicios", { ...nuevo, nombre: "Otro", precioBase: -1 })).status, 400);
    assert.equal((await adm(comun, "POST", "/catalogo/servicios", { ...nuevo, nombre: "Otro", especialidadIds: [] })).status, 400);
    const enApp = async () => (await pedir("GET", "/api/cliente/catalogo", { token: ana.token })).cuerpo.servicios.some((s: { id: number }) => s.id === c.cuerpo.id);
    assert.equal(await enApp(), true);
    assert.equal((await adm(comun, "PATCH", `/catalogo/servicios/${c.cuerpo.id}`, { estado: "INACTIVO" })).status, 200);
    assert.equal(await enApp(), false, "un servicio inactivo no se ofrece");
    assert.equal((await adm(comun, "PATCH", "/catalogo/servicios/999999", { estado: "ACTIVO" })).status, 404);
  });

  it("cambiar el precio no cambia las solicitudes anteriores (copia)", async () => {
    const id = await crearSolicitud({ clienteId: ana.id, estado: "REALIZADO" });
    const antes = await prisma.solicitudes.findUniqueOrThrow({ where: { id }, include: { servicios: true } });
    await adm(comun, "PATCH", `/catalogo/servicios/${antes.servicio_id}`, { precioBase: 9999 });
    const despues = await prisma.solicitudes.findUniqueOrThrow({ where: { id } });
    assert.equal(Number(despues.precio_estimado), Number(antes.precio_estimado));
  });

  it("extras y áreas: crear, editar y desactivar", async () => {
    const e = await adm(comun, "POST", "/catalogo/extras", { nombre: "Extra plataforma", precio: 120, duracionMin: 30 });
    assert.equal(e.status, 201, e.texto);
    assert.equal((await adm(comun, "PATCH", `/catalogo/extras/${e.cuerpo.id}`, { precio: 150, estado: "INACTIVO" })).status, 200);
    const a = await adm(comun, "POST", "/catalogo/areas", { nombre: "Terraza plataforma" });
    assert.equal(a.status, 201, a.texto);
    assert.equal((await adm(comun, "PATCH", `/catalogo/areas/${a.cuerpo.id}`, { estado: "INACTIVO" })).status, 200);
    const cat = (await adm(comun, "GET", "/catalogo")).cuerpo;
    assert.equal(cat.extras.find((x: { id: number }) => x.id === e.cuerpo.id).precio, 150);
    assert.equal(cat.areas.find((x: { id: number }) => x.id === a.cuerpo.id).estado, "INACTIVO");
  });
});
