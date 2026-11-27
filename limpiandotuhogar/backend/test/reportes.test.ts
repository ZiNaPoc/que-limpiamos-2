// Primero el entorno: apunta la app a la BD LOCAL de pruebas antes de cargar nada más.
import { ORIGEN_PANEL } from "./soporte/entorno";

import assert from "node:assert/strict";
import { rmSync } from "node:fs";
import { after, before, describe, it } from "node:test";

import app from "../src/app";
import { prisma } from "../src/config/prisma";
import { otorgarPermiso } from "../src/dominio/permisos";
import { relojDominio } from "../src/dominio/reloj";
import { bloqueaConfirmacionAutomatica } from "../src/dominio/reportes";
import { almacenamiento } from "../src/shared/almacenamiento";
import { type FotoProduccion, limpiarBdDePruebas, prepararBdDePruebas } from "./soporte/bd";
import {
  type Admin,
  type Cliente,
  crearAdmin,
  crearCliente,
  crearPropietarioYModerador,
  crearSolicitud,
  crearTrabajador,
  jpegDeTamano,
  pedirMultipart,
  type Trabajador,
} from "./soporte/fabrica";
import { crearPeticiones, iniciarServidor } from "./soporte/http";
import { jpegConMetadatos, PDF_MINIMO, pngConMetadatos, tieneRastrosDeGps, webpConMetadatos } from "./soporte/imagenes";

/**
 * Fase 3a — REPORTES y EVIDENCIAS (doc 20 §3): reglas, límites de fotos (5 · 8 MB · 16 MB,
 * MB decimal), tipo real, visibilidad (X6), moderación con auditoría y D57/X5. BD LOCAL.
 */

const AHORA = new Date("2026-11-25T12:00:00.000Z");
const HORA = 3600_000;
const MB = 1_000_000;
const relojOriginal = relojDominio.ahora;

let foto: FotoProduccion | undefined;
let servidor: Awaited<ReturnType<typeof iniciarServidor>> | undefined;
let pedir: ReturnType<typeof crearPeticiones>;
let carla: Cliente;
let otroCliente: Cliente;
let tomas: Trabajador;
let ajeno: Trabajador;
let moderador: Admin;
let incidencias: Admin; // doc 25 v2: resuelve el servicio de una solicitud abierta con reportes
let sinPermiso: Admin;
const s: Record<string, number> = {};
const ids: Record<string, number> = {};

before(async () => {
  foto = await prepararBdDePruebas();
  relojDominio.ahora = () => new Date(AHORA);
  carla = await crearCliente("Carla Reportante Secreta");
  otroCliente = await crearCliente("Otro Cliente");
  tomas = await crearTrabajador("Tomas Reportado");
  ajeno = await crearTrabajador("Trabajador Ajeno");
  const equipo = await crearPropietarioYModerador();
  moderador = equipo.moderador;
  incidencias = await crearAdmin("Admin Incidencias");
  await otorgarPermiso(equipo.propietario.id, { usuarioId: incidencias.id, permiso: "GESTIONAR_INCIDENCIAS_FINANZAS", motivo: "Incidencias de PRUEBA" });
  sinPermiso = await crearAdmin("Admin Sin Permiso");
  const pasada = new Date(AHORA.getTime() - 2 * HORA);
  s.enProceso = await crearSolicitud({ clienteId: carla.id, trabajadorId: tomas.id, estado: "EN_PROCESO", programada: pasada });
  s.futura = await crearSolicitud({ clienteId: carla.id, trabajadorId: tomas.id, estado: "CONFIRMADO", programada: new Date(AHORA.getTime() + 5 * HORA) });
  s.sinTrabajador = await crearSolicitud({ clienteId: carla.id, estado: "PENDIENTE", programada: pasada });
  s.disputa = await crearSolicitud({ clienteId: carla.id, trabajadorId: tomas.id, estado: "REALIZADO", programada: pasada, realizadoEn: pasada, reportePagoHasta: new Date(AHORA.getTime() + HORA) });
  s.disputaVencida = await crearSolicitud({ clienteId: carla.id, trabajadorId: tomas.id, estado: "REALIZADO", programada: pasada, realizadoEn: pasada, reportePagoHasta: new Date(AHORA.getTime() - HORA) });
  s.d57 = await crearSolicitud({ clienteId: carla.id, trabajadorId: tomas.id, estado: "EN_PROCESO", programada: pasada });
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

const reportarCliente = (solicitud: number, o: Parameters<typeof pedirMultipart>[2]) =>
  pedirMultipart(servidor!.base, `/api/cliente/solicitudes/${solicitud}/reportes`, o);
const reportarTrabajador = (solicitud: number, o: Parameters<typeof pedirMultipart>[2]) =>
  pedirMultipart(servidor!.base, `/api/trabajador/solicitudes/${solicitud}/reportes`, o);
const jpeg = (nombre = "foto.jpg", contenido = jpegConMetadatos()) => ({ nombre, contenido, tipo: "image/jpeg" });
const adminPide = (metodo: string, ruta: string, cuerpo?: unknown, quien: Admin = moderador) =>
  pedir(metodo, ruta, { cookie: quien.cookie, origen: ORIGEN_PANEL, cuerpo });

describe("Reportes: creación", () => {
  it("el cliente reporta al trabajador ANTES de que termine el servicio, con descripción y 3 fotos (JPEG, PNG, WebP)", async () => {
    const r = await reportarCliente(s.enProceso!, {
      token: carla.token,
      campos: { tipo: "INASISTENCIA", descripcion: "Llegó 2 horas tarde" },
      archivos: [jpeg(), { nombre: "b.png", contenido: pngConMetadatos(), tipo: "image/png" }, { nombre: "c.webp", contenido: webpConMetadatos(), tipo: "image/webp" }],
    });
    assert.equal(r.status, 201, r.texto);
    ids.reporteCliente = r.cuerpo.reporte.id;
    assert.equal(r.cuerpo.reporte.tipo, "INASISTENCIA");
    assert.equal(r.cuerpo.reporte.reportaA, "TRABAJADOR");
    assert.equal(r.cuerpo.reporte.evidencias.length, 3);
    const fila = await prisma.solicitud_reportes.findUniqueOrThrow({ where: { id: ids.reporteCliente } });
    assert.equal(fila.cliente_id, carla.id);
    assert.equal(fila.reportado_trabajador_id, tomas.id);
    // Fotos guardadas en privado, ligadas a reporte y solicitud, con tipo real y sin GPS.
    const evidencias = await prisma.evidencias_solicitud.findMany({ where: { reporte_id: ids.reporteCliente }, orderBy: { id: "asc" } });
    assert.deepEqual(evidencias.map((e) => [e.solicitud_id, e.aportada_por, e.tipo_mime]), [
      [s.enProceso, "CLIENTE", "image/jpeg"], [s.enProceso, "CLIENTE", "image/png"], [s.enProceso, "CLIENTE", "image/webp"],
    ]);
    for (const e of evidencias) {
      assert.match(e.sha256 ?? "", /^[0-9a-f]{64}$/);
      assert.equal(tieneRastrosDeGps(await almacenamiento().leer(e.archivo_url)), false, "se quitaron los datos de ubicación");
    }
  });

  it("el trabajador reporta al cliente SIN descripción ni fotos (JSON) → tipo OTRO", async () => {
    const r = await pedir("POST", `/api/trabajador/solicitudes/${s.enProceso}/reportes`, { token: tomas.token, cuerpo: {} });
    assert.equal(r.status, 201, r.texto);
    ids.reporteTrabajador = r.cuerpo.reporte.id;
    assert.equal(r.cuerpo.reporte.tipo, "OTRO");
    assert.equal(r.cuerpo.reporte.descripcion, null);
    assert.deepEqual(r.cuerpo.reporte.evidencias, []);
    const fila = await prisma.solicitud_reportes.findUniqueOrThrow({ where: { id: ids.reporteTrabajador } });
    assert.equal(fila.reportado_cliente_id, carla.id);
  });

  it("no exige ni crea reseñas", async () => {
    assert.equal(await prisma.resenas.count({ where: { solicitud_id: s.enProceso } }), 0);
  });

  it("antes de la hora programada (D57) → 409; sin trabajador asignado → 409; quien no es parte → 403", async () => {
    assert.equal((await reportarCliente(s.futura!, { token: carla.token })).cuerpo.codigo, "REPORTE_ANTES_DE_HORA");
    assert.equal((await reportarCliente(s.sinTrabajador!, { token: carla.token })).cuerpo.codigo, "SIN_CONTRAPARTE");
    assert.equal((await reportarCliente(s.enProceso!, { token: otroCliente.token })).status, 403);
    assert.equal((await reportarTrabajador(s.enProceso!, { token: ajeno.token })).status, 403);
  });

  it("más de 5 fotografías → 400 DEMASIADAS_FOTOS (y no se guarda nada)", async () => {
    const antes = await prisma.solicitud_reportes.count();
    const r = await reportarCliente(s.enProceso!, { token: carla.token, archivos: Array.from({ length: 6 }, (_, i) => jpeg(`f${i}.jpg`)) });
    assert.equal(r.status, 400, r.texto);
    assert.equal(r.cuerpo.codigo, "DEMASIADAS_FOTOS");
    assert.equal(await prisma.solicitud_reportes.count(), antes);
  });

  it("una foto de más de 8 MB (8 000 001 bytes) → 413; una de exactamente 8 MB → 201", async () => {
    const grande = await reportarCliente(s.enProceso!, { token: carla.token, archivos: [jpeg("g.jpg", jpegDeTamano(8 * MB + 1))] });
    assert.equal(grande.status, 413, grande.texto);
    assert.equal(grande.cuerpo.codigo, "FOTO_DEMASIADO_GRANDE");
    const justa = await reportarCliente(s.enProceso!, { token: carla.token, archivos: [jpeg("j.jpg", jpegDeTamano(8 * MB))] });
    assert.equal(justa.status, 201, justa.texto);
  });

  it("el conjunto de fotos de más de 16 MB → 413; exactamente 16 MB → 201", async () => {
    const tres = [7 * MB, 7 * MB, 2 * MB + 1].map((b, i) => jpeg(`t${i}.jpg`, jpegDeTamano(b)));
    const exceso = await reportarCliente(s.enProceso!, { token: carla.token, archivos: tres });
    assert.equal(exceso.status, 413, exceso.texto);
    assert.equal(exceso.cuerpo.codigo, "REPORTE_DEMASIADO_GRANDE");
    const justo = await reportarCliente(s.enProceso!, { token: carla.token, archivos: [8 * MB, 8 * MB].map((b, i) => jpeg(`u${i}.jpg`, jpegDeTamano(b))) });
    assert.equal(justo.status, 201, justo.texto);
  });

  it("formatos no permitidos (PDF, GIF) → 415", async () => {
    const pdf = await reportarCliente(s.enProceso!, { token: carla.token, archivos: [{ nombre: "a.pdf", contenido: PDF_MINIMO, tipo: "application/pdf" }] });
    assert.equal(pdf.status, 415);
    assert.equal(pdf.cuerpo.codigo, "TIPO_NO_PERMITIDO");
    const gif = Buffer.from("GIF89a\x01\x00\x01\x00\x00\x00\x00;", "latin1");
    assert.equal((await reportarCliente(s.enProceso!, { token: carla.token, archivos: [{ nombre: "a.gif", contenido: gif, tipo: "image/gif" }] })).status, 415);
  });

  it("archivos cuyo contenido no coincide con su extensión o tipo declarado → 415", async () => {
    // Un PDF disfrazado de JPEG.
    const disfrazado = await reportarCliente(s.enProceso!, { token: carla.token, archivos: [{ nombre: "foto.jpg", contenido: PDF_MINIMO, tipo: "image/jpeg" }] });
    assert.equal(disfrazado.status, 415);
    // Un PNG real con extensión .jpg.
    const extension = await reportarCliente(s.enProceso!, { token: carla.token, archivos: [{ nombre: "foto.jpg", contenido: pngConMetadatos(), tipo: "image/png" }] });
    assert.equal(extension.cuerpo.codigo, "EXTENSION_NO_COINCIDE");
    // Un JPEG real declarado como PNG.
    const declarado = await reportarCliente(s.enProceso!, { token: carla.token, archivos: [{ nombre: "foto.jpg", contenido: jpegConMetadatos(), tipo: "image/png" }] });
    assert.equal(declarado.cuerpo.codigo, "TIPO_NO_COINCIDE");
  });

  it("PAGO_EN_DISPUTA: solo el trabajador y dentro del plazo de reporte (D61)", async () => {
    assert.equal((await reportarCliente(s.disputa!, { token: carla.token, campos: { tipo: "PAGO_EN_DISPUTA" } })).status, 400);
    assert.equal((await reportarTrabajador(s.disputaVencida!, { token: tomas.token, campos: { tipo: "PAGO_EN_DISPUTA" } })).cuerpo.codigo, "PLAZO_REPORTE_PAGO_VENCIDO");
    const ok = await reportarTrabajador(s.disputa!, { token: tomas.token, campos: { tipo: "PAGO_EN_DISPUTA", descripcion: "No recibí el efectivo" } });
    assert.equal(ok.status, 201, ok.texto);
    ids.disputa = ok.cuerpo.reporte.id;
  });
});

describe("Reportes: visibilidad (X6)", () => {
  it("el reportante consulta su reporte y descarga sus fotos con URL temporal", async () => {
    const r = await pedir("GET", `/api/cliente/reportes/${ids.reporteCliente}`, { token: carla.token });
    assert.equal(r.status, 200);
    assert.equal(r.cuerpo.reporte.descripcion, "Llegó 2 horas tarde");
    const lista = await pedir("GET", "/api/cliente/reportes", { token: carla.token });
    assert.ok(lista.cuerpo.reportes.some((x: { id: number }) => x.id === ids.reporteCliente));
    const [primera] = r.cuerpo.reporte.evidencias;
    const url = await pedir("GET", `/api/cliente/reportes/${ids.reporteCliente}/evidencias/${primera.id}`, { token: carla.token });
    assert.equal(url.status, 200);
    const archivo = await fetch(servidor!.base + url.cuerpo.url);
    assert.equal(archivo.status, 200);
    assert.equal(archivo.headers.get("content-type"), "image/jpeg");
  });

  it("el REPORTADO no puede consultar el reporte ni saber quién lo hizo", async () => {
    assert.equal((await pedir("GET", `/api/trabajador/reportes/${ids.reporteCliente}`, { token: tomas.token })).status, 404);
    const evidencia = await prisma.evidencias_solicitud.findFirstOrThrow({ where: { reporte_id: ids.reporteCliente } });
    assert.equal((await pedir("GET", `/api/trabajador/reportes/${ids.reporteCliente}/evidencias/${evidencia.id}`, { token: tomas.token })).status, 404);
    const suyos = await pedir("GET", "/api/trabajador/reportes", { token: tomas.token });
    assert.ok(!suyos.cuerpo.reportes.some((x: { id: number }) => x.id === ids.reporteCliente));
    assert.ok(!suyos.texto.includes(carla.nombre) && !suyos.texto.includes("Llegó 2 horas tarde"));
    // Tampoco otro cliente.
    assert.equal((await pedir("GET", `/api/cliente/reportes/${ids.reporteCliente}`, { token: otroCliente.token })).status, 404);
  });

  it("el contenido de un reporte no aparece en endpoints de reseñas ni de reputación", async () => {
    for (const [ruta, token] of [
      [`/api/cliente/trabajadores/${tomas.id}/resenas`, otroCliente.token],
      ["/api/trabajador/resenas/recibidas", tomas.token],
    ] as const) {
      const r = await pedir("GET", ruta, { token });
      assert.ok(!r.texto.includes("Llegó 2 horas tarde") && !r.texto.includes(carla.nombre), ruta);
    }
  });
});

describe("Reportes: moderación con auditoría", () => {
  it("un admin SIN MODERAR_CONTENIDO recibe 403 en todas las rutas de reportes", async () => {
    for (const [metodo, ruta, cuerpo] of [
      ["GET", "/api/admin/reportes", undefined],
      ["GET", `/api/admin/reportes/${ids.reporteCliente}`, undefined],
      ["PATCH", `/api/admin/reportes/${ids.reporteCliente}`, { descripcion: "x", motivo: "x" }],
      ["POST", `/api/admin/reportes/${ids.reporteCliente}/resolucion`, { resolucion: "x" }],
      ["DELETE", `/api/admin/reportes/${ids.reporteCliente}`, { motivo: "x" }],
    ] as const) {
      const r = await adminPide(metodo, ruta, cuerpo, sinPermiso);
      assert.equal(r.status, 403, `${metodo} ${ruta}`);
    }
  });

  it("el moderador ve reportante, reportado, descripción y fotos", async () => {
    const lista = await adminPide("GET", "/api/admin/reportes");
    assert.equal(lista.status, 200);
    const r = await adminPide("GET", `/api/admin/reportes/${ids.reporteCliente}`);
    assert.equal(r.status, 200, r.texto);
    assert.deepEqual(r.cuerpo.reporte.reportante, { id: String(carla.id), rol: "CLIENTE", nombre: carla.nombre });
    assert.deepEqual(r.cuerpo.reporte.reportado, { id: String(tomas.id), rol: "TRABAJADOR", nombre: tomas.nombre });
    assert.equal(r.cuerpo.reporte.fotos.length, 3);
    assert.ok(r.cuerpo.reporte.fotos.every((f: { url: string }) => f.url.startsWith("/api/archivos/temporal/")));
  });

  it("seguimiento, edición, retiro de foto, resolución y eliminación: cada una deja SU evento", async () => {
    const id = ids.reporteCliente;
    const pasos = [
      await adminPide("POST", `/api/admin/reportes/${id}/estado`, { estado: "EN_REVISION", motivo: "Se revisa el caso" }),
      await adminPide("POST", `/api/admin/reportes/${id}/seguimiento`, { nota: "Se llamó al trabajador" }),
      await adminPide("PATCH", `/api/admin/reportes/${id}`, { descripcion: "Llegó 2 horas tarde (editado)", motivo: "Se quitan datos personales" }),
    ];
    for (const p of pasos) assert.ok(p.status === 200 || p.status === 201, p.texto);
    const [primeraFoto] = (await adminPide("GET", `/api/admin/reportes/${id}`)).cuerpo.reporte.fotos;
    const retirar = await adminPide("DELETE", `/api/admin/reportes/${id}/fotos/${primeraFoto.id}`, { motivo: "Foto con datos de otra persona" });
    assert.equal(retirar.status, 200, retirar.texto);
    // Doc 25 v2 §4 (decisión del 2026-11-25): mientras la solicitud siga abierta, la moderación NO resuelve
    // el reporte (lo hace la resolución del servicio). Ya cerrada, sí, igual que antes.
    const abierta = await adminPide("POST", `/api/admin/reportes/${id}/resolucion`, { resolucion: "Se advirtió al trabajador" });
    assert.equal(abierta.status, 409, abierta.texto);
    assert.equal(abierta.cuerpo.codigo, "RESOLUCION_DE_SERVICIO");
    await prisma.solicitudes.update({ where: { id: s.enProceso! }, data: { estado: "REALIZADO", realizado_en: new Date(AHORA) } });
    const resolver = await adminPide("POST", `/api/admin/reportes/${id}/resolucion`, { resolucion: "Se advirtió al trabajador" });
    assert.equal(resolver.status, 200, resolver.texto);
    const eventos = await prisma.moderacion_eventos.findMany({ where: { reporte_id: id }, orderBy: { id: "asc" } });
    assert.deepEqual(eventos.map((e) => e.operacion), ["CAMBIAR_ESTADO", "NOTA", "EDITAR", "EDITAR", "RESOLVER"]);
    assert.ok(eventos.every((e) => e.admin_id === moderador.id && e.admin_permiso_id !== null && e.motivo.length > 0));
    assert.deepEqual(eventos[2]!.datos_anteriores, { tipo: "INASISTENCIA", descripcion: "Llegó 2 horas tarde" });
    assert.deepEqual(eventos[2]!.datos_nuevos, { tipo: "INASISTENCIA", descripcion: "Llegó 2 horas tarde (editado)" });
    // La foto retirada sigue en la BD (borrado lógico) y el reportante ya no la ve.
    assert.ok((await prisma.evidencias_solicitud.findUniqueOrThrow({ where: { id: Number(primeraFoto.id) } })).eliminada_en);
    const propio = await pedir("GET", `/api/cliente/reportes/${id}`, { token: carla.token });
    assert.equal(propio.cuerpo.reporte.evidencias.length, 2);
  });

  it("sin motivo → 400 y nada cambia (ni se registra evento)", async () => {
    const antes = await prisma.moderacion_eventos.count();
    for (const [metodo, ruta, cuerpo] of [
      ["PATCH", `/api/admin/reportes/${ids.reporteTrabajador}`, { descripcion: "x" }],
      ["DELETE", `/api/admin/reportes/${ids.reporteTrabajador}`, {}],
      ["POST", `/api/admin/reportes/${ids.reporteTrabajador}/resolucion`, { resolucion: "   " }],
    ] as const) {
      const r = await adminPide(metodo, ruta, cuerpo);
      assert.equal(r.status, 400, `${metodo} ${ruta}: ${r.texto}`);
    }
    assert.equal(await prisma.moderacion_eventos.count(), antes);
    assert.equal((await prisma.solicitud_reportes.findUniqueOrThrow({ where: { id: ids.reporteTrabajador } })).descripcion, null);
  });

  it("un PAGO_EN_DISPUTA no se resuelve por moderación (D62, flujo financiero) → 409", async () => {
    const r = await adminPide("POST", `/api/admin/reportes/${ids.disputa}/resolucion`, { resolucion: "x" });
    assert.equal(r.status, 409);
    assert.equal(r.cuerpo.codigo, "RESOLUCION_FINANCIERA");
  });
});

describe("Confirmación automática (D57 + X5)", () => {
  it("un reporte ACTIVO bloquea; RESUELTO o ELIMINADO lógicamente deja de bloquear", async () => {
    assert.equal(await bloqueaConfirmacionAutomatica(s.d57!), false, "sin reportes");
    const uno = await reportarCliente(s.d57!, { token: carla.token, campos: { descripcion: "Uno" } });
    const dos = await reportarTrabajador(s.d57!, { token: tomas.token, campos: { descripcion: "Dos" } });
    assert.equal(uno.status, 201);
    assert.equal(dos.status, 201);
    assert.equal(await bloqueaConfirmacionAutomatica(s.d57!), true, "dos reportes activos");
    await adminPide("POST", `/api/admin/reportes/${uno.cuerpo.reporte.id}/estado`, { estado: "EN_REVISION", motivo: "Revisión" });
    assert.equal(await bloqueaConfirmacionAutomatica(s.d57!), true, "EN_REVISION sigue bloqueando (D57)");
    const eliminar = await adminPide("DELETE", `/api/admin/reportes/${uno.cuerpo.reporte.id}`, { motivo: "Reporte duplicado" });
    assert.equal(eliminar.status, 200, eliminar.texto);
    assert.equal(await bloqueaConfirmacionAutomatica(s.d57!), true, "todavía queda uno activo");
    // Doc 25 v2 §4: con la solicitud abierta, la moderación no lo resuelve (sigue bloqueando)...
    const porModeracion = await adminPide("POST", `/api/admin/reportes/${dos.cuerpo.reporte.id}/resolucion`, { resolucion: "Resuelto" });
    assert.equal(porModeracion.cuerpo.codigo, "RESOLUCION_DE_SERVICIO");
    assert.equal(await bloqueaConfirmacionAutomatica(s.d57!), true, "la moderación no lo resolvió");
    // ...lo resuelve la resolución del servicio (permiso de incidencias), que lo deja RESUELTO.
    const resolucion = await adminPide("POST", `/api/admin/solicitudes/${s.d57!}/resolucion`, { resultadoServicio: "REALIZADO", motivo: "Se revisaron las pruebas de ambas partes" }, incidencias);
    assert.equal(resolucion.status, 201, resolucion.texto);
    assert.equal((await prisma.solicitud_reportes.findUniqueOrThrow({ where: { id: dos.cuerpo.reporte.id } })).estado, "RESUELTO");
    assert.equal(await bloqueaConfirmacionAutomatica(s.d57!), false, "eliminado + resuelto ya no bloquean");
    // El eliminado se conserva con su historial.
    const fila = await prisma.solicitud_reportes.findUniqueOrThrow({ where: { id: uno.cuerpo.reporte.id } });
    assert.ok(fila.eliminado_en);
    assert.deepEqual((await prisma.moderacion_eventos.findMany({ where: { reporte_id: fila.id }, orderBy: { id: "asc" } })).map((e) => e.operacion), ["CAMBIAR_ESTADO", "ELIMINAR"]);
  });
});
