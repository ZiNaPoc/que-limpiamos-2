import { Router } from "express";

import { crearReporte, LIMITES_FOTOS, leerDescripcion, leerTipo, reportePropio, reportesPropios, urlEvidenciaPropia } from "../../../dominio/reportes";
import { fotosRecibidas, recibirFotos } from "../../../shared/http/multipart";
import { idDeRuta } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { clienteActual, requireCliente } from "../auth/guard";

/**
 * Reportes — audiencia CLIENTE (doc 20 §3). Solo ve los reportes que ÉL creó (X6).
 *   POST /api/cliente/solicitudes/:id/reportes   multipart (tipo?, descripcion?, fotos[0..5]) o JSON
 *   GET  /api/cliente/reportes                    sus reportes
 *   GET  /api/cliente/reportes/:id                uno suyo (otro → 404)
 *   GET  /api/cliente/reportes/:id/evidencias/:evidenciaId   URL temporal de una foto suya
 */
export const clienteReportesRouter = Router();
const protegido = [requireCliente];

clienteReportesRouter.post("/solicitudes/:id/reportes", ...protegido,
  recibirFotos({ cantidad: LIMITES_FOTOS.cantidad, bytesPorArchivo: LIMITES_FOTOS.bytesPorFoto }),
  async (req, res) => {
    const cuerpo = leerCuerpo(req.body ?? {});
    const reporte = await crearReporte({
      solicitudId: idDeRuta(req),
      rol: "CLIENTE",
      autorId: clienteActual(res).id,
      tipo: leerTipo(cuerpo.tipo, true),
      descripcion: leerDescripcion(cuerpo.descripcion),
      archivos: fotosRecibidas(req),
    });
    res.status(201).json({ reporte });
  },
);

clienteReportesRouter.get("/reportes", ...protegido, async (_req, res) => {
  res.json({ reportes: await reportesPropios("CLIENTE", clienteActual(res).id) });
});

clienteReportesRouter.get("/reportes/:id", ...protegido, async (req, res) => {
  res.json({ reporte: await reportePropio("CLIENTE", clienteActual(res).id, idDeRuta(req)) });
});

clienteReportesRouter.get("/reportes/:id/evidencias/:evidenciaId", ...protegido, async (req, res) => {
  res.json(await urlEvidenciaPropia("CLIENTE", clienteActual(res).id, idDeRuta(req), idDeRuta(req, "evidenciaId")));
});
