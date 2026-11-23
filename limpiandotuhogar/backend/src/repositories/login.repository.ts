import { prisma } from "../config/prisma";
import { estrellas_rol } from "../../generated/prisma/client";

export function buscarUsuario(email: string) {
  return prisma.estrellas.findUnique({
    where: { email },
  });
}

export interface CrearUsuarioData {
  name: string;
  phone_number: string;
  email: string;
  password: string; // ya hasheada
  rol: estrellas_rol;
}

export function crearUsuario({
  name,
  phone_number,
  email,
  password,
  rol,
}: CrearUsuarioData) {
  return prisma.estrellas.create({
    data: { name, phone_number, email, password, rol },
    select: {
      id: true,
      name: true,
      email: true,
      phone_number: true,
      rol: true,
    },
  });
}