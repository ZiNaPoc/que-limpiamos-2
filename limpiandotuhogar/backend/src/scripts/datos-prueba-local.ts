
import { DESTINO, DIRECTORIO_LOCAL } from "./lib/entorno-datos";

import { randomBytes } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import { prisma } from "../config/prisma";
import { asignacionInicialPropietario } from "../dominio/permisos";
import { hashPassword } from "../shared/auth/password";
import { verificarDestinoLocal, verificarDestinoNube } from "./lib/destino-local";


const ARCHIVO_CUENTAS = path.join(DIRECTORIO_LOCAL, DESTINO === "nube" ? "cuentas-demo-nube.json" : "cuentas-prueba-local.json");
const ARCHIVO_CUENTAS_LOCAL = path.join(DIRECTORIO_LOCAL, "cuentas-prueba-local.json");

const ARG_RESTABLECER = process.argv.find((a) => a === "--restablecer-claves" || a.startsWith("--restablecer-claves="));
const SOLO_RESTABLECER = ARG_RESTABLECER?.includes("=") ? new Set(ARG_RESTABLECER.split("=")[1]!.split(",")) : null;
const restablecer = (clave: string) => ARG_RESTABLECER !== undefined && (SOLO_RESTABLECER === null || SOLO_RESTABLECER.has(clave));


const ESPECIALIDADES = [
  { nombre: "Limpieza general", descripcion: "Barrer, trapear, aspirar y sacudir" },
  { nombre: "Limpieza profunda", descripcion: "Zonas de difícil acceso y desinfección" },
  { nombre: "Limpieza post-obra", descripcion: "Polvo y residuos de remodelación" },
];
const SERVICIOS = [
  { nombre: "Limpieza regular", descripcion: "Limpieza de mantenimiento que incluye barrer, trapear y aspirar.", precio: "400.00", minutos: 180, especialidades: ["Limpieza general"] },
  { nombre: "Limpieza profunda", descripcion: "Limpieza detallada de todas las áreas del espacio, incluyendo zonas de difícil acceso.", precio: "600.00", minutos: 300, especialidades: ["Limpieza general", "Limpieza profunda"] },
  { nombre: "Limpieza post-obra", descripcion: "Limpieza después de una remodelación o construcción.", precio: "650.00", minutos: 360, especialidades: ["Limpieza post-obra"] },
];

const AREAS = ["Cocina", "Sala", "Recámaras", "Baños", "Patio", "Áreas comunes"];
const EXTRAS = [
  { nombre: "Limpieza de ventanas", precio: "300.00" },
  { nombre: "Limpieza de estufa", precio: "300.00" },
  { nombre: "Limpieza de refrigerador", precio: "200.00" },
  { nombre: "Limpieza de alacena", precio: "180.00" },
  { nombre: "Limpieza de cajonera", precio: "150.00" },
];


const CLIENTE = { correo: "cliente.prueba@quelimpiamos.test", nombre: "Cliente de Prueba", telefono: "9990003333" };
const TRABAJADOR = { correo: "trabajador.prueba@quelimpiamos.test", nombre: "Trabajador de Prueba", telefono: "9990004444", direccion: "Calle Ficticia 123, Cancún (dato de prueba)" };

const PROPIETARIO = { correo: "", nombre: "Propietario (prueba local)" };
const ADMINS = [
  { clave: "admin1", correo: "admin1.prueba@quelimpiamos.test", nombre: "Admin Uno de Prueba" },
  { clave: "admin2", correo: "admin2.prueba@quelimpiamos.test", nombre: "Admin Dos de Prueba" },
] as const;
const TRABAJADOR2 = { correo: "trabajador2.prueba@quelimpiamos.test", nombre: "Trabajadora Dos de Prueba", telefono: "9990005555", direccion: "Calle Ficticia 789, Cancún (dato de prueba)" };

type Cuentas = Record<string, { correo: string; password?: string }>;
const nuevaClave = () => `Prueba-${randomBytes(6).toString("base64url")}`;

async function main() {
  const destino = DESTINO === "nube" ? await verificarDestinoNube({ conTablas: true }) : await verificarDestinoLocal();
  console.log(`Destino verificado: ${destino.host}:${destino.port} / ${destino.bd} (${destino.tablas} tablas) — ${destino.version.split("-").slice(0, 3).join("-")}`);

  const creados: string[] = [];
  const existian: string[] = [];
  const anotar = (nuevo: boolean, que: string) => (nuevo ? creados : existian).push(que);


  const especialidad = new Map<string, number>();
  for (const e of ESPECIALIDADES) {
    const previa = await prisma.especialidades.findUnique({ where: { nombre: e.nombre } });
    const fila = previa ?? (await prisma.especialidades.create({ data: e }));
    anotar(!previa, `especialidad "${e.nombre}"`);
    if (fila.estado !== "ACTIVO") console.warn(`  ⚠ La especialidad "${e.nombre}" ya existía y está ${fila.estado}: no se cambia.`);
    especialidad.set(e.nombre, fila.id);
  }
  const servicioIds: number[] = [];
  for (const s of SERVICIOS) {
    const previo = await prisma.servicios.findUnique({ where: { nombre: s.nombre } });
    const fila = previo ?? (await prisma.servicios.create({ data: { nombre: s.nombre, descripcion: s.descripcion, precio_base: s.precio, duracion_estimada_min: s.minutos } }));
    anotar(!previo, `servicio "${s.nombre}"`);
    if (fila.estado !== "ACTIVO") console.warn(`  ⚠ El servicio "${s.nombre}" ya existía y está ${fila.estado}: no se cambia.`);
    servicioIds.push(fila.id);
    if (!(await prisma.servicio_calculo.findUnique({ where: { servicio_id: fila.id } }))) {
      await prisma.servicio_calculo.create({ data: { servicio_id: fila.id } }); // incrementos en 0, como el 002 (F3)
    }
    for (const nombre of s.especialidades) {
      const clave = { servicio_id: fila.id, especialidad_id: especialidad.get(nombre)! };
      await prisma.servicio_especialidades.upsert({ where: { servicio_id_especialidad_id: clave }, create: clave, update: {} });
    }
  }

  for (const [i, nombre] of AREAS.entries()) {
    const previa = await prisma.areas_limpieza.findUnique({ where: { nombre } });
    if (!previa) await prisma.areas_limpieza.create({ data: { nombre, orden: i + 1 } });
    anotar(!previa, `área "${nombre}"`);
  }
  for (const x of EXTRAS) {
    const previo = await prisma.servicios_extra.findUnique({ where: { nombre: x.nombre } });
    if (!previo) await prisma.servicios_extra.create({ data: x });
    anotar(!previo, `extra "${x.nombre}"`);
  }

  const archivo: Cuentas = existsSync(ARCHIVO_CUENTAS)
    ? JSON.parse(readFileSync(ARCHIVO_CUENTAS, "utf8")).cuentas
    : { cliente: { correo: CLIENTE.correo }, trabajador: { correo: TRABAJADOR.correo } };

  const cliente = await prisma.usuarios.findUnique({ where: { correo: CLIENTE.correo } });
  if (cliente && cliente.rol !== "CLIENTE") throw new Error(`${CLIENTE.correo} existe con rol ${cliente.rol}: no se toca`);
  if (!cliente || restablecer("cliente") || !archivo.cliente?.password) {
    if (cliente && !restablecer("cliente")) {
      console.warn(`  ⚠ ${CLIENTE.correo} ya existe y su contraseña no está en ${ARCHIVO_CUENTAS}: usa --restablecer-claves.`);
    } else {
      const password = nuevaClave();
      const password_hash = await hashPassword(password);
      if (cliente) await prisma.usuarios.update({ where: { id: cliente.id }, data: { password_hash } });
      else await prisma.usuarios.create({ data: { rol: "CLIENTE", nombre_completo: CLIENTE.nombre, correo: CLIENTE.correo, telefono: CLIENTE.telefono, password_hash } });
      archivo.cliente = { correo: CLIENTE.correo, password };
    }
  }
  anotar(!cliente, `cliente ${CLIENTE.correo}`);

  let trabajador = await prisma.trabajadores.findUnique({ where: { correo: TRABAJADOR.correo } });
  const trabajadorNuevo = !trabajador;
  if (!trabajador || restablecer("trabajador") || !archivo.trabajador?.password) {
    if (trabajador && !restablecer("trabajador")) {
      console.warn(`  ⚠ ${TRABAJADOR.correo} ya existe y su contraseña no está en ${ARCHIVO_CUENTAS}: usa --restablecer-claves.`);
    } else {
      const password = nuevaClave();
      const password_hash = await hashPassword(password);
      trabajador = trabajador
        ? await prisma.trabajadores.update({ where: { id: trabajador.id }, data: { password_hash } })
        : await prisma.trabajadores.create({
            data: { nombre_completo: TRABAJADOR.nombre, correo: TRABAJADOR.correo, telefono: TRABAJADOR.telefono, direccion: TRABAJADOR.direccion, password_hash },
          });
      archivo.trabajador = { correo: TRABAJADOR.correo, password };
    }
  }
  anotar(trabajadorNuevo, `trabajador ${TRABAJADOR.correo}`);
  // Activo y verificado (solo esta cuenta ficticia), para que aparezca en la selección manual.
  trabajador = await prisma.trabajadores.update({ where: { id: trabajador!.id }, data: { estado: "ACTIVO", estado_verificacion: "VERIFICADO" } });
  for (const id of especialidad.values()) {
    const clave = { trabajador_id: trabajador.id, especialidad_id: id };
    await prisma.trabajador_especialidades.upsert({ where: { trabajador_id_especialidad_id: clave }, create: clave, update: {} });
  }
  for (const servicio_id of servicioIds) {
    const clave = { trabajador_id: trabajador.id, servicio_id };
    await prisma.trabajador_servicios.upsert({ where: { trabajador_id_servicio_id: clave }, create: clave, update: {} });
  }

  await prisma.usuarios.update({ where: { correo: CLIENTE.correo }, data: { estado_verificacion: "VERIFICADO" } });

  let trabajador2 = await prisma.trabajadores.findUnique({ where: { correo: TRABAJADOR2.correo } });
  if (!trabajador2 || restablecer("trabajador2") || !archivo.trabajador2?.password) {
    if (trabajador2 && !restablecer("trabajador2")) console.warn(`  ⚠ ${TRABAJADOR2.correo} ya existe y su contraseña no está en ${ARCHIVO_CUENTAS}: usa --restablecer-claves.`);
    else {
      const password = nuevaClave();
      const password_hash = await hashPassword(password);
      const nuevo = !trabajador2;
      trabajador2 = trabajador2
        ? await prisma.trabajadores.update({ where: { id: trabajador2.id }, data: { password_hash } })
        : await prisma.trabajadores.create({ data: { nombre_completo: TRABAJADOR2.nombre, correo: TRABAJADOR2.correo, telefono: TRABAJADOR2.telefono, direccion: TRABAJADOR2.direccion, password_hash } });
      archivo.trabajador2 = { correo: TRABAJADOR2.correo, password };
      anotar(nuevo, `trabajador ${TRABAJADOR2.correo}`);
    }
  } else anotar(false, `trabajador ${TRABAJADOR2.correo}`);
  trabajador2 = await prisma.trabajadores.update({ where: { id: trabajador2!.id }, data: { estado: "ACTIVO", estado_verificacion: "VERIFICADO" } });
  for (const id of especialidad.values()) {
    const clave = { trabajador_id: trabajador2.id, especialidad_id: id };
    await prisma.trabajador_especialidades.upsert({ where: { trabajador_id_especialidad_id: clave }, create: clave, update: {} });
  }


  const deLocal = existsSync(ARCHIVO_CUENTAS_LOCAL) ? (JSON.parse(readFileSync(ARCHIVO_CUENTAS_LOCAL, "utf8")).cuentas as Cuentas).propietario?.correo : undefined;
  PROPIETARIO.correo = (process.env.PROPIETARIO_CORREO ?? archivo.propietario?.correo ?? deLocal ?? "").trim().toLowerCase();
  if (!PROPIETARIO.correo) throw new Error("Indica el correo del propietario con PROPIETARIO_CORREO (no se guarda en el código)");
  const admins = [{ clave: "propietario", correo: PROPIETARIO.correo, nombre: PROPIETARIO.nombre }, ...ADMINS];
  for (const a of admins) {
    const existente = await prisma.usuarios.findUnique({ where: { correo: a.correo } });
    if (existente && existente.rol !== "ADMIN") throw new Error(`${a.clave}: la cuenta existe con rol ${existente.rol}; no se toca`);
    if (!existente || restablecer(a.clave) || !archivo[a.clave]?.password) {
      if (existente && !restablecer(a.clave)) {
        console.warn(`  ⚠ ${a.clave} ya existe y su contraseña no está en ${ARCHIVO_CUENTAS}: usa --restablecer-claves.`);
        continue;
      }
      const password = nuevaClave();
      const password_hash = await hashPassword(password);
      if (existente) await prisma.usuarios.update({ where: { id: existente.id }, data: { password_hash } });
      else await prisma.usuarios.create({ data: { rol: "ADMIN", nombre_completo: a.nombre, correo: a.correo, password_hash } });
      archivo[a.clave] = { correo: a.correo, password };
    }
    anotar(!existente, `admin ${a.clave}`);
  }
  const propietarioVigente = await prisma.admin_permisos.count({ where: { permiso: "ADMINISTRAR_PERMISOS", revocado_en: null } });
  if (propietarioVigente === 0) {
    await asignacionInicialPropietario(PROPIETARIO.correo, "Propietario de PRUEBA en la BD local de desarrollo (doc 25 v2, autorizado el 2026-11-25)");
    anotar(true, "asignación inicial del propietario de prueba");
  } else anotar(false, "asignación inicial del propietario de prueba");

  writeFileSync(ARCHIVO_CUENTAS, JSON.stringify({ bd: destino.bd, actualizado: new Date().toISOString(), cuentas: archivo }, null, 2), { encoding: "utf8", mode: 0o600 });

  // 4. Comprobación final con los mismos criterios que la selección manual.
  const visible = await prisma.trabajadores.count({ where: { id: trabajador.id, estado: "ACTIVO", estado_verificacion: "VERIFICADO" } });
  console.log(`Creado ahora: ${creados.length ? creados.join(", ") : "nada (ya estaba todo)"}`);
  console.log(`Ya existía: ${existian.length}`);
  console.log(`Trabajador de prueba visible en la selección manual: ${visible ? "sí" : "NO"} (id ${trabajador.id}, ${especialidad.size} especialidades)`);
  console.log(`Credenciales: ${ARCHIVO_CUENTAS}`);
  console.log("No se crearon solicitudes.");
}

main()
  .catch((error: unknown) => {
    console.error("ERROR:", (error as Error)?.message ?? error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
