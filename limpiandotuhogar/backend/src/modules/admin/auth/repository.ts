import { prisma } from "../../../config/prisma";

/** Acceso a datos de la cuenta del ADMIN (tabla usuarios, rol ADMIN). */
export const adminAuthRepository = {
  buscarPorId: (id: number) => prisma.usuarios.findUnique({ where: { id } }),
  buscarPorCorreo: (correo: string) => prisma.usuarios.findUnique({ where: { correo } }),
};
