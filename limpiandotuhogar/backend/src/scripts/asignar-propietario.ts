/**
 * Asignación INICIAL auditada al propietario (D63a) en la BD LOCAL de desarrollo.
 *   npm run permisos:asignar-propietario -- --correo <correo> --motivo "<motivo>"
 * Solo si existe EXACTAMENTE una cuenta ADMIN ACTIVA con ese correo. No crea usuarios ni cambia
 * roles. Otorga ADMINISTRAR_PERMISOS + MODERAR_CONTENIDO con origen ASIGNACION_INICIAL y deja
 * sus eventos en moderacion_eventos. En producción se usa la plantilla SQL revisada (doc 21 §5).
 */
import "./lib/entorno-bd-local";

import { env } from "../config/env";
import { prisma } from "../config/prisma";
import { asignacionInicialPropietario } from "../dominio/permisos";
import { AppError } from "../shared/errors/AppError";

function argumento(nombre: string): string | undefined {
  const i = process.argv.indexOf(`--${nombre}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function enmascarar(correo: string): string {
  const [usuario = "", dominio = ""] = correo.split("@");
  return `${usuario.slice(0, 2)}***@${dominio}`;
}

async function main() {
  if (!env.db.esLocal) throw new Error("Este script solo trabaja con la BD LOCAL de desarrollo");
  const correo = argumento("correo")?.trim().toLowerCase();
  const motivo = argumento("motivo")?.trim() || "D63a: asignación inicial del propietario indicado por el usuario (2026-11-25)";
  if (!correo) throw new Error("Falta --correo");
  console.log(`BD: ${env.db.name} en ${env.db.host}:${env.db.port} · propietario: ${enmascarar(correo)}`);
  try {
    const r = await asignacionInicialPropietario(correo, motivo);
    console.log(`ASIGNADO a la cuenta id ${r.usuarioId}:`, r.permisos.map((p) => `${p.permiso}#${p.id}`).join(", "));
  } catch (error) {
    if (error instanceof AppError) {
      console.log(`NO ASIGNADO (${error.codigo}): ${error.message}. No se creó ni se cambió ninguna cuenta.`);
      process.exitCode = 2;
      return;
    }
    throw error;
  }
}

main()
  .catch((error) => {
    console.error("ERROR:", (error as Error).message);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
