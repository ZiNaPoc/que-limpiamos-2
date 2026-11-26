import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";

import { clavesDeIntento, ControlDeIntentos, reloj } from "../src/shared/auth/intentos";

/** Contador de intentos fallidos (sin BD, con reloj simulado). */

const original = reloj.ahora;
let ahora = 1_000_000_000_000;
reloj.ahora = () => ahora;
afterEach(() => undefined);
const avanzar = (segundos: number) => {
  ahora += segundos * 1000;
};

describe("ControlDeIntentos — bloqueo temporal progresivo", () => {
  const nuevo = () => new ControlDeIntentos({ gratis: 5, escalonesMin: [1, 5, 15, 30, 60], olvidoHoras: 24 });
  const k = ["cliente:correo:a@x.test"];

  it("5 fallos gratis; el 6.º bloquea 1 min y al vencer se puede intentar de nuevo", () => {
    const c = nuevo();
    for (let i = 0; i < 5; i++) {
      assert.equal(c.esperaSegundos(k), 0);
      c.registrarFallo(k);
    }
    assert.equal(c.esperaSegundos(k), 0, "con 5 fallos todavía no hay bloqueo");
    c.registrarFallo(k);
    assert.equal(c.esperaSegundos(k), 60);
    avanzar(61);
    assert.equal(c.esperaSegundos(k), 0);
  });

  it("los bloqueos crecen 1 → 5 → 15 → 30 → 60 min y no pasan de 60 (nunca permanente)", () => {
    const c = nuevo();
    for (let i = 0; i < 5; i++) c.registrarFallo(k);
    const esperas: number[] = [];
    for (let i = 0; i < 8; i++) {
      c.registrarFallo(k);
      const espera = c.esperaSegundos(k);
      esperas.push(espera / 60);
      avanzar(espera + 1);
    }
    assert.deepEqual(esperas, [1, 5, 15, 30, 60, 60, 60, 60]);
    assert.equal(c.esperaSegundos(k), 0, "tras el último bloqueo se puede volver a intentar");
  });

  it("un login correcto reinicia el contador", () => {
    const c = nuevo();
    for (let i = 0; i < 5; i++) c.registrarFallo(k);
    c.registrarExito(k);
    c.registrarFallo(k);
    assert.equal(c.esperaSegundos(k), 0, "tras el éxito vuelve a tener 5 intentos gratis");
  });

  it("24 h sin fallos: el contador se olvida", () => {
    const c = nuevo();
    for (let i = 0; i < 5; i++) c.registrarFallo(k);
    avanzar(24 * 3600 + 1);
    c.registrarFallo(k);
    assert.equal(c.esperaSegundos(k), 0);
  });

  it("varias claves: basta con que una esté bloqueada (correo y teléfono de la misma cuenta)", () => {
    const c = nuevo();
    const porCorreo = clavesDeIntento("cliente", { correo: "a@x.test" }, 7);
    const porTelefono = clavesDeIntento("cliente", { telefono: "9981234567" }, 7);
    for (let i = 0; i < 3; i++) c.registrarFallo(porCorreo);
    for (let i = 0; i < 3; i++) c.registrarFallo(porTelefono);
    assert.equal(c.esperaSegundos(porCorreo), 60, "la clave de la cuenta suma los 6 fallos");
    assert.equal(c.esperaSegundos(porTelefono), 60);
  });

  it("el tope de memoria descarta primero lo no bloqueado", () => {
    const c = new ControlDeIntentos({ gratis: 1, escalonesMin: [1], olvidoHoras: 24, maxClaves: 10 });
    const bloqueada = ["admin:correo:b@x.test"];
    c.registrarFallo(bloqueada);
    c.registrarFallo(bloqueada);
    for (let i = 0; i < 600; i++) c.registrarFallo([`cliente:correo:${i}@x.test`]);
    assert.ok(c.esperaSegundos(bloqueada) > 0, "la clave bloqueada se conserva");
  });
});

process.on("exit", () => {
  reloj.ahora = original;
});
