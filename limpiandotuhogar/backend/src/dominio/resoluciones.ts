import { Prisma } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { AppError } from "../shared/errors/AppError";
import type { Cuerpo } from "../shared/validation/campos";
import { registrarEvento } from "./auditoria";
import { bloquearSolicitud } from "./ciclo-solicitudes";
import { avisarCliente, avisarTrabajador } from "./notificaciones";
import { exigirPermiso, GESTIONAR_INCIDENCIAS_FINANZAS } from "./permisos";
import { relojDominio } from "./reloj";

/**
 * RESOLUCIÓN ADMINISTRATIVA DEL SERVICIO (doc 25 v2 §4; D57, D62; decisiones del 2026-11-25).
 *  - Solo un admin ACTIVO con GESTIONAR_INCIDENCIAS_FINANZAS vigente (bloqueado durante la operación).
 *  - Solo sobre una solicitud CONFIRMADO o EN_PROCESO con al menos un reporte ACTIVO.
 *  - INMUTABLE: una sola resolución de servicio por solicitud. No hay ruta para editarla ni
 *    sustituirla. La rectificación será un procedimiento futuro aparte (NO en esta fase).
 *  - Concurrencia: la fila de la solicitud se bloquea (FOR UPDATE); la segunda resolución recibe
 *    409 RESOLUCION_EXISTENTE. Última barrera: el UNIQUE uq_res_una_de_servicio (SQL 004) → 409.
 *  - Sin dinero: resultado_pago queda NULL (fase de dinero).
 */

export const LIMITES_MOTIVO_RESOLUCION = { min: 10, max: 500 } as const;
type Resultado = "REALIZADO" | "NO_REALIZADO";

export function leerResolucion(cuerpo: Cuerpo): { resultado: Resultado; motivo: string } {
  const resultado = cuerpo.resultadoServicio;
  if (resultado !== "REALIZADO" && resultado !== "NO_REALIZADO") {
    throw new AppError(400, "Indica el resultado del servicio: REALIZADO o NO_REALIZADO", "RESULTADO_INVALIDO");
  }
  const texto = typeof cuerpo.motivo === "string" ? cuerpo.motivo.trim() : "";
  const largo = [...texto].length;
  if (largo < LIMITES_MOTIVO_RESOLUCION.min || largo > LIMITES_MOTIVO_RESOLUCION.max) {
    throw new AppError(400, `El motivo es obligatorio (de ${LIMITES_MOTIVO_RESOLUCION.min} a ${LIMITES_MOTIVO_RESOLUCION.max} caracteres)`, "MOTIVO_REQUERIDO");
  }
  return { resultado, motivo: texto };
}

const existente = () => new AppError(409, "Esta solicitud ya tiene una resolución registrada. Las resoluciones no se pueden modificar", "RESOLUCION_EXISTENTE");

export async function resolverServicio(adminId: number, solicitudId: number, cuerpo: Cuerpo) {
  const { resultado, motivo } = leerResolucion(cuerpo);
  try {
    return await prisma.$transaction(async (tx) => {
      const permisoId = await exigirPermiso(tx, adminId, GESTIONAR_INCIDENCIAS_FINANZAS, { bloquear: true });
      const s = await bloquearSolicitud(tx, solicitudId);
      if (await tx.solicitud_resoluciones.findFirst({ where: { solicitud_id: solicitudId, resultado_servicio: { not: null } }, select: { id: true } })) throw existente();
      if (s.estado !== "CONFIRMADO" && s.estado !== "EN_PROCESO") {
        throw new AppError(409, "Solo se resuelve un servicio confirmado o en proceso (esta solicitud ya está cerrada o pendiente)", "ESTADO_NO_PERMITIDO");
      }
      const reportes = await tx.solicitud_reportes.findMany({ where: { solicitud_id: solicitudId, estado: { not: "RESUELTO" }, eliminado_en: null }, orderBy: { id: "asc" } });
      if (!reportes.length) throw new AppError(409, "La solicitud no tiene reportes activos: no hay una incidencia que resolver", "SIN_REPORTES_ACTIVOS");

      const ahora = relojDominio.ahora();
      const resolucion = await tx.solicitud_resoluciones.create({
        data: { solicitud_id: solicitudId, admin_id: adminId, admin_permiso_id: permisoId, resultado_servicio: resultado, resultado_pago: null, motivo, created_at: ahora },
      });
      const nuevo = resultado === "REALIZADO" ? ("REALIZADO" as const) : ("CANCELADO" as const);
      const r = await tx.solicitudes.updateMany({
        where: { id: solicitudId, estado: s.estado },
        data: resultado === "REALIZADO" ? { estado: "REALIZADO", realizado_en: ahora, realizado_via: "RESOLUCION_ADMIN", updated_at: ahora } : { estado: "CANCELADO", updated_at: ahora },
      });
      if (r.count !== 1) throw new AppError(409, "La solicitud cambió mientras tanto", "ESTADO_CAMBIO");
      await tx.solicitud_historial.create({
        data: {
          solicitud_id: solicitudId,
          estado_anterior: s.estado,
          estado_nuevo: nuevo,
          actor: "ADMIN",
          actor_id: adminId,
          motivo: `Resolución administrativa #${resolucion.id} (${resultado === "REALIZADO" ? "realizado" : "no realizado"}): ${motivo}`.slice(0, 255),
          created_at: ahora,
        },
      });
      for (const rep of reportes) {
        await tx.solicitud_reportes.update({ where: { id: rep.id }, data: { estado: "RESUELTO", resolucion_id: resolucion.id, updated_at: ahora } });
        await registrarEvento(tx, {
          actor: { adminId, permisoId },
          objetivo: { entidad: "REPORTE", reporteId: rep.id },
          operacion: "RESOLVER",
          antes: { estado: rep.estado, resolucion_id: null },
          despues: { estado: "RESUELTO", resolucion_id: resolucion.id, resultado_servicio: resultado },
          motivo,
        });
      }
      const titulo = "Se resolvió el reporte de tu servicio";
      const servicio = s.servicio_nombre_aplicado ?? "tu servicio";
      const mensaje = resultado === "REALIZADO" ? `La administración revisó ${servicio} y lo dio por realizado.` : `La administración revisó ${servicio} y lo dio por no realizado: quedó cancelado.`;
      await avisarCliente(tx, s.cliente_id, { tipo: "REPORTE_RESUELTO", clave: `REPORTE_RESUELTO:sol:${solicitudId}`, titulo, mensaje, solicitudId });
      if (s.trabajador_id) await avisarTrabajador(tx, s.trabajador_id, { tipo: "REPORTE_RESUELTO", clave: `REPORTE_RESUELTO:sol:${solicitudId}`, titulo, mensaje, solicitudId });
      return {
        id: resolucion.id,
        solicitudId,
        resultadoServicio: resultado,
        estadoSolicitud: nuevo,
        motivo,
        reportesResueltos: reportes.map((x) => x.id),
        fecha: ahora.toISOString(),
      };
    });
  } catch (error) {
    // Dos resoluciones a la vez: si la segunda llegó a insertar, el UNIQUE de la BD la rechaza.
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") throw existente();
    throw error;
  }
}
