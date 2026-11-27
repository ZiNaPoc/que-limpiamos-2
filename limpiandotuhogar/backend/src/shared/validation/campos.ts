import { AppError } from "../errors/AppError";
import { PASSWORD_MAX_BYTES, PASSWORD_MIN_CARACTERES } from "../auth/password";

/**
 * Validación manual de campos del body (sin dependencias). Cada función devuelve el valor
 * normalizado o lanza AppError 400 DATOS_INVALIDOS con un mensaje para el usuario.
 */

export type Cuerpo = Record<string, unknown>;

function invalido(mensaje: string): AppError {
  return new AppError(400, mensaje, "DATOS_INVALIDOS");
}

/** El body debe ser un objeto JSON (no arreglo, no texto). */
export function leerCuerpo(body: unknown): Cuerpo {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw invalido("El cuerpo de la petición debe ser un objeto JSON");
  }
  return body as Cuerpo;
}

export function texto(cuerpo: Cuerpo, campo: string, etiqueta: string, limites: { min: number; max: number }): string {
  const valor = cuerpo[campo];
  if (typeof valor !== "string" || !valor.trim()) throw invalido(`${etiqueta} es obligatorio`);
  const limpio = valor.trim().replace(/\s+/g, " ");
  if (limpio.length < limites.min || limpio.length > limites.max) {
    throw invalido(`${etiqueta} debe tener entre ${limites.min} y ${limites.max} caracteres`);
  }
  return limpio;
}

const PATRON_CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export function correo(cuerpo: Cuerpo, campo = "correo"): string {
  const valor = cuerpo[campo];
  if (typeof valor !== "string" || !valor.trim()) throw invalido("El correo es obligatorio");
  const limpio = valor.trim().toLowerCase();
  if (limpio.length > 150 || !PATRON_CORREO.test(limpio)) throw invalido("El correo no es válido");
  return limpio;
}

/** Teléfono de México: 10 dígitos. Acepta espacios, guiones y el prefijo +52. */
export function telefono(cuerpo: Cuerpo, campo = "telefono"): string {
  const valor = cuerpo[campo];
  if (typeof valor !== "string" && typeof valor !== "number") throw invalido("El teléfono es obligatorio");
  let digitos = String(valor).replace(/[\s\-().]/g, "");
  if (digitos.startsWith("+52")) digitos = digitos.slice(3);
  if (!/^\d{10}$/.test(digitos)) throw invalido("El teléfono debe tener 10 dígitos");
  return digitos;
}

/** Contraseña nueva: mínimo 8 caracteres y máximo 72 bytes. No se recorta. */
export function passwordNueva(cuerpo: Cuerpo, campo = "password"): string {
  const valor = cuerpo[campo];
  if (typeof valor !== "string" || !valor) throw invalido("La contraseña es obligatoria");
  if (valor.length < PASSWORD_MIN_CARACTERES) {
    throw invalido(`La contraseña debe tener al menos ${PASSWORD_MIN_CARACTERES} caracteres`);
  }
  if (Buffer.byteLength(valor, "utf8") > PASSWORD_MAX_BYTES) throw invalido("La contraseña es demasiado larga");
  return valor;
}

/** Contraseña para iniciar sesión: solo se exige que venga (las reglas aplican al crearla). */
export function passwordIngresada(cuerpo: Cuerpo, campo = "password"): string {
  const valor = cuerpo[campo];
  if (typeof valor !== "string" || !valor) throw invalido("La contraseña es obligatoria");
  return valor;
}

/** Login: se identifica con correo o con teléfono (uno de los dos). */
export function identificador(cuerpo: Cuerpo): { correo: string } | { telefono: string } {
  if (cuerpo.telefono !== undefined && cuerpo.telefono !== null && cuerpo.telefono !== "") {
    return { telefono: telefono(cuerpo) };
  }
  return { correo: correo(cuerpo) };
}
