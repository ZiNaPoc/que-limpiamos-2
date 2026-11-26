import type { usuarios } from "../../../../generated/prisma/client";

/** Lo que la app del cliente ve de su cuenta. Nunca incluye password_hash. */
export function aClienteDto(u: usuarios) {
  return {
    id: u.id,
    nombre: u.nombre_completo,
    correo: u.correo,
    telefono: u.telefono,
    rol: u.rol,
    foto_url: u.foto_url,
    estado_cuenta: u.estado_cuenta,
    estado_verificacion: u.estado_verificacion,
  };
}
