import type { RequestHandler } from "express";
import multer from "multer";

import { AppError } from "../errors/AppError";

/**
 * Recibe las FOTOS de un reporte (multipart/form-data, campo "fotos"), en memoria y con los
 * límites aplicados MIENTRAS se reciben (no se acepta un archivo enorme para rechazarlo después):
 * máx. `cantidad` archivos y `bytesPorArchivo` cada uno. El total por reporte, el tipo REAL
 * y la limpieza de GPS se validan después (dominio/reportes.ts → almacenamiento).
 */
export function recibirFotos(limites: { cantidad: number; bytesPorArchivo: number }): RequestHandler {
  const subir = multer({
    storage: multer.memoryStorage(),
    limits: { files: limites.cantidad, fileSize: limites.bytesPorArchivo, fields: 10, fieldSize: 64 * 1024, parts: limites.cantidad + 10 },
  }).array("fotos", limites.cantidad);

  return (req, res, next) => {
    if (!req.is("multipart/form-data")) {
      next();
      return;
    }
    subir(req, res, (error: unknown) => {
      if (!error) {
        next();
        return;
      }
      if (error instanceof multer.MulterError) {
        if (error.code === "LIMIT_FILE_COUNT" || error.code === "LIMIT_UNEXPECTED_FILE") {
          next(new AppError(400, `Un reporte admite como máximo ${limites.cantidad} fotografías (campo "fotos")`, "DEMASIADAS_FOTOS"));
          return;
        }
        if (error.code === "LIMIT_FILE_SIZE") {
          next(new AppError(413, `Cada fotografía puede pesar como máximo ${limites.bytesPorArchivo / 1_000_000} MB`, "FOTO_DEMASIADO_GRANDE"));
          return;
        }
        next(new AppError(400, "El formulario enviado no es válido", "FORMULARIO_INVALIDO"));
        return;
      }
      next(error);
    });
  };
}

/** Archivos recibidos por recibirFotos, en el formato del dominio. */
export function fotosRecibidas(req: Parameters<RequestHandler>[0]) {
  const archivos = (req as { files?: Express.Multer.File[] }).files ?? [];
  return archivos.map((f) => ({ contenido: f.buffer, nombreOriginal: f.originalname, mimeDeclarado: f.mimetype }));
}
