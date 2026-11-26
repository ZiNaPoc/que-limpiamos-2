import type { Prisma } from "../../generated/prisma/client";
import type { Cuerpo } from "../shared/validation/campos";
import { AppError } from "../shared/errors/AppError";

/**
 * Auditoría de moderación y de permisos (tabla moderacion_eventos, doc 20 §5 y doc 21 §6).
 *
 * INMUTABLE POR DISEÑO: este módulo es el ÚNICO que escribe en moderacion_eventos y SOLO crea
 * filas. No existe ninguna función, ruta ni consulta que la actualice o la borre (lo vigila
 * test/auditoria-estatica.test.ts). TiDB no tiene triggers, así que la protección es: este
 * código + FK RESTRICT + CHECK de la tabla (+ cuenta de BD por tabla en producción, doc 21 §6).
 */

export type Tx = Prisma.TransactionClient;
export type Actor = { adminId: number; permisoId: number } | null;
export type Objetivo = { entidad: "RESENA"; resenaId: number } | { entidad: "REPORTE"; reporteId: number } | { entidad: "PERMISO"; permisoId: number };
export type Operacion =
  | "EDITAR"
  | "ELIMINAR"
  | "CAMBIAR_ESTADO"
  | "RESOLVER"
  | "NOTA"
  | "OTORGAR"
  | "REVOCAR"
  | "ASIGNACION_INICIAL";

export const MAX_MOTIVO = 500;

/** Motivo obligatorio (1–500 caracteres) de toda modificación administrativa. */
export function leerMotivo(cuerpo: Cuerpo, campo = "motivo"): string {
  const valor = cuerpo[campo];
  const texto = typeof valor === "string" ? valor.trim() : "";
  if (!texto) throw new AppError(400, "Escribe el motivo de la modificación", "MOTIVO_REQUERIDO");
  if ([...texto].length > MAX_MOTIVO) throw new AppError(400, `El motivo admite como máximo ${MAX_MOTIVO} caracteres`, "MOTIVO_LARGO");
  return texto;
}

/** Convierte valores (Date, bigint, Decimal) a JSON plano para guardar antes/después. */
function plano(datos: Record<string, unknown>): Prisma.InputJsonObject {
  return JSON.parse(
    JSON.stringify(datos, (_k, v: unknown) => (typeof v === "bigint" ? Number(v) : v instanceof Date ? v.toISOString() : v)),
  ) as Prisma.InputJsonObject;
}

/** Registra UN evento. Debe llamarse dentro de la MISMA transacción que el cambio. */
export async function registrarEvento(
  tx: Tx,
  evento: { actor: Actor; objetivo: Objetivo; operacion: Operacion; antes: Record<string, unknown>; despues: Record<string, unknown>; motivo: string },
): Promise<number> {
  const { objetivo } = evento;
  const creado = await tx.moderacion_eventos.create({
    data: {
      admin_id: evento.actor?.adminId ?? null,
      admin_permiso_id: evento.actor?.permisoId ?? null,
      entidad: objetivo.entidad,
      resena_id: objetivo.entidad === "RESENA" ? objetivo.resenaId : null,
      reporte_id: objetivo.entidad === "REPORTE" ? objetivo.reporteId : null,
      permiso_id: objetivo.entidad === "PERMISO" ? objetivo.permisoId : null,
      operacion: evento.operacion,
      datos_anteriores: plano(evento.antes),
      datos_nuevos: plano(evento.despues),
      motivo: evento.motivo,
    },
    select: { id: true },
  });
  return creado.id;
}
