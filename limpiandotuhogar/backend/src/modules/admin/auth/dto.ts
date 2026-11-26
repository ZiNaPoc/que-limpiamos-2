import type { usuarios } from "../../../../generated/prisma/client";

/** Forma que espera el panel (`Sesion` en appWeb/src/data/tipos.ts). Nunca incluye password_hash. */
export function aAdminDto(u: usuarios) {
  return { id: u.id, nombre: u.nombre_completo, correo: u.correo, rol: u.rol };
}
