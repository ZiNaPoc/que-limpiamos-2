import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { describe, it } from "node:test";

/**
 * Secretos ESTABLES: qué pasa al arrancar si faltan. Cada caso corre en un proceso aparte
 * con su propio entorno (los valores vacíos tapan lo que haya en .env). Sin BD.
 */

const RAIZ = path.resolve(__dirname, "..");
const SECRETO = (letra: string) => letra.repeat(40);
const VALIDOS = { JWT_SECRET_CLIENTE: SECRETO("a"), JWT_SECRET_TRABAJADOR: SECRETO("b"), JWT_SECRET_ADMIN: SECRETO("c") };
const VACIOS = { JWT_SECRET_CLIENTE: "", JWT_SECRET_TRABAJADOR: "", JWT_SECRET_ADMIN: "" };

function cargar(cual: string, entorno: Record<string, string>) {
  const r = spawnSync("npx", ["--no-install", "tsx", "test/soporte/cargar-config.ts", cual], {
    cwd: RAIZ,
    env: { ...process.env, NODE_ENV: "development", ...entorno },
    encoding: "utf8",
    shell: process.platform === "win32",
  });
  return { ok: r.status === 0 && r.stdout.includes("CARGADO"), salida: `${r.stdout}\n${r.stderr}` };
}

describe("Secretos JWT (servidor): nunca se generan; si faltan, no arranca", () => {
  it("sin JWT_SECRET_* → el servidor no arranca y dice cuál falta", () => {
    const r = cargar("auth", VACIOS);
    assert.equal(r.ok, false);
    assert.match(r.salida, /Falta la variable de entorno JWT_SECRET_CLIENTE/);
  });

  it("secretos iguales entre audiencias → no arranca", () => {
    const r = cargar("auth", { JWT_SECRET_CLIENTE: SECRETO("z"), JWT_SECRET_TRABAJADOR: SECRETO("z"), JWT_SECRET_ADMIN: SECRETO("z") });
    assert.equal(r.ok, false);
    assert.match(r.salida, /deben ser distintos/);
  });

  it("secreto de menos de 32 caracteres → no arranca", () => {
    const r = cargar("auth", { ...VALIDOS, JWT_SECRET_ADMIN: "corto" });
    assert.equal(r.ok, false);
    assert.match(r.salida, /al menos 32 caracteres/);
  });

  it("con los tres secretos válidos → carga", () => {
    assert.equal(cargar("auth", VALIDOS).ok, true);
  });
});

describe("Secreto de las URLs temporales de archivos", () => {
  it("en PRODUCCIÓN es obligatorio (no se genera)", () => {
    const r = cargar("almacenamiento", { NODE_ENV: "production", ALMACENAMIENTO_FIRMA_SECRETO: "" });
    assert.equal(r.ok, false);
    assert.match(r.salida, /obligatorio en producción/);
  });

  it("en desarrollo, si falta, se genera uno temporal (solo para esa ejecución)", () => {
    assert.equal(cargar("almacenamiento", { ALMACENAMIENTO_FIRMA_SECRETO: "" }).ok, true);
  });
});

describe("Demo local", () => {
  it("en PRODUCCIÓN no genera secretos JWT: falla", () => {
    const r = cargar("entorno-demo", { ...VACIOS, NODE_ENV: "production" });
    assert.equal(r.ok, false);
    assert.match(r.salida, /no se generan/);
  });

  it("en desarrollo genera secretos temporales (las sesiones no sobreviven a un reinicio)", () => {
    assert.equal(cargar("entorno-demo", VACIOS).ok, true);
  });
});
