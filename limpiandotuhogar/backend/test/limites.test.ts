// Primero los límites bajos y el entorno: apuntan la app a la BD de pruebas antes de cargar nada.
import "./soporte/limites-bajos";
import { ORIGEN_PANEL } from "./soporte/entorno";

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

import app from "../src/app";
import { prisma } from "../src/config/prisma";
import { reloj } from "../src/shared/auth/intentos";
import { hashPassword } from "../src/shared/auth/password";
import { type FotoProduccion, limpiarBdDePruebas, prepararBdDePruebas } from "./soporte/bd";
import { crearPeticiones, iniciarServidor } from "./soporte/http";

/**
 * Límite de intentos por HTTP: bloqueo progresivo por cuenta e identificador (sin revelar si
 * la cuenta existe) y límite por IP. Reloj simulado para no esperar minutos reales.
 */

const PASS = "pruebas-limites-1234";
let foto: FotoProduccion | undefined;
let servidor: Awaited<ReturnType<typeof iniciarServidor>> | undefined;
let pedir: ReturnType<typeof crearPeticiones>;
const relojOriginal = reloj.ahora;
let ahora = Date.now();
const avanzar = (segundos: number) => {
  ahora += segundos * 1000;
};

before(async () => {
  foto = await prepararBdDePruebas();
  reloj.ahora = () => ahora;
  const hash = await hashPassword(PASS);
  await prisma.usuarios.create({ data: { nombre_completo: "Cliente Límites", correo: "limites@pruebas.test", telefono: "9970000001", password_hash: hash } });
  await prisma.usuarios.create({ data: { rol: "ADMIN", nombre_completo: "Admin Límites", correo: "admin.limites@pruebas.test", password_hash: hash } });
  await prisma.trabajadores.create({
    data: { nombre_completo: "Trabajador Límites", correo: "trab.limites@pruebas.test", telefono: "9970000002", direccion: "Calle 1", password_hash: hash },
  });
  servidor = await iniciarServidor(app);
  pedir = crearPeticiones(servidor.base);
});

after(async () => {
  reloj.ahora = relojOriginal;
  await servidor?.cerrar();
  await prisma.$disconnect().catch(() => undefined);
  const resultado = await limpiarBdDePruebas(foto);
  assert.deepEqual(resultado, { tablasRestantes: [], estructuraDistinta: [], datosDistintos: [] });
});

const loginCliente = (cuerpo: Record<string, string>) => pedir("POST", "/api/cliente/auth/login", { cuerpo });

describe("Bloqueo progresivo por cuenta e identificador", () => {
  it("cliente: 5 fallos → 401; el 6.º intento se bloquea aunque la contraseña sea CORRECTA (429 + Retry-After)", async () => {
    for (let i = 0; i < 5; i++) {
      const r = await loginCliente({ correo: "limites@pruebas.test", password: "incorrecta-000" });
      assert.equal(r.status, 401, `intento ${i + 1}`);
    }
    const bloqueado = await loginCliente({ correo: "limites@pruebas.test", password: "incorrecta-000" });
    assert.equal(bloqueado.status, 401, "el 6.º fallo todavía responde 401 y activa el bloqueo");
    const conPasswordCorrecta = await loginCliente({ correo: "limites@pruebas.test", password: PASS });
    assert.equal(conPasswordCorrecta.status, 429);
    assert.equal(conPasswordCorrecta.cuerpo.codigo, "DEMASIADOS_INTENTOS");
    assert.equal(conPasswordCorrecta.headers.get("retry-after"), "60");
  });

  it("al vencer el bloqueo entra con la contraseña correcta y el contador se reinicia", async () => {
    avanzar(61);
    const ok = await loginCliente({ correo: "limites@pruebas.test", password: PASS });
    assert.equal(ok.status, 200, ok.texto);
    const unFallo = await loginCliente({ correo: "limites@pruebas.test", password: "incorrecta-000" });
    assert.equal(unFallo.status, 401, "tras el éxito vuelve a tener intentos gratis");
    await loginCliente({ correo: "limites@pruebas.test", password: PASS }); // reinicia de nuevo
  });

  it("no revela si la cuenta existe: un correo inexistente recibe exactamente las mismas respuestas", async () => {
    const respuestas = async (correo: string) => {
      const r: { status: number; cuerpo: unknown; retry: string | null }[] = [];
      for (let i = 0; i < 7; i++) {
        const x = await loginCliente({ correo, password: "incorrecta-000" });
        r.push({ status: x.status, cuerpo: x.cuerpo, retry: x.headers.get("retry-after") });
      }
      return r;
    };
    const existe = await respuestas("limites@pruebas.test");
    const noExiste = await respuestas("nadie.limites@pruebas.test");
    assert.deepEqual(existe, noExiste);
    assert.deepEqual(existe.map((x) => x.status), [401, 401, 401, 401, 401, 401, 429]);
    avanzar(61);
    await loginCliente({ correo: "limites@pruebas.test", password: PASS });
  });

  it("alternar correo y teléfono de la misma cuenta no da más intentos", async () => {
    for (let i = 0; i < 3; i++) await loginCliente({ correo: "limites@pruebas.test", password: "incorrecta-000" });
    for (let i = 0; i < 3; i++) await loginCliente({ telefono: "9970000001", password: "incorrecta-000" });
    const r = await loginCliente({ telefono: "9970000001", password: PASS });
    assert.equal(r.status, 429);
    avanzar(61);
    assert.equal((await loginCliente({ telefono: "9970000001", password: PASS })).status, 200);
  });

  it("los bloqueos crecen (1 → 5 → 15 min…) y nunca pasan de 60 min", async () => {
    for (let i = 0; i < 5; i++) await loginCliente({ correo: "limites@pruebas.test", password: "incorrecta-000" });
    const esperas: number[] = [];
    for (let i = 0; i < 6; i++) {
      await loginCliente({ correo: "limites@pruebas.test", password: "incorrecta-000" });
      const r = await loginCliente({ correo: "limites@pruebas.test", password: PASS });
      assert.equal(r.status, 429);
      const espera = Number(r.headers.get("retry-after"));
      esperas.push(Math.round(espera / 60));
      avanzar(espera + 1);
    }
    assert.deepEqual(esperas, [1, 5, 15, 30, 60, 60]);
    assert.equal((await loginCliente({ correo: "limites@pruebas.test", password: PASS })).status, 200, "nunca queda bloqueada para siempre");
  });

  it("trabajador: mismo mecanismo (5 gratis)", async () => {
    for (let i = 0; i < 6; i++) await pedir("POST", "/api/trabajador/auth/login", { cuerpo: { correo: "trab.limites@pruebas.test", password: "incorrecta-000" } });
    const r = await pedir("POST", "/api/trabajador/auth/login", { cuerpo: { correo: "trab.limites@pruebas.test", password: PASS } });
    assert.equal(r.status, 429);
    avanzar(61);
  });

  it("panel: más estricto (3 fallos gratis)", async () => {
    const login = (password: string) =>
      pedir("POST", "/api/admin/auth/login", { origen: ORIGEN_PANEL, cuerpo: { correo: "admin.limites@pruebas.test", password } });
    for (let i = 0; i < 4; i++) assert.equal((await login("incorrecta-000")).status, 401);
    assert.equal((await login(PASS)).status, 429);
    avanzar(61);
    assert.equal((await login(PASS)).status, 200);
  });
});

describe("Límite por IP (abuso general)", () => {
  it("registro: con límite 3 por IP, el 4.º → 429 DEMASIADOS_INTENTOS con Retry-After", async () => {
    const estados: number[] = [];
    let ultimo;
    for (let i = 0; i < 4; i++) {
      ultimo = await pedir("POST", "/api/cliente/auth/registro", {
        cuerpo: { nombre: "Registro IP", correo: `ip${i}@pruebas.test`, telefono: `996000000${i}`, password: PASS },
      });
      estados.push(ultimo.status);
    }
    assert.deepEqual(estados, [201, 201, 201, 429]);
    assert.equal(ultimo?.cuerpo.codigo, "DEMASIADOS_INTENTOS");
    assert.ok(Number(ultimo?.headers.get("retry-after")) > 0);
  });
});
