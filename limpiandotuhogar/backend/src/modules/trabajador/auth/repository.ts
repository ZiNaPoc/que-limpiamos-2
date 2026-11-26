import { prisma } from "../../../config/prisma";

/** Acceso a datos de la cuenta del TRABAJADOR (tabla trabajadores, separada de usuarios). */
export const trabajadorAuthRepository = {
  buscarPorId: (id: number) => prisma.trabajadores.findUnique({ where: { id } }),
  buscarPorCorreo: (correo: string) => prisma.trabajadores.findUnique({ where: { correo } }),
  buscarPorTelefono: (telefono: string) => prisma.trabajadores.findUnique({ where: { telefono } }),

  crear: (datos: { nombre_completo: string; correo: string; telefono: string; direccion: string; password_hash: string }) =>
    prisma.trabajadores.create({ data: datos }),

  actualizarPassword: (id: number, password_hash: string) =>
    prisma.trabajadores.update({ where: { id }, data: { password_hash } }),
};
