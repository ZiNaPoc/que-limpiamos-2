import type { trabajadores } from "../../../../generated/prisma/client";

/**
 * Lo que la app del trabajador ve de su cuenta. Nunca incluye password_hash.
 * `rol` es fijo: el modelo ApiUser de la app lo exige (los trabajadores no están en usuarios).
 */
export function aTrabajadorDto(t: trabajadores) {
  return {
    id: t.id,
    rol: "TRABAJADOR" as const,
    nombre: t.nombre_completo,
    correo: t.correo,
    telefono: t.telefono,
    direccion: t.direccion,
    foto_url: t.foto_url,
    estado: t.estado,
  };
}
