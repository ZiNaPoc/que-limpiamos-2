import { prisma } from "../../../config/prisma";

/** Acceso a datos de la cuenta del CLIENTE (tabla usuarios, rol CLIENTE). */
export const clienteAuthRepository = {
  buscarPorId: (id: number) => prisma.usuarios.findUnique({ where: { id } }),
  buscarPorCorreo: (correo: string) => prisma.usuarios.findUnique({ where: { correo } }),
  buscarPorTelefono: (telefono: string) => prisma.usuarios.findUnique({ where: { telefono } }),

  /** El rol se fija aquí: el registro público nunca puede crear un ADMIN. */
  crear: (datos: { nombre_completo: string; correo: string; telefono: string; password_hash: string }) =>
    prisma.usuarios.create({ data: { ...datos, rol: "CLIENTE" } }),

  actualizarPassword: (id: number, password_hash: string) =>
    prisma.usuarios.update({ where: { id }, data: { password_hash } }),
};
