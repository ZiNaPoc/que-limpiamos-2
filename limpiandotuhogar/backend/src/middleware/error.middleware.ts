import type { ErrorRequestHandler, RequestHandler } from "express";
import { AppError } from "../shared/errors/AppError";
import { traducirErrorPrisma } from "../shared/errors/prismaErrors";

/** Formato de error de toda la API: { mensaje, codigo? } */
export const rutaNoEncontrada: RequestHandler = (req, res) => {
  res.status(404).json({
    mensaje: `No existe la ruta ${req.method} ${req.path}`,
    codigo: "RUTA_NO_ENCONTRADA",
  });
};

export const manejarErrores: ErrorRequestHandler = (errorOriginal, _req, res, _next) => {
  // JSON mal formado en el body (lo lanza express.json()).
  if (
    errorOriginal instanceof SyntaxError &&
    (errorOriginal as { type?: string }).type === "entity.parse.failed"
  ) {
    res.status(400).json({ mensaje: "El cuerpo de la petición no es JSON válido", codigo: "JSON_INVALIDO" });
    return;
  }
  if ((errorOriginal as { type?: string })?.type === "entity.too.large") {
    res.status(413).json({ mensaje: "La petición es demasiado grande", codigo: "PAYLOAD_GRANDE" });
    return;
  }

  const error = traducirErrorPrisma(errorOriginal);

  if (error instanceof AppError) {
    res.status(error.status).json({
      mensaje: error.message,
      ...(error.codigo ? { codigo: error.codigo } : {}),
    });
    return;
  }

  // Errores inesperados: se registran completos, pero al cliente no se le
  // filtran detalles internos (consultas, rutas, stack).
  console.error(error);
  res.status(500).json({ mensaje: "Error interno del servidor", codigo: "ERROR_INTERNO" });
};
