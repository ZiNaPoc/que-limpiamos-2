import { Router } from "express";

import { crearReporte, LIMITES_FOTOS, leerDescripcion, leerTipo, reportePropio, reportesPropios, urlEvidenciaPropia } from "../../../dominio/reportes";
import { fotosRecibidas, recibirFotos } from "../../../shared/http/multipart";
import { idDeRuta } from "../../../shared/http/parametros";
import { leerCuerpo } from "../../../shared/validation/campos";
import { requireTrabajador, trabajadorActual } from "../auth/guard";

/**
 * Reportes — audiencia TRABAJADOR (doc 20 §3). Solo ve los reportes que ÉL creó (X6).
 *   POST /api/trabajador/solicitudes/:id/reportes   multipart (tipo?, descripcion?, fotos[0..5]) o JSON
 *   GET  /api/trabajador/reportes                    sus reportes
 *   GET  /api/trabajador/reportes/:id                uno suyo (otro → 404)
 *   GET  /api/trabajador/reportes/:id/evidencias/:evidenciaId   URL temporal de una foto suya
 */
export const trabajadorReportesRouter = Router();
const protegido = [requireTrabajador];

trabajadorReportesRouter.post("/solicitudes/:id/reportes", ...protegido,
  recibirFotos({ cantidad: LIMITES_FOTOS.cantidad, bytesPorArchivo: LIMITES_FOTOS.bytesPorFoto }),
  async (req, res) => {
    const cuerpo = leerCuerpo(req.body ?? {});
    const reporte = await crearReporte({
      solicitudId: idDeRuta(req),
      rol: "TRABAJADOR",
      autorId: trabajadorActual(res).id,
      tipo: leerTipo(cuerpo.tipo, true),
      descripcion: leerDescripcion(cuerpo.descripcion),
      archivos: fotosRecibidas(req),
    });
    res.status(201).json({ reporte });
  },
);

trabajadorReportesRouter.get("/reportes", ...protegido, async (_req, res) => {
  res.json({ reportes: await reportesPropios("TRABAJADOR", trabajadorActual(res).id) });
});

trabajadorReportesRouter.get("/reportes/:id", ...protegido, async (req, res) => {
  res.json({ reporte: await reportePropio("TRABAJADOR", trabajadorActual(res).id, idDeRuta(req)) });
});

trabajadorReportesRouter.get("/reportes/:id/evidencias/:evidenciaId", ...protegido, async (req, res) => {
  res.json(await urlEvidenciaPropia("TRABAJADOR", trabajadorActual(res).id, idDeRuta(req), idDeRuta(req, "evidenciaId")));
});
