import { NextFunction, Request, Response } from "express";
import { compare, hash } from "bcryptjs";
import { Prisma } from "../../generated/prisma/client";
import * as loginRepository from "../repositories/login.repository";
import { AppError } from "../errors/AppError";

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const TELEFONO_REGEX = /^\d{7,15}$/; // la columna es VarChar(15)

// SOLO PARA LA DEMO: cada app manda su rol al registrarse.
// En producción TRABAJADOR debería asignarse después de revisar la INE.
const ROLES_PERMITIDOS = ["CLIENTE", "TRABAJADOR"] as const;
type RolPermitido = (typeof ROLES_PERMITIDOS)[number];

function texto(valor: unknown): string {
  return typeof valor === "string" ? valor.trim() : "";
}

export async function login(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  try {
    const correo = texto(req.body?.correo).toLowerCase();

    const password =
      typeof req.body?.password === "string" ? req.body.password : "";

    if (!correo) {
      throw new AppError(400, "Hace falta el correo electronico");
    }

    if (!password) {
      throw new AppError(400, "Hace falta la contraseña");
    }

    const estrella = await loginRepository.buscarUsuario(correo);

    const passwordValida = estrella
      ? await compare(password, estrella.password)
      : false;

    if (!estrella || !passwordValida) {
      throw new AppError(401, "Credenciales invalidas");
    }

    // El rol se devuelve y cada app decide si lo acepta
    // (la de trabajadores solo TRABAJADOR, la de clientes solo CLIENTE).
    return res.status(200).json({
      mensaje: "Inicio de sesion exitoso",
      estrella: {
        id: estrella.id,
        nombre: estrella.name,
        correo: estrella.email,
        telefono: estrella.phone_number,
        rol: estrella.rol,
      },
    });
  } catch (error) {
    next(error);
  }
}

export async function signup(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  try {
    const nombre = texto(req.body?.nombre);
    const correo = texto(req.body?.correo).toLowerCase();
    const telefono = texto(req.body?.telefono);
    const password =
      typeof req.body?.password === "string" ? req.body.password : "";
    const rolRecibido = texto(req.body?.rol).toUpperCase() || "CLIENTE";

    if (!nombre) {
      throw new AppError(400, "Hace falta el nombre");
    }
    if (nombre.length > 255) {
      throw new AppError(400, "El nombre es demasiado largo");
    }

    if (!correo) {
      throw new AppError(400, "Hace falta el correo electronico");
    }
    if (correo.length > 255 || !EMAIL_REGEX.test(correo)) {
      throw new AppError(400, "El correo electronico no es valido");
    }

    if (!telefono) {
      throw new AppError(400, "Hace falta el telefono");
    }
    if (!TELEFONO_REGEX.test(telefono)) {
      throw new AppError(400, "El telefono debe tener entre 7 y 15 digitos");
    }

    if (!password) {
      throw new AppError(400, "Hace falta la contraseña");
    }
    if (password.length < 8) {
      throw new AppError(400, "La contraseña debe tener al menos 8 caracteres");
    }

    if (!ROLES_PERMITIDOS.includes(rolRecibido as RolPermitido)) {
      throw new AppError(400, "El rol debe ser CLIENTE o TRABAJADOR");
    }
    const rol = rolRecibido as RolPermitido;

    const passwordHash = await hash(password, 10);

    const estrella = await loginRepository.crearUsuario({
      name: nombre,
      phone_number: telefono,
      email: correo,
      password: passwordHash,
      rol,
    });

    return res.status(201).json({
      mensaje: "Registro exitoso",
      estrella: {
        id: estrella.id,
        nombre: estrella.name,
        correo: estrella.email,
        telefono: estrella.phone_number,
        rol: estrella.rol,
      },
    });
  } catch (error) {
    // P2002 = valor duplicado en una columna unique (email o phone_number)
    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2002"
    ) {
      const campo = String(error.meta?.target ?? "");
      if (campo.includes("phone_number")) {
        return next(new AppError(409, "El telefono ya esta registrado"));
      }
      if (campo.includes("email")) {
        return next(new AppError(409, "El correo electronico ya esta registrado"));
      }
      return next(new AppError(409, "Ya existe un usuario con esos datos"));
    }
    next(error);
  }
}