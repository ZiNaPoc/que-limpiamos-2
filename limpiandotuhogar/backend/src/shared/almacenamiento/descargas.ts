import { Router } from "express";

import type { AlmacenamientoLocal } from "./local";

/**
 * GET /api/archivos/temporal/:token — entrega un archivo SOLO con un token firmado y vigente
 * (lo emite un endpoint que ya autorizó a quien lo pide). No hay listado ni rutas estáticas.
 * Token inválido, vencido o archivo inexistente → 404 (no se distingue el motivo).
 */
export function crearRouterDescargas(almacen: AlmacenamientoLocal): Router {
  const router = Router();
  router.get("/temporal/:token", async (req, res) => {
    const resuelto = almacen.resolverToken(req.params.token);
    const contenido = resuelto && (await almacen.existe(resuelto.clave)) ? await almacen.leer(resuelto.clave) : null;
    if (!resuelto || !contenido) {
      res.status(404).json({ mensaje: "Archivo no disponible", codigo: "ARCHIVO_NO_DISPONIBLE" });
      return;
    }
    const extension = resuelto.clave.slice(resuelto.clave.lastIndexOf(".") + 1);
    res.setHeader("Content-Type", resuelto.mime);
    res.setHeader("Content-Length", String(contenido.length));
    res.setHeader("Content-Disposition", `inline; filename="archivo.${extension}"`);
    res.setHeader("Cache-Control", "no-store, private");
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Content-Security-Policy", "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; sandbox");
    res.setHeader("Referrer-Policy", "no-referrer");
    res.end(contenido);
  });
  return router;
}
