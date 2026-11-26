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
import { aClienteDto } from "./dto";
import { clienteActual } from "./guard";
import { clienteAuthRepository as repo } from "./repository";
import { emitirTokenCliente } from "./token";

/** Bloqueo progresivo de esta audiencia (en memoria). */
export const intentosCliente = crearControlDeIntentos(authConfig.limites.intentosGratis);

const CORREO_EN_USO = () => new AppError(409, "Ese correo ya está registrado", "CORREO_EN_USO");
const TELEFONO_EN_USO = () => new AppError(409, "Ese teléfono ya está registrado", "TELEFONO_EN_USO");
const CREDENCIALES_INVALIDAS = () =>
  new AppError(401, "Correo, teléfono o contraseña incorrectos", "CREDENCIALES_INVALIDAS");

/** POST /api/cliente/auth/registro — el teléfono es obligatorio (los clientes se registran por número). */
export const registro: RequestHandler = async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const datos = {
    nombre_completo: texto(cuerpo, "nombre", "El nombre", { min: 2, max: 120 }),
    correo: correo(cuerpo),
    telefono: telefono(cuerpo),
  };
  const password = passwordNueva(cuerpo);
  // `rol` y cualquier otro campo del body se ignoran: el registro siempre crea un CLIENTE.

  if (await repo.buscarPorCorreo(datos.correo)) throw CORREO_EN_USO();
  if (await repo.buscarPorTelefono(datos.telefono)) throw TELEFONO_EN_USO();

  try {
    const cuenta = await repo.crear({ ...datos, password_hash: await hashPassword(password) });
    res.status(201).json({ token: emitirTokenCliente(cuenta), cliente: aClienteDto(cuenta) });
  } catch (error) {
    // Dos registros simultáneos con el mismo dato: lo detecta el UNIQUE de la BD.
    const campo = campoDuplicado(error, ["correo", "telefono"] as const);
    if (campo === "correo") throw CORREO_EN_USO();
    if (campo === "telefono") throw TELEFONO_EN_USO();
    throw error;
  }
};

/** POST /api/cliente/auth/login — con correo o con teléfono. */
export const login: RequestHandler = async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const id = identificador(cuerpo);
  const password = passwordIngresada(cuerpo);

  const cuenta = "correo" in id ? await repo.buscarPorCorreo(id.correo) : await repo.buscarPorTelefono(id.telefono);
  const esCliente = cuenta?.rol === "CLIENTE";
  // El bloqueo se revisa ANTES de la contraseña y aplica igual si la cuenta no existe.
  const claves = clavesDeIntento("cliente", id, esCliente ? cuenta.id : undefined);
  exigirSinBloqueo(intentosCliente, claves, res);
  const passwordOk = await verificarPassword(password, esCliente ? cuenta.password_hash : null);
  if (!cuenta || !esCliente || !passwordOk) {
    intentosCliente.registrarFallo(claves);
    throw CREDENCIALES_INVALIDAS();
  }
  intentosCliente.registrarExito(claves);
  if (cuenta.estado_cuenta !== "ACTIVA") throw new AppError(403, "Tu cuenta está suspendida", "CUENTA_SUSPENDIDA");

  res.json({ token: emitirTokenCliente(cuenta), cliente: aClienteDto(cuenta) });
};

/** GET /api/cliente/auth/me */
export const yo: RequestHandler = (_req, res) => {
  res.json({ cliente: aClienteDto(clienteActual(res)) });
};

/**
 * POST /api/cliente/auth/logout — la sesión es un token sin estado (D9-a): la app lo borra.
 * Responde 204 para que la app tenga un punto único de cierre de sesión.
 */
export const logout: RequestHandler = (_req, res) => {
  res.status(204).end();
};

/** POST /api/cliente/auth/cambiar-password — invalida todos los tokens anteriores y devuelve uno nuevo. */
export const cambiarPassword: RequestHandler = async (req, res) => {
  const cuerpo = leerCuerpo(req.body);
  const actual = passwordIngresada(cuerpo, "password_actual");
  const nueva = passwordNueva(cuerpo, "password_nueva");
  const cuenta = clienteActual(res);
  const claves = [`cliente:cuenta:${cuenta.id}`];
  exigirSinBloqueo(intentosCliente, claves, res);

  if (!(await verificarPassword(actual, cuenta.password_hash))) {
    intentosCliente.registrarFallo(claves);
    throw new AppError(400, "La contraseña actual no es correcta", "PASSWORD_ACTUAL_INCORRECTA");
  }
  const actualizada = await repo.actualizarPassword(cuenta.id, await hashPassword(nueva));
  res.json({ token: emitirTokenCliente(actualizada) });
};
