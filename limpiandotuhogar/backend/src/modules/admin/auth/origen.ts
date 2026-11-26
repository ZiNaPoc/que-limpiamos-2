import type { RequestHandler } from "express";

import { env } from "../../../config/env";
import { AppError } from "../../../shared/errors/AppError";

const METODOS_SEGUROS = new Set(["GET", "HEAD", "OPTIONS"]);

/**
 * Protección CSRF de la audiencia ADMIN (sesión en cookie). Toda petición que cambia algo
 * (POST, PUT, PATCH, DELETE) debe traer un encabezado Origin de la lista CORS_ORIGINS. Los
 * navegadores lo envían siempre en esas peticiones; una página ajena no puede falsificarlo.
 */
export const exigirOrigenPermitido: RequestHandler = (req, _res, next) => {
  if (METODOS_SEGUROS.has(req.method)) return next();
  const origen = req.headers.origin;
  if (!origen || !env.corsOrigins.includes(origen)) {
    throw new AppError(403, "Origen no permitido", "ORIGEN_NO_PERMITIDO");
  }
  next();
};
