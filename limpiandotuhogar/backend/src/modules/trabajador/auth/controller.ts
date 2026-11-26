import type { RequestHandler } from "express";

import { authConfig } from "../../../config/auth";
import { clavesDeIntento } from "../../../shared/auth/intentos";
import { hashPassword, verificarPassword } from "../../../shared/auth/password";
import { crearControlDeIntentos, exigirSinBloqueo } from "../../../shared/http/limites";
import { AppError } from "../../../shared/errors/AppError";
import { campoDuplicado } from "../../../shared/errors/duplicados";
import {
  correo,
  identificador,
  leerCuerpo,
  passwordIngresada,
  passwordNueva,
  telefono,
  texto,
} from "../../../shared/validation/campos";
import { aTrabajadorDto } from "./dto";
import { trabajadorActual } from "./guard";
import { trabajadorAuthRepository as repo } from "./repository";
import { emitirTokenTrabajador } from "./token";

/** Bloqueo progresivo de esta audiencia (en memoria). */
export const intentosTrabajador = crearControlDeIntentos(authConfig.limites.intentosGratis);

const CORREO_EN_USO = () => new AppError(409, "Ese correo ya está registrado", "CORREO_EN_USO");
const TELEFONO_EN_USO = () => new AppError(409, "Ese teléfono ya está registrado", "TELEFONO_EN_USO");
const CREDENCIALES_INVALIDAS = () =>
  new AppError(401, "Correo, teléfono o contraseña incorrectos", "CREDENCIALES_INVALIDAS");

/**
 * POST /api/trabajador/auth/registro — el trabajador se registra solo (decisión v3). No recibe
 * trabajos hasta que el admin apruebe sus documentos (eso llega con el SQL 002 y la Fase 4).
 */
export const registro: RequestHandler = async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const datos = {
    nombre_completo: texto(cuerpo, "nombre", "El nombre", { min: 2, max: 120 }),
    correo: correo(cuerpo),
    telefono: telefono(cuerpo),
    direccion: texto(cuerpo, "direccion", "La dirección", { min: 5, max: 255 }),
  };
  const password = passwordNueva(cuerpo);

  if (await repo.buscarPorCorreo(datos.correo)) throw CORREO_EN_USO();
  if (await repo.buscarPorTelefono(datos.telefono)) throw TELEFONO_EN_USO();

  try {
    const password_hash = await hashPassword(password);
    const cuenta = await repo.crear({ ...datos, password_hash });
    res.status(201).json({ token: emitirTokenTrabajador({ id: cuenta.id, password_hash }), trabajador: aTrabajadorDto(cuenta) });
  } catch (error) {
    const campo = campoDuplicado(error, ["correo", "telefono"] as const);
    if (campo === "correo") throw CORREO_EN_USO();
    if (campo === "telefono") throw TELEFONO_EN_USO();
    throw error;
  }
};

/** POST /api/trabajador/auth/login — con correo o teléfono. Sin contraseña asignada no entra. */
export const login: RequestHandler = async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const id = identificador(cuerpo);
  const password = passwordIngresada(cuerpo);

  const cuenta = "correo" in id ? await repo.buscarPorCorreo(id.correo) : await repo.buscarPorTelefono(id.telefono);
  const hash = cuenta?.password_hash ?? null;
  const claves = clavesDeIntento("trabajador", id, cuenta && hash ? cuenta.id : undefined);
  exigirSinBloqueo(intentosTrabajador, claves, res);
  const passwordOk = await verificarPassword(password, hash);
  if (!cuenta || !hash || !passwordOk) {
    intentosTrabajador.registrarFallo(claves);
    throw CREDENCIALES_INVALIDAS();
  }
  intentosTrabajador.registrarExito(claves);

  res.json({ token: emitirTokenTrabajador({ id: cuenta.id, password_hash: hash }), trabajador: aTrabajadorDto(cuenta) });
};

/** GET /api/trabajador/auth/me */
export const yo: RequestHandler = (_req, res) => {
  res.json({ trabajador: aTrabajadorDto(trabajadorActual(res)) });
};

/** POST /api/trabajador/auth/logout — token sin estado (D9-a): la app lo borra. */
export const logout: RequestHandler = (_req, res) => {
  res.status(204).end();
};

/** POST /api/trabajador/auth/cambiar-password — invalida los tokens anteriores y devuelve uno nuevo. */
export const cambiarPassword: RequestHandler = async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const actual = passwordIngresada(cuerpo, "password_actual");
  const nueva = passwordNueva(cuerpo, "password_nueva");
  const cuenta = trabajadorActual(res);
  const claves = [`trabajador:cuenta:${cuenta.id}`];
  exigirSinBloqueo(intentosTrabajador, claves, res);

  if (!(await verificarPassword(actual, cuenta.password_hash))) {
    intentosTrabajador.registrarFallo(claves);
    throw new AppError(400, "La contraseña actual no es correcta", "PASSWORD_ACTUAL_INCORRECTA");
  }
  const password_hash = await hashPassword(nueva);
  await repo.actualizarPassword(cuenta.id, password_hash);
  res.json({ token: emitirTokenTrabajador({ id: cuenta.id, password_hash }) });
};
