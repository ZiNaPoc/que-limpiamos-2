// Primero el entorno: apunta la app a la BD de pruebas antes de cargar nada más.
import { ORIGEN_PANEL } from "./soporte/entorno";

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import jwt from "jsonwebtoken";

import app from "../src/app";
import { prisma } from "../src/config/prisma";
import { hashPassword, versionDePassword } from "../src/shared/auth/password";
import { type FotoProduccion, limpiarBdDePruebas, prepararBdDePruebas } from "./soporte/bd";
import { cookieDe, crearPeticiones, iniciarServidor, type Respuesta } from "./soporte/http";

/**
 * Fase 2 — autenticación por audiencia (cliente, trabajador, admin) y aislamiento entre ellas.
 * Corre contra la BD de pruebas (queLimpiamos_proyecto) con datos creados aquí; producción
 * solo se lee y al final se comprueba que no cambió.
 */

const EMISOR = "que-limpiamos";
// Contraseñas de PRUEBA: solo existen en la BD de pruebas durante esta ejecución.
const PASS_ADMIN = "admin-pruebas-1234";
const PASS_CLIENTE = "cliente-pruebas-1234";
const PASS_TRABAJADOR = "trabajador-pruebas-1234";

let foto: FotoProduccion | undefined;
let servidor: Awaited<ReturnType<typeof iniciarServidor>> | undefined;
let pedir: ReturnType<typeof crearPeticiones>;
const ids = { admin: 0, clienteSuspendido: 0, trabajadorSinPassword: 0 };

/** Token firmado a mano, para probar audiencias, secretos y expiración. */
function tokenManual(o: { secreto: string; aud: string; sub: number; pwv: string; exp?: number }): string {
  return jwt.sign({ pwv: o.pwv, ...(o.exp ? { exp: o.exp } : {}) }, o.secreto, {
    algorithm: "HS256",
    audience: o.aud,
    issuer: EMISOR,
    subject: String(o.sub),
    ...(o.exp ? {} : { expiresIn: 3600 }),
  });
}
const secreto = (a: "CLIENTE" | "TRABAJADOR" | "ADMIN") => process.env[`JWT_SECRET_${a}`] as string;

function sinSecretos(r: Respuesta) {
  assert.ok(!/password/i.test(r.texto), `la respuesta expone datos de contraseña: ${r.texto}`);
}

before(async () => {
  foto = await prepararBdDePruebas();
  const admin = await prisma.usuarios.create({
    data: { rol: "ADMIN", nombre_completo: "Admin Pruebas", correo: "admin@pruebas.test", password_hash: await hashPassword(PASS_ADMIN) },
  });
  ids.admin = admin.id;
  const suspendido = await prisma.usuarios.create({
    data: {
      nombre_completo: "Cliente Suspendido", correo: "suspendido@pruebas.test", telefono: "9990000001",
      password_hash: await hashPassword(PASS_CLIENTE), estado_cuenta: "SUSPENDIDA",
    },
  });
  ids.clienteSuspendido = suspendido.id;
  // Trabajador dado de alta sin contraseña (como los que existían antes de D1).
  const sinPassword = await prisma.trabajadores.create({
    data: { nombre_completo: "Trabajador Sin Contraseña", correo: "sinpass@pruebas.test", telefono: "9990000002", direccion: "Calle 1" },
  });
  ids.trabajadorSinPassword = sinPassword.id;
  servidor = await iniciarServidor(app);
  pedir = crearPeticiones(servidor.base);
});

after(async () => {
  await servidor?.cerrar();
  await prisma.$disconnect().catch(() => undefined);
  const resultado = await limpiarBdDePruebas(foto);
  assert.deepEqual(resultado, { tablasRestantes: [], estructuraDistinta: [], datosDistintos: [] }, "BD de pruebas sin vaciar o producción modificada");
});

describe("Cliente — /api/cliente/auth", () => {
  let token = "";
  let id = 0;

  it("registro: crea un CLIENTE (aunque el body diga rol ADMIN), guarda bcrypt y devuelve token", async () => {
    const r = await pedir("POST", "/api/cliente/auth/registro", {
      cuerpo: { nombre: "  Ana   López ", correo: "Ana@Pruebas.Test", telefono: "+52 998 123 4567", password: PASS_CLIENTE, rol: "ADMIN" },
    });
    assert.equal(r.status, 201, r.texto);
    sinSecretos(r);
    assert.equal(typeof r.cuerpo.token, "string");
    assert.deepEqual(
      { nombre: r.cuerpo.cliente.nombre, correo: r.cuerpo.cliente.correo, telefono: r.cuerpo.cliente.telefono, rol: r.cuerpo.cliente.rol },
      { nombre: "Ana López", correo: "ana@pruebas.test", telefono: "9981234567", rol: "CLIENTE" },
    );
    // Campos que exige el modelo ApiUser de la app del cliente.
    for (const campo of ["id", "nombre", "correo", "rol", "telefono"]) assert.ok(campo in r.cuerpo.cliente, campo);
    token = r.cuerpo.token;
    id = r.cuerpo.cliente.id;
    const guardado = await prisma.usuarios.findUniqueOrThrow({ where: { id } });
    assert.match(guardado.password_hash, /^\$2[aby]\$/);
    assert.notEqual(guardado.password_hash, PASS_CLIENTE);
  });

  it("registro: valida los campos (400 DATOS_INVALIDOS)", async () => {
    const base = { nombre: "Beto", correo: "beto@pruebas.test", telefono: "9981112233", password: PASS_CLIENTE };
    for (const [cambio, motivo] of [
      [{ telefono: undefined }, "sin teléfono"],
      [{ telefono: "998111223" }, "teléfono de 9 dígitos"],
      [{ correo: "no-es-correo" }, "correo inválido"],
      [{ password: "corta" }, "contraseña corta"],
      [{ password: "x".repeat(73) }, "contraseña de más de 72 bytes"],
      [{ nombre: " " }, "nombre vacío"],
    ] as const) {
      const r = await pedir("POST", "/api/cliente/auth/registro", { cuerpo: { ...base, ...cambio } });
      assert.equal(r.status, 400, `${motivo}: ${r.texto}`);
      assert.equal(r.cuerpo.codigo, "DATOS_INVALIDOS", motivo);
    }
    const arreglo = await pedir("POST", "/api/cliente/auth/registro", { cuerpo: [base] });
    assert.equal(arreglo.status, 400);
    const malFormado = await pedir("POST", "/api/cliente/auth/registro", { crudo: "{no es json" });
    assert.equal(malFormado.cuerpo.codigo, "JSON_INVALIDO");
  });

  it("registro: correo (sin distinguir mayúsculas) o teléfono repetidos → 409", async () => {
    const correo = await pedir("POST", "/api/cliente/auth/registro", {
      cuerpo: { nombre: "Otra", correo: "ANA@pruebas.test", telefono: "9980000000", password: PASS_CLIENTE },
    });
    assert.equal(correo.status, 409);
    assert.equal(correo.cuerpo.codigo, "CORREO_EN_USO");
    const tel = await pedir("POST", "/api/cliente/auth/registro", {
      cuerpo: { nombre: "Otra", correo: "otra@pruebas.test", telefono: "998-123-4567", password: PASS_CLIENTE },
    });
    assert.equal(tel.status, 409);
    assert.equal(tel.cuerpo.codigo, "TELEFONO_EN_USO");
  });

  it("registro: dos registros simultáneos con el mismo correo → uno 201 y otro 409", async () => {
    const cuerpo = (tel: string) => ({ nombre: "Doble", correo: "doble@pruebas.test", telefono: tel, password: PASS_CLIENTE });
    const [a, b] = await Promise.all([
      pedir("POST", "/api/cliente/auth/registro", { cuerpo: cuerpo("9983330001") }),
      pedir("POST", "/api/cliente/auth/registro", { cuerpo: cuerpo("9983330002") }),
    ]);
    assert.deepEqual([a.status, b.status].sort(), [201, 409]);
    assert.equal([a, b].find((r) => r.status === 409)?.cuerpo.codigo, "CORREO_EN_USO");
    assert.equal(await prisma.usuarios.count({ where: { correo: "doble@pruebas.test" } }), 1);
  });

  it("login con correo o con teléfono; credenciales malas → 401 con el mismo mensaje", async () => {
    const porCorreo = await pedir("POST", "/api/cliente/auth/login", { cuerpo: { correo: "ANA@pruebas.test", password: PASS_CLIENTE } });
    assert.equal(porCorreo.status, 200, porCorreo.texto);
    sinSecretos(porCorreo);
    const porTelefono = await pedir("POST", "/api/cliente/auth/login", { cuerpo: { telefono: "9981234567", password: PASS_CLIENTE } });
    assert.equal(porTelefono.status, 200, porTelefono.texto);
    const malPassword = await pedir("POST", "/api/cliente/auth/login", { cuerpo: { correo: "ana@pruebas.test", password: "incorrecta-123" } });
    const noExiste = await pedir("POST", "/api/cliente/auth/login", { cuerpo: { correo: "nadie@pruebas.test", password: "incorrecta-123" } });
    assert.equal(malPassword.status, 401);
    assert.equal(noExiste.status, 401);
    assert.deepEqual(malPassword.cuerpo, noExiste.cuerpo, "no debe revelar si la cuenta existe");
    // Un ADMIN no entra por el login de clientes.
    const admin = await pedir("POST", "/api/cliente/auth/login", { cuerpo: { correo: "admin@pruebas.test", password: PASS_ADMIN } });
    assert.equal(admin.status, 401);
  });

  it("me: con token 200; sin token, malformado, expirado o con alg none → 401", async () => {
    const ok = await pedir("GET", "/api/cliente/auth/me", { token });
    assert.equal(ok.status, 200);
    assert.equal(ok.cuerpo.cliente.id, id);
    sinSecretos(ok);
    assert.equal((await pedir("GET", "/api/cliente/auth/me")).cuerpo.codigo, "NO_AUTENTICADO");
    assert.equal((await pedir("GET", "/api/cliente/auth/me", { token: "abc.def.ghi" })).cuerpo.codigo, "TOKEN_INVALIDO");
    const cuenta = await prisma.usuarios.findUniqueOrThrow({ where: { id } });
    const expirado = tokenManual({ secreto: secreto("CLIENTE"), aud: "cliente", sub: id, pwv: versionDePassword(cuenta.password_hash), exp: Math.floor(Date.now() / 1000) - 60 });
    const rExp = await pedir("GET", "/api/cliente/auth/me", { token: expirado });
    assert.equal(rExp.status, 401);
    assert.equal(rExp.cuerpo.codigo, "SESION_EXPIRADA");
    const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString("base64url");
    const sinFirma = `${b64({ alg: "none", typ: "JWT" })}.${b64({ sub: String(id), aud: "cliente", iss: EMISOR, pwv: "x" })}.`;
    assert.equal((await pedir("GET", "/api/cliente/auth/me", { token: sinFirma })).status, 401);
  });

  it("cambiar contraseña: exige la actual, invalida el token viejo y entrega uno nuevo", async () => {
    const mal = await pedir("POST", "/api/cliente/auth/cambiar-password", {
      token, cuerpo: { password_actual: "no-es-esta-123", password_nueva: "nueva-pruebas-1234" },
    });
    assert.equal(mal.status, 400);
    assert.equal(mal.cuerpo.codigo, "PASSWORD_ACTUAL_INCORRECTA");
    const r = await pedir("POST", "/api/cliente/auth/cambiar-password", {
      token, cuerpo: { password_actual: PASS_CLIENTE, password_nueva: "nueva-pruebas-1234" },
    });
    assert.equal(r.status, 200, r.texto);
    const viejo = await pedir("GET", "/api/cliente/auth/me", { token });
    assert.equal(viejo.status, 401);
    assert.equal(viejo.cuerpo.codigo, "SESION_EXPIRADA");
    assert.equal((await pedir("GET", "/api/cliente/auth/me", { token: r.cuerpo.token })).status, 200);
    const login = await pedir("POST", "/api/cliente/auth/login", { cuerpo: { correo: "ana@pruebas.test", password: "nueva-pruebas-1234" } });
    assert.equal(login.status, 200);
    token = r.cuerpo.token;
  });

  it("cuenta suspendida: no inicia sesión y su token deja de servir (403)", async () => {
    const login = await pedir("POST", "/api/cliente/auth/login", { cuerpo: { telefono: "9990000001", password: PASS_CLIENTE } });
    assert.equal(login.status, 403);
    assert.equal(login.cuerpo.codigo, "CUENTA_SUSPENDIDA");
    await prisma.usuarios.update({ where: { id }, data: { estado_cuenta: "SUSPENDIDA" } });
    const me = await pedir("GET", "/api/cliente/auth/me", { token });
    assert.equal(me.status, 403);
    await prisma.usuarios.update({ where: { id }, data: { estado_cuenta: "ACTIVA" } });
  });

  it("logout: 204 (la app borra el token)", async () => {
    assert.equal((await pedir("POST", "/api/cliente/auth/logout", { token })).status, 204);
  });
});

describe("Trabajador — /api/trabajador/auth", () => {
  let token = "";

  it("registro propio: 201 con token; exige dirección", async () => {
    const sinDireccion = await pedir("POST", "/api/trabajador/auth/registro", {
      cuerpo: { nombre: "Tere", correo: "tere@pruebas.test", telefono: "9982223344", password: PASS_TRABAJADOR },
    });
    assert.equal(sinDireccion.status, 400);
    const r = await pedir("POST", "/api/trabajador/auth/registro", {
      cuerpo: { nombre: "Tere Díaz", correo: "tere@pruebas.test", telefono: "9982223344", direccion: "Av. Tulum 10", password: PASS_TRABAJADOR },
    });
    assert.equal(r.status, 201, r.texto);
    sinSecretos(r);
    assert.equal(r.cuerpo.trabajador.estado, "ACTIVO");
    // Campos que exige el modelo ApiUser de la app del trabajador.
    for (const campo of ["id", "nombre", "correo", "rol", "telefono"]) assert.ok(campo in r.cuerpo.trabajador, campo);
    assert.equal(r.cuerpo.trabajador.rol, "TRABAJADOR");
    token = r.cuerpo.token;
  });

  it("registro: correo o teléfono repetidos → 409", async () => {
    const r = await pedir("POST", "/api/trabajador/auth/registro", {
      cuerpo: { nombre: "Otra", correo: "TERE@pruebas.test", telefono: "9989998877", direccion: "Calle 2 #3", password: PASS_TRABAJADOR },
    });
    assert.equal(r.cuerpo.codigo, "CORREO_EN_USO");
    const t = await pedir("POST", "/api/trabajador/auth/registro", {
      cuerpo: { nombre: "Otra", correo: "otra2@pruebas.test", telefono: "9982223344", direccion: "Calle 2 #3", password: PASS_TRABAJADOR },
    });
    assert.equal(t.cuerpo.codigo, "TELEFONO_EN_USO");
  });

  it("login, me y cambio de contraseña", async () => {
    const login = await pedir("POST", "/api/trabajador/auth/login", { cuerpo: { telefono: "998 222 3344", password: PASS_TRABAJADOR } });
    assert.equal(login.status, 200, login.texto);
    const me = await pedir("GET", "/api/trabajador/auth/me", { token: login.cuerpo.token });
    assert.equal(me.status, 200);
    assert.equal(me.cuerpo.trabajador.correo, "tere@pruebas.test");
    sinSecretos(me);
    const cambio = await pedir("POST", "/api/trabajador/auth/cambiar-password", {
      token, cuerpo: { password_actual: PASS_TRABAJADOR, password_nueva: "nueva-trab-1234" },
    });
    assert.equal(cambio.status, 200);
    assert.equal((await pedir("GET", "/api/trabajador/auth/me", { token })).status, 401, "el token viejo debe dejar de valer");
    token = cambio.cuerpo.token;
    assert.equal((await pedir("POST", "/api/trabajador/auth/logout", { token })).status, 204);
  });

  it("un trabajador sin contraseña asignada no puede iniciar sesión ni usar un token", async () => {
    const r = await pedir("POST", "/api/trabajador/auth/login", { cuerpo: { correo: "sinpass@pruebas.test", password: "cualquier-cosa-1" } });
    assert.equal(r.status, 401);
    assert.equal(r.cuerpo.codigo, "CREDENCIALES_INVALIDAS");
    const falso = tokenManual({ secreto: secreto("TRABAJADOR"), aud: "trabajador", sub: ids.trabajadorSinPassword, pwv: "x" });
    assert.equal((await pedir("GET", "/api/trabajador/auth/me", { token: falso })).status, 401);
  });
});

describe("Admin — /api/admin/auth (cookie httpOnly) y alias /api/auth/admin", () => {
  let cookie = "";

  it("login: 200 { usuario }, cookie httpOnly y sin token en el body", async () => {
    const r = await pedir("POST", "/api/admin/auth/login", { origen: ORIGEN_PANEL, cuerpo: { correo: "admin@pruebas.test", password: PASS_ADMIN } });
    assert.equal(r.status, 200, r.texto);
    sinSecretos(r);
    assert.deepEqual(r.cuerpo, { usuario: { id: ids.admin, nombre: "Admin Pruebas", correo: "admin@pruebas.test", rol: "ADMIN" } });
    const c = cookieDe(r, "ql_admin");
    assert.ok(c && c.par.length > "ql_admin=".length, "falta la cookie de sesión");
    assert.match(c.atributos, /HttpOnly/i);
    assert.match(c.atributos, /SameSite=Lax/i);
    assert.match(c.atributos, /Path=\//i);
    cookie = c.par;
  });

  it("session con la cookie → 200; sin cookie → 401", async () => {
    const ok = await pedir("GET", "/api/admin/auth/session", { cookie });
    assert.equal(ok.status, 200);
    assert.equal(ok.cuerpo.usuario.rol, "ADMIN");
    assert.equal((await pedir("GET", "/api/admin/auth/me", { cookie })).status, 200);
    assert.equal((await pedir("GET", "/api/admin/auth/session")).status, 401);
  });

  it("alias /api/auth/admin/login (el que usa el panel hoy) funciona igual", async () => {
    const r = await pedir("POST", "/api/auth/admin/login", { origen: ORIGEN_PANEL, cuerpo: { correo: "admin@pruebas.test", password: PASS_ADMIN } });
    assert.equal(r.status, 200, r.texto);
    assert.ok(cookieDe(r, "ql_admin"));
    assert.equal((await pedir("GET", "/api/auth/admin/session", { cookie })).status, 200);
  });

  it("CSRF: sin Origin o con un Origin ajeno → 403 ORIGEN_NO_PERMITIDO", async () => {
    const credenciales = { correo: "admin@pruebas.test", password: PASS_ADMIN };
    const sinOrigen = await pedir("POST", "/api/admin/auth/login", { cuerpo: credenciales });
    assert.equal(sinOrigen.status, 403);
    assert.equal(sinOrigen.cuerpo.codigo, "ORIGEN_NO_PERMITIDO");
    const ajeno = await pedir("POST", "/api/auth/admin/login", { origen: "https://sitio-ajeno.example", cuerpo: credenciales });
    assert.equal(ajeno.status, 403);
    const logoutAjeno = await pedir("POST", "/api/admin/auth/logout", { cookie, origen: "https://sitio-ajeno.example" });
    assert.equal(logoutAjeno.status, 403);
  });

  it("un CLIENTE no entra al panel; credenciales malas → 401", async () => {
    const cliente = await pedir("POST", "/api/admin/auth/login", { origen: ORIGEN_PANEL, cuerpo: { correo: "ana@pruebas.test", password: "nueva-pruebas-1234" } });
    assert.equal(cliente.status, 401);
    const mal = await pedir("POST", "/api/admin/auth/login", { origen: ORIGEN_PANEL, cuerpo: { correo: "admin@pruebas.test", password: "incorrecta-123" } });
    assert.equal(mal.status, 401);
    assert.deepEqual(cliente.cuerpo, mal.cuerpo);
  });

  it("logout: 204 y borra la cookie", async () => {
    const r = await pedir("POST", "/api/admin/auth/logout", { cookie, origen: ORIGEN_PANEL });
    assert.equal(r.status, 204);
    const c = cookieDe(r, "ql_admin");
    assert.ok(c, "debe enviar Set-Cookie para borrarla");
    assert.match(c.atributos, /Expires=Thu, 01 Jan 1970/i);
  });
});

describe("Aislamiento entre audiencias", () => {
  let tokenCliente = "";
  let tokenTrabajador = "";
  let cookieAdmin = "";
  let idCliente = 0;
  let idTrabajador = 0;

  before(async () => {
    const c = await pedir("POST", "/api/cliente/auth/login", { cuerpo: { correo: "ana@pruebas.test", password: "nueva-pruebas-1234" } });
    tokenCliente = c.cuerpo.token;
    idCliente = c.cuerpo.cliente.id;
    const t = await pedir("POST", "/api/trabajador/auth/login", { cuerpo: { correo: "tere@pruebas.test", password: "nueva-trab-1234" } });
    tokenTrabajador = t.cuerpo.token;
    idTrabajador = t.cuerpo.trabajador.id;
    const a = await pedir("POST", "/api/admin/auth/login", { origen: ORIGEN_PANEL, cuerpo: { correo: "admin@pruebas.test", password: PASS_ADMIN } });
    cookieAdmin = cookieDe(a, "ql_admin")?.par ?? "";
    assert.ok(tokenCliente && tokenTrabajador && cookieAdmin);
  });

  it("el token de cliente no sirve en trabajador ni en admin", async () => {
    assert.equal((await pedir("GET", "/api/trabajador/auth/me", { token: tokenCliente })).status, 401);
    assert.equal((await pedir("GET", "/api/admin/auth/session", { cookie: `ql_admin=${tokenCliente}` })).status, 401);
  });

  it("el token de trabajador no sirve en cliente ni en admin", async () => {
    assert.equal((await pedir("GET", "/api/cliente/auth/me", { token: tokenTrabajador })).status, 401);
    assert.equal((await pedir("GET", "/api/admin/auth/session", { cookie: `ql_admin=${tokenTrabajador}` })).status, 401);
  });

  it("la cookie de admin no sirve como Bearer en cliente ni en trabajador", async () => {
    const valor = cookieAdmin.slice("ql_admin=".length);
    assert.equal((await pedir("GET", "/api/cliente/auth/me", { token: valor })).status, 401);
    assert.equal((await pedir("GET", "/api/trabajador/auth/me", { token: valor })).status, 401);
  });

  it("se revisan secreto y `aud` por separado: con el secreto correcto pero otra audiencia → 401", async () => {
    const cuenta = await prisma.usuarios.findUniqueOrThrow({ where: { id: idCliente } });
    const pwv = versionDePassword(cuenta.password_hash);
    // Secreto de cliente, aud trabajador → lo rechaza el cliente (aud) y el trabajador (secreto).
    const audCruzada = tokenManual({ secreto: secreto("CLIENTE"), aud: "trabajador", sub: idCliente, pwv });
    assert.equal((await pedir("GET", "/api/cliente/auth/me", { token: audCruzada })).status, 401);
    assert.equal((await pedir("GET", "/api/trabajador/auth/me", { token: audCruzada })).status, 401);
    // Control: el mismo token con aud cliente sí vale.
    const valido = tokenManual({ secreto: secreto("CLIENTE"), aud: "cliente", sub: idCliente, pwv });
    assert.equal((await pedir("GET", "/api/cliente/auth/me", { token: valido })).status, 200);
  });

  it("se revisa el rol en la BD: un token de cliente válido con el id del ADMIN → 401", async () => {
    const admin = await prisma.usuarios.findUniqueOrThrow({ where: { id: ids.admin } });
    const t = tokenManual({ secreto: secreto("CLIENTE"), aud: "cliente", sub: ids.admin, pwv: versionDePassword(admin.password_hash) });
    assert.equal((await pedir("GET", "/api/cliente/auth/me", { token: t })).status, 401);
    // Y al revés: un token de admin válido con el id de un CLIENTE no abre el panel.
    const cliente = await prisma.usuarios.findUniqueOrThrow({ where: { id: idCliente } });
    const a = tokenManual({ secreto: secreto("ADMIN"), aud: "admin", sub: idCliente, pwv: versionDePassword(cliente.password_hash) });
    assert.equal((await pedir("GET", "/api/admin/auth/session", { cookie: `ql_admin=${a}` })).status, 401);
  });

  it("la cookie de admin no autentica en las rutas de cliente (que solo leen Bearer)", async () => {
    assert.equal((await pedir("GET", "/api/cliente/auth/me", { cookie: cookieAdmin })).status, 401);
  });
});
