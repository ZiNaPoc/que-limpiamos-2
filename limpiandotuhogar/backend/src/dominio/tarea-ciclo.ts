import { prisma } from "../config/prisma";
import type { Tx } from "./auditoria";
import { bloquearSolicitud, tieneReportesActivos } from "./ciclo-solicitudes";
import { avisarCliente, avisarTrabajador } from "./notificaciones";
import { relojDominio } from "./reloj";

/**
 * TAREA PERIÓDICA del ciclo (doc 25 v2 §2), cada minuto dentro del servidor. IDEMPOTENTE: cada paso
 * es un UPDATE condicional en su propia transacción, con la fila de la solicitud bloqueada; una
 * segunda ejecución (o una simultánea) no cambia nada ni repite avisos (clave_evento, D60).
 *
 *  1. VENCER: PENDIENTE cuya hora programada llegó → CANCELADO por el SISTEMA; invitaciones
 *     pendientes → CERRADA con motivo VENCIDA (SQL 004); aviso al cliente. Sin cargos.
 *  2. D54, con T = fin estimado, solo EN_PROCESO y SIN reportes activos (D57):
 *     a) el trabajador marcó terminado (con fotos) y el cliente no: en max(T + 30 min, marca) se
 *        avisa al cliente; 15 min después → REALIZADO (EVIDENCIA_TRABAJADOR).
 *     b) nadie marcó: en T + 30 min se pide confirmar a ambos; 30 min después → REALIZADO (AUTOMATICO).
 *  Un CONFIRMADO que nunca inició NO cambia solo: queda como alerta en el panel.
 *  NADA de dinero: no se presume el pago ni se registra comisión (fase de dinero).
 */

const MIN = 60_000;
export const D54 = { avisoTrasFinMin: 30, esperaConEvidenciaMin: 15, esperaAutomaticaMin: 30 } as const;
const LOTE = 200;

type Resumen = { vencidas: number; avisosEvidencia: number; realizadasPorEvidencia: number; confirmacionesSolicitadas: number; realizadasAutomaticas: number; errores: number };

async function enTransaccion(resumen: Resumen, fn: (tx: Tx) => Promise<void>) {
  try {
    await prisma.$transaction(fn);
  } catch (error) {
    resumen.errores++;
    console.error("[tarea-ciclo]", (error as Error).message);
  }
}

async function vencer(id: number, resumen: Resumen) {
  await enTransaccion(resumen, async (tx) => {
    const s = await bloquearSolicitud(tx, id);
    const ahora = relojDominio.ahora();
    if (s.estado !== "PENDIENTE" || s.fecha_hora_programada.getTime() > ahora.getTime()) return;
    const r = await tx.solicitudes.updateMany({ where: { id, estado: "PENDIENTE" }, data: { estado: "CANCELADO", updated_at: ahora } });
    if (r.count !== 1) return;
    await tx.solicitud_trabajadores.updateMany({ where: { solicitud_id: id, estado: "PENDIENTE" }, data: { estado: "CERRADA", motivo_cierre: "VENCIDA", updated_at: ahora } });
    await tx.solicitud_historial.create({
      data: { solicitud_id: id, estado_anterior: "PENDIENTE", estado_nuevo: "CANCELADO", actor: "SISTEMA", actor_id: null, motivo: "Vencida: ningún trabajador la aceptó antes de la hora programada", created_at: ahora },
    });
    await avisarCliente(tx, s.cliente_id, {
      tipo: "SERVICIO_CANCELADO_POR_PLATAFORMA",
      clave: `VENCIDA:sol:${id}`,
      titulo: "Tu solicitud venció",
      mensaje: `Ningún colaborador aceptó ${s.servicio_nombre_aplicado ?? "tu servicio"} antes de la hora programada. Se canceló sin ningún cargo.`,
      solicitudId: id,
    });
    resumen.vencidas++;
  });
}

async function d54(id: number, resumen: Resumen) {
  await enTransaccion(resumen, async (tx) => {
    const s = await bloquearSolicitud(tx, id);
    const ahora = relojDominio.ahora();
    if (s.estado !== "EN_PROCESO" || !s.fecha_hora_fin_estimada) return;
    if (await tieneReportesActivos(tx, id)) return; // D57: decide la administración
    const t = s.fecha_hora_fin_estimada.getTime();
    const servicio = s.servicio_nombre_aplicado ?? "tu servicio";

    if (s.trabajador_marco_realizado_en && !s.cliente_marco_realizado_en) {
      if (!s.aviso_evidencia_en) {
        const momento = Math.max(t + D54.avisoTrasFinMin * MIN, s.trabajador_marco_realizado_en.getTime());
        if (ahora.getTime() < momento) return;
        const r = await tx.solicitudes.updateMany({ where: { id, estado: "EN_PROCESO", aviso_evidencia_en: null }, data: { aviso_evidencia_en: ahora, updated_at: ahora } });
        if (r.count !== 1) return;
        await avisarCliente(tx, s.cliente_id, {
          tipo: "AVISO_CONFIRMACION_CON_EVIDENCIA",
          clave: `AVISO_CONFIRMACION_CON_EVIDENCIA:sol:${id}`,
          titulo: "Confirma tu servicio",
          mensaje: `Tu colaborador terminó ${servicio} y subió fotos. Si no respondes en ${D54.esperaConEvidenciaMin} min, se dará por realizado.`,
          solicitudId: id,
        });
        resumen.avisosEvidencia++;
        return;
      }
      if (ahora.getTime() < s.aviso_evidencia_en.getTime() + D54.esperaConEvidenciaMin * MIN) return;
      const r = await tx.solicitudes.updateMany({ where: { id, estado: "EN_PROCESO" }, data: { estado: "REALIZADO", realizado_en: ahora, realizado_via: "EVIDENCIA_TRABAJADOR", updated_at: ahora } });
      if (r.count !== 1) return;
      await tx.solicitud_historial.create({
        data: { solicitud_id: id, estado_anterior: "EN_PROCESO", estado_nuevo: "REALIZADO", actor: "SISTEMA", actor_id: null, motivo: "Confirmado con la evidencia del trabajador (D54)", created_at: ahora },
      });
      await avisarCliente(tx, s.cliente_id, {
        tipo: "CALIFICAR_SERVICIO",
        clave: `CALIFICAR_SERVICIO:sol:${id}`,
        titulo: "Tu servicio se dio por realizado",
        mensaje: `${servicio} se confirmó con las fotos del colaborador. Puedes calificarlo durante 7 días.`,
        solicitudId: id,
      });
      resumen.realizadasPorEvidencia++;
      return;
    }

    if (!s.trabajador_marco_realizado_en && !s.cliente_marco_realizado_en) {
      if (!s.confirmacion_solicitada_en) {
        if (ahora.getTime() < t + D54.avisoTrasFinMin * MIN) return;
        const r = await tx.solicitudes.updateMany({ where: { id, estado: "EN_PROCESO", confirmacion_solicitada_en: null }, data: { confirmacion_solicitada_en: ahora, updated_at: ahora } });
        if (r.count !== 1) return;
        await avisarCliente(tx, s.cliente_id, {
          tipo: "CONFIRMAR_SERVICIO_REALIZADO",
          clave: `CONFIRMAR_SERVICIO_REALIZADO:sol:${id}`,
          titulo: "¿Se realizó tu servicio?",
          mensaje: `Confirma ${servicio} o repórtalo. Si nadie responde en ${D54.esperaAutomaticaMin} min, se confirmará automáticamente.`,
          solicitudId: id,
        });
        if (s.trabajador_id) {
          await avisarTrabajador(tx, s.trabajador_id, {
            tipo: "SUBIR_EVIDENCIA_SERVICIO",
            clave: `SUBIR_EVIDENCIA_SERVICIO:sol:${id}`,
            titulo: "Marca el servicio como terminado",
            mensaje: `Sube las fotos de ${servicio} para marcarlo como terminado.`,
            solicitudId: id,
          });
        }
        resumen.confirmacionesSolicitadas++;
        return;
      }
      if (ahora.getTime() < s.confirmacion_solicitada_en.getTime() + D54.esperaAutomaticaMin * MIN) return;
      const r = await tx.solicitudes.updateMany({
        where: { id, estado: "EN_PROCESO", trabajador_marco_realizado_en: null, cliente_marco_realizado_en: null },
        data: { estado: "REALIZADO", realizado_en: ahora, realizado_via: "AUTOMATICO", updated_at: ahora },
      });
      if (r.count !== 1) return;
      await tx.solicitud_historial.create({
        data: { solicitud_id: id, estado_anterior: "EN_PROCESO", estado_nuevo: "REALIZADO", actor: "SISTEMA", actor_id: null, motivo: "Confirmación automática: nadie respondió (D54)", created_at: ahora },
      });
      const aviso = { tipo: "SERVICIO_CONFIRMADO_AUTOMATICAMENTE" as const, clave: `SERVICIO_CONFIRMADO_AUTOMATICAMENTE:sol:${id}`, titulo: "Servicio confirmado automáticamente", solicitudId: id };
      await avisarCliente(tx, s.cliente_id, { ...aviso, mensaje: `${servicio} se confirmó automáticamente. Puedes calificarlo durante 7 días.` });
      if (s.trabajador_id) await avisarTrabajador(tx, s.trabajador_id, { ...aviso, mensaje: `${servicio} se confirmó automáticamente.` });
      resumen.realizadasAutomaticas++;
    }
  });
}

/** Una pasada completa. La usa el intervalo del servidor y la llaman las pruebas directamente. */
export async function ejecutarCiclo(): Promise<Resumen> {
  const resumen: Resumen = { vencidas: 0, avisosEvidencia: 0, realizadasPorEvidencia: 0, confirmacionesSolicitadas: 0, realizadasAutomaticas: 0, errores: 0 };
  const ahora = relojDominio.ahora();
  const porVencer = await prisma.solicitudes.findMany({ where: { estado: "PENDIENTE", fecha_hora_programada: { lte: ahora } }, select: { id: true }, orderBy: { id: "asc" }, take: LOTE });
  for (const { id } of porVencer) await vencer(id, resumen);
  const limite = new Date(ahora.getTime() - D54.avisoTrasFinMin * MIN);
  const enProceso = await prisma.solicitudes.findMany({
    where: { estado: "EN_PROCESO", OR: [{ fecha_hora_fin_estimada: { lte: limite } }, { trabajador_marco_realizado_en: { not: null } }] },
    select: { id: true },
    orderBy: { id: "asc" },
    take: LOTE,
  });
  for (const { id } of enProceso) await d54(id, resumen);
  return resumen;
}

/** Arranca la tarea cada `intervaloMs` (60 s). No se solapa consigo misma. Devuelve cómo detenerla. */
export function iniciarTareaCiclo(intervaloMs = 60_000): () => void {
  let corriendo = false;
  const paso = async () => {
    if (corriendo) return;
    corriendo = true;
    try {
      const r = await ejecutarCiclo();
      const cambios = r.vencidas + r.avisosEvidencia + r.realizadasPorEvidencia + r.confirmacionesSolicitadas + r.realizadasAutomaticas;
      if (cambios || r.errores) console.log("[tarea-ciclo]", JSON.stringify(r));
    } catch (error) {
      console.error("[tarea-ciclo]", (error as Error).message);
    } finally {
      corriendo = false;
    }
  };
  const temporizador = setInterval(() => void paso(), intervaloMs);
  temporizador.unref();
  void paso();
  return () => clearInterval(temporizador);
}
