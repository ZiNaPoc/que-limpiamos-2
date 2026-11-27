/**
 * Demo LOCAL sin tocar producción ni gastar: `npm run demo:local` (Ctrl+C para detener).
 *
 *  - BD: quelimpiamos_demo en el TiDB LOCAL (Docker, 127.0.0.1:4000; npm run bd:local -- iniciar).
 *    Nunca el clúster remoto. El esquema sale de los archivos del repositorio (000 + 002 + 003 v2).
 *  - Con --con-moderacion (solo para probar el panel): crea una "propietaria" y un moderador de
 *    PRUEBA en esta BD local efímera y da MODERAR_CONTENIDO al admin de la demo. No toca cuentas reales.
 *  - Crea o actualiza 3 cuentas de demostración (admin, cliente y trabajador) con contraseñas
 *    ALEATORIAS en cada arranque, guardadas en backend/.local/cuentas-demo.json (ignorado por git).
 *  - Arranca el servidor. Si .env no tiene los JWT_SECRET_*, usa secretos temporales de la sesión.
 *  - Al detener: BORRA la BD de la demo (con --conservar la conserva).
 * Si se cerró de golpe y quedaron tablas: `npm run demo:limpiar`.
 */
// Primero el entorno: fija la BD de la demo antes de cargar la configuración.
import { BD_DEMO, secretosTemporales } from "./lib/entorno-demo";

import { randomBytes } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

import app from "../app";
import { almacenamientoConfig } from "../config/almacenamiento";
import { env } from "../config/env";
import { prisma } from "../config/prisma";
import { asignacionInicialPropietario, otorgarPermiso } from "../dominio/permisos";
import { hashPassword } from "../shared/auth/password";
import { activarChecksLocales, BD_LOCAL, construirBdLocal, verificarQueEsLocal } from "./lib/bd-local";
import { conectar } from "./lib/db-directa";

const SOLO_LIMPIAR = process.argv.includes("--limpiar");
const CONSERVAR = process.argv.includes("--conservar");
const CON_MODERACION = process.argv.includes("--con-moderacion");
const ARCHIVO_CUENTAS = path.resolve(process.cwd(), ".local", "cuentas-demo.json");

async function abrirServidorLocal() {
  const c = await conectar(null);
  await verificarQueEsLocal(c.consultar, BD_LOCAL.host);
  return c;
}

async function vaciarBdDemo() {
  const c = await abrirServidorLocal();
  await c.ejecutar(`DROP DATABASE IF EXISTS \`${BD_DEMO}\``);
  await c.cerrar();
  console.log(`BD local ${BD_DEMO}: borrada.`);
}

async function prepararBd() {
  const previa = await abrirServidorLocal();
  await activarChecksLocales(previa.ejecutar);
  await previa.cerrar();
  const c = await abrirServidorLocal();
  try {
    const { sentencias } = await construirBdLocal(c.consultar, c.ejecutar, BD_DEMO, { recrear: !CONSERVAR });
    console.log(`BD local ${BD_DEMO}: esquema 000 + 002 v10 + 003 v2 (${sentencias} sentencias), sin datos.`);
  } catch (error) {
    if (CONSERVAR && /ya tiene tablas/.test((error as Error).message)) {
      console.log(`BD local ${BD_DEMO}: se conservan los datos anteriores.`);
      return;
    }
    throw error;
  } finally {
    await c.cerrar();
  }
}

/** Cuentas de demostración con contraseñas NUEVAS en cada arranque (solo existen en la BD de la demo). */
async function crearCuentas() {
  const clave = () => randomBytes(9).toString("base64url");
  const cuentas = {
    admin: { correo: "admin.demo@quelimpiamos.test", password: clave() },
    cliente: { correo: "cliente.demo@quelimpiamos.test", telefono: "9990001111", password: clave() },
    trabajador: { correo: "trabajador.demo@quelimpiamos.test", telefono: "9990002222", password: clave() },
  };
  const hashAdmin = await hashPassword(cuentas.admin.password);
  const hashCliente = await hashPassword(cuentas.cliente.password);
  const hashTrabajador = await hashPassword(cuentas.trabajador.password);
  await prisma.usuarios.upsert({
    where: { correo: cuentas.admin.correo },
    create: { rol: "ADMIN", nombre_completo: "Admin Demo", correo: cuentas.admin.correo, password_hash: hashAdmin },
    update: { password_hash: hashAdmin, estado_cuenta: "ACTIVA" },
  });
  await prisma.usuarios.upsert({
    where: { correo: cuentas.cliente.correo },
    create: { nombre_completo: "Cliente Demo", correo: cuentas.cliente.correo, telefono: cuentas.cliente.telefono, password_hash: hashCliente },
    update: { password_hash: hashCliente, estado_cuenta: "ACTIVA" },
  });
  await prisma.trabajadores.upsert({
    where: { correo: cuentas.trabajador.correo },
    create: {
      nombre_completo: "Trabajador Demo", correo: cuentas.trabajador.correo, telefono: cuentas.trabajador.telefono,
      direccion: "Av. Demo 123, Cancún", password_hash: hashTrabajador,
    },
    update: { password_hash: hashTrabajador },
  });
  const extra: Record<string, unknown> = {};
  if (CON_MODERACION) {
    // Cuentas de PRUEBA en la BD local efímera, solo para probar el panel de moderación.
    const propietaria = { correo: "propietaria.prueba@quelimpiamos.test", password: clave() };
    await prisma.usuarios.upsert({
      where: { correo: propietaria.correo },
      create: { rol: "ADMIN", nombre_completo: "Propietaria de PRUEBA (demo)", correo: propietaria.correo, password_hash: await hashPassword(propietaria.password) },
      update: {},
    });
    const admin = await prisma.usuarios.findUniqueOrThrow({ where: { correo: cuentas.admin.correo } });
    if (!(await prisma.admin_permisos.count({ where: { permiso: "ADMINISTRAR_PERMISOS", revocado_en: null } }))) {
      await asignacionInicialPropietario(propietaria.correo, "Propietaria de PRUEBA de la demo local (no es la cuenta real)");
    }
    if (!(await prisma.admin_permisos.count({ where: { usuario_id: admin.id, permiso: "MODERAR_CONTENIDO", revocado_en: null } }))) {
      const p = await prisma.usuarios.findUniqueOrThrow({ where: { correo: propietaria.correo } });
      await otorgarPermiso(p.id, { usuarioId: admin.id, permiso: "MODERAR_CONTENIDO", motivo: "Admin de la demo local, para probar la moderación" });
    }
    extra.propietariaDePrueba = propietaria;
  }
  mkdirSync(path.dirname(ARCHIVO_CUENTAS), { recursive: true });
  writeFileSync(ARCHIVO_CUENTAS, JSON.stringify({ bd: BD_DEMO, generado: new Date().toISOString(), cuentas: { ...cuentas, ...extra } }, null, 2), {
    encoding: "utf8",
    mode: 0o600,
  });
}

async function main() {
  if (SOLO_LIMPIAR) {
    await vaciarBdDemo();
    return;
  }
  await prepararBd();
  await crearCuentas();

  const servidor = app.listen(env.port, () => {
    console.log(`\nDemo local en http://localhost:${env.port} (BD ${BD_DEMO}, NODE_ENV=${env.nodeEnv})`);
    console.log(`Cuentas de demostración (contraseñas nuevas en cada arranque): ${ARCHIVO_CUENTAS}`);
    console.log(`Carpeta del almacenamiento local (fotos de reportes): ${almacenamientoConfig.directorioLocal}`);
    if (CON_MODERACION) console.log("Moderación de PRUEBA activa: el admin de la demo tiene MODERAR_CONTENIDO (solo en esta BD local).");
    if (secretosTemporales.length) {
      console.log(`Secretos JWT temporales de esta sesión: ${secretosTemporales.join(", ")} (agrégalos a .env para que las sesiones sobrevivan reinicios).`);
    }
    console.log(CONSERVAR ? "Al detener se CONSERVAN los datos." : "Al detener (Ctrl+C) se BORRA la BD local de la demo.");
  });

  const detener = async () => {
    servidor.close();
    await prisma.$disconnect().catch(() => undefined);
    if (!CONSERVAR) await vaciarBdDemo().catch((e: unknown) => console.error("No se pudo vaciar la BD:", (e as Error).message));
    process.exit(0);
  };
  process.on("SIGINT", () => void detener());
  process.on("SIGTERM", () => void detener());
}

main().catch(async (error: unknown) => {
  console.error("La demo se detuvo:", (error as Error)?.message ?? error);
  await prisma.$disconnect().catch(() => undefined);
  process.exitCode = 1;
});
