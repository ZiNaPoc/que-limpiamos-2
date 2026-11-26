import type { RequestHandler, Response } from "express";
import { rateLimit } from "express-rate-limit";

import { authConfig } from "../../config/auth";
import { ControlDeIntentos } from "../auth/intentos";
import { AppError } from "../errors/AppError";

const MENSAJE = (minutos: number) =>
  `Demasiados intentos. Intenta de nuevo en ${minutos} minuto${minutos === 1 ? "" : "s"}.`;

/** Límite por IP (abuso general) con respuesta en el formato de la API. */
export function limitePorIp(regla: { limite: number; ventanaMin: number }): RequestHandler {
  return rateLimit({
    windowMs: regla.ventanaMin * 60_000,
    limit: regla.limite,
    standardHeaders: "draft-7",
    legacyHeaders: false,
    handler: (req, res) => {
      const reinicio = (req as { rateLimit?: { resetTime?: Date } }).rateLimit?.resetTime;
      const segundos = reinicio ? Math.max(1, Math.ceil((reinicio.getTime() - Date.now()) / 1000)) : regla.ventanaMin * 60;
      res.setHeader("Retry-After", String(segundos));
      res.status(429).json({ mensaje: MENSAJE(Math.ceil(segundos / 60)), codigo: "DEMASIADOS_INTENTOS" });
    },
  });
}

/** Bloqueo progresivo por cuenta/identificador: una instancia por audiencia. */
export function crearControlDeIntentos(gratis: number): ControlDeIntentos {
  return new ControlDeIntentos({
    gratis,
    escalonesMin: authConfig.limites.escalonesMin,
    olvidoHoras: authConfig.limites.olvidoHoras,
  });
}

/** Lanza 429 (con Retry-After) si alguna de las claves está bloqueada. Mismo mensaje exista o no la cuenta. */
export function exigirSinBloqueo(control: ControlDeIntentos, claves: string[], res: Response): void {
  const espera = control.esperaSegundos(claves);
  if (espera > 0) {
    res.setHeader("Retry-After", String(espera));
    throw new AppError(429, MENSAJE(Math.ceil(espera / 60)), "DEMASIADOS_INTENTOS");
  }
}
