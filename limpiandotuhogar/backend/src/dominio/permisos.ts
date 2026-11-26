import type { admin_permisos_permiso } from "../../generated/prisma/client";
import { prisma } from "../config/prisma";
import { AppError } from "../shared/errors/AppError";
import { registrarEvento, type Tx } from "./auditoria";
import { relojDominio } from "./reloj";

/**
 * Permisos de administrador (doc 20 §6, doc 21 §5).
 *  - MODERAR_CONTENIDO: moderar reseñas y reportes (y ver al autor, X0).
 *  - ADMINISTRAR_PERMISOS: el PROPIETARIO. Solo él otorga y revoca los permisos otorgables.
 *  - SUPERVISAR_SOLICITUDES (SQL 004, doc 25 §5): ver las solicitudes en el panel. El propietario lo
 *    tiene de forma IMPLÍCITA (sin fila propia; decisión del 2026-11-25).
 *  - GESTIONAR_INCIDENCIAS_FINANZAS (D62): resolver el servicio de una solicitud con reportes.
 * Cada otorgamiento y revocación queda en admin_permisos (historial) Y en moderacion_eventos.
 * La BD impide el auto-otorgamiento (CHECK) y dos permisos activos iguales (UNIQUE).
 * Las fechas de otorgamiento y revocación salen del MISMO reloj (relojDominio, UTC): si una
 * viniera de la BD y la otra de la app, un desfase rompería el CHECK chk_permiso_fechas.
 */
export type Permiso = admin_permisos_permiso;
export const MODERAR_CONTENIDO: Permiso = "MODERAR_CONTENIDO";
export const ADMINISTRAR_PERMISOS: Permiso = "ADMINISTRAR_PERMISOS";
export const SUPERVISAR_SOLICITUDES: Permiso = "SUPERVISAR_SOLICITUDES";
export const GESTIONAR_INCIDENCIAS_FINANZAS: Permiso = "GESTIONAR_INCIDENCIAS_FINANZAS";
/**
 * Lo que el propietario puede otorgar (y revocar) por la API a OTROS admins. REVISAR_DOCUMENTOS_IDENTIDAD
 * sigue fuera (fase de documentos) y ADMINISTRAR_PERMISOS solo por la asignación inicial.
 */
export const PERMISOS_OTORGABLES: readonly Permiso[] = [MODERAR_CONTENIDO, SUPERVISAR_SOLICITUDES, GESTIONAR_INCIDENCIAS_FINANZAS];

/**
 * El permiso VIGENTE de un admin ACTIVO, o null. Con `bloquear`, bloquea la fila (FOR UPDATE)
 * para que una revocación simultánea no se cruce con la acción que lo usa.
 */
export async function permisoVigente(tx: Tx, usuarioId: number, permiso: Permiso, opciones: { bloquear?: boolean } = {}) {
  const filas = opciones.bloquear
    ? await tx.$queryRaw<{ id: number }[]>`
        SELECT p.id FROM admin_permisos p JOIN usuarios u ON u.id = p.usuario_id
         WHERE p.usuario_id = ${usuarioId} AND p.permiso = ${permiso} AND p.revocado_en IS NULL
           AND u.rol = 'ADMIN' AND u.estado_cuenta = 'ACTIVA'
         FOR UPDATE`
    : await tx.$queryRaw<{ id: number }[]>`
        SELECT p.id FROM admin_permisos p JOIN usuarios u ON u.id = p.usuario_id
         WHERE p.usuario_id = ${usuarioId} AND p.permiso = ${permiso} AND p.revocado_en IS NULL
           AND u.rol = 'ADMIN' AND u.estado_cuenta = 'ACTIVA'`;
  const id = filas[0]?.id;
  return id === undefined ? null : Number(id);
}

/** Exige el permiso y devuelve el id de la fila con la que se actúa (para la auditoría). */
export async function exigirPermiso(tx: Tx, usuarioId: number, permiso: Permiso, opciones: { bloquear?: boolean } = {}): Promise<number> {
  const id = await permisoVigente(tx, usuarioId, permiso, opciones);
  if (id === null) throw new AppError(403, "No tienes permiso para esta acción", "PERMISO_REQUERIDO");
  return id;
}

/** Permisos vigentes de un admin, tal como están en admin_permisos (filas sin revocar). */
export async function permisosVigentes(usuarioId: number): Promise<Permiso[]> {
  const filas = await prisma.admin_permisos.findMany({
    where: { usuario_id: usuarioId, revocado_en: null },
    select: { permiso: true },
    orderBy: { id: "asc" },
  });
  return filas.map((f) => f.permiso);
}

/**
 * Permisos EFECTIVOS (para que el panel muestre solo lo que el backend permite): los vigentes y,
 * para el propietario, SUPERVISAR_SOLICITUDES implícito. Los IMPLÍCITOS se indican aparte.
 */
export async function permisosEfectivos(usuarioId: number): Promise<{ permisos: Permiso[]; implicitos: Permiso[] }> {
  const vigentes = await permisosVigentes(usuarioId);
  const implicitos: Permiso[] = vigentes.includes(ADMINISTRAR_PERMISOS) && !vigentes.includes(SUPERVISAR_SOLICITUDES) ? [SUPERVISAR_SOLICITUDES] : [];
  return { permisos: [...vigentes, ...implicitos], implicitos };
}

/**
 * ¿Puede ver las solicitudes? Con SUPERVISAR_SOLICITUDES vigente o, de forma implícita, siendo el
 * propietario (ADMINISTRAR_PERMISOS vigente). Ambos exigen cuenta ADMIN ACTIVA (permisoVigente).
 */
export async function puedeSupervisar(tx: Tx, usuarioId: number): Promise<boolean> {
  return (await permisoVigente(tx, usuarioId, SUPERVISAR_SOLICITUDES)) !== null || (await permisoVigente(tx, usuarioId, ADMINISTRAR_PERMISOS)) !== null;
}

/** Lista para el propietario: admins activos con sus permisos vigentes. */
export async function listarAdministradores() {
  const admins = await prisma.usuarios.findMany({
    where: { rol: "ADMIN" },
    select: { id: true, nombre_completo: true, correo: true, estado_cuenta: true },
    orderBy: { id: "asc" },
  });
  const permisos = await prisma.admin_permisos.findMany({
    where: { usuario_id: { in: admins.map((a) => a.id) }, revocado_en: null },
    orderBy: { id: "asc" },
  });
  return admins.map((a) => ({
    id: a.id,
    nombre: a.nombre_completo,
    correo: a.correo,
    estadoCuenta: a.estado_cuenta,
    permisos: permisos
      .filter((p) => p.usuario_id === a.id)
      .map((p) => ({ id: p.id, permiso: p.permiso, origen: p.origen, otorgadoEn: p.otorgado_en.toISOString(), otorgadoPor: p.otorgado_por })),
  }));
}

/** El propietario otorga un permiso a OTRO admin activo. Auditoría: fila + evento OTORGAR. */
export async function otorgarPermiso(propietarioId: number, datos: { usuarioId: number; permiso: Permiso; motivo: string }) {
  if (!PERMISOS_OTORGABLES.includes(datos.permiso)) {
    throw new AppError(400, "Ese permiso no se puede otorgar desde aquí", "PERMISO_NO_OTORGABLE");
  }
  if (datos.usuarioId === propietarioId) throw new AppError(403, "Nadie puede otorgarse un permiso a sí mismo", "AUTO_OTORGAMIENTO");
  return prisma.$transaction(async (tx) => {
    const permisoPropietario = await exigirPermiso(tx, propietarioId, ADMINISTRAR_PERMISOS, { bloquear: true });
    const destino = await tx.usuarios.findUnique({ where: { id: datos.usuarioId }, select: { id: true, rol: true, estado_cuenta: true } });
    if (!destino || destino.rol !== "ADMIN") throw new AppError(404, "No existe un administrador con ese id", "ADMIN_NO_ENCONTRADO");
    if (destino.estado_cuenta !== "ACTIVA") throw new AppError(409, "La cuenta del administrador está suspendida", "CUENTA_SUSPENDIDA");
    if ((await permisoVigente(tx, destino.id, datos.permiso)) !== null) {
      throw new AppError(409, "Ese administrador ya tiene el permiso", "PERMISO_YA_VIGENTE");
    }
    const creado = await tx.admin_permisos.create({
      data: { usuario_id: destino.id, permiso: datos.permiso, origen: "OTORGADO_POR_ADMIN", otorgado_por: propietarioId, motivo: datos.motivo, otorgado_en: relojDominio.ahora() },
    });
    await registrarEvento(tx, {
      actor: { adminId: propietarioId, permisoId: permisoPropietario },
      objetivo: { entidad: "PERMISO", permisoId: creado.id },
      operacion: "OTORGAR",
      antes: { usuario_id: destino.id, permiso: datos.permiso, vigente: false },
      despues: { usuario_id: destino.id, permiso: datos.permiso, vigente: true, origen: "OTORGADO_POR_ADMIN", otorgado_por: propietarioId },
      motivo: datos.motivo,
    });
    return { id: creado.id, usuarioId: destino.id, permiso: creado.permiso, otorgadoEn: creado.otorgado_en.toISOString() };
  });
}

/** El propietario revoca un permiso otorgable de OTRO admin. Auditoría: fila + evento REVOCAR. */
export async function revocarPermiso(propietarioId: number, datos: { permisoId: number; motivo: string }) {
  return prisma.$transaction(async (tx) => {
    const permisoPropietario = await exigirPermiso(tx, propietarioId, ADMINISTRAR_PERMISOS, { bloquear: true });
    const filas = await tx.$queryRaw<{ id: number }[]>`SELECT id FROM admin_permisos WHERE id = ${datos.permisoId} FOR UPDATE`;
    if (!filas.length) throw new AppError(404, "No existe ese permiso", "PERMISO_NO_ENCONTRADO");
    const permiso = await tx.admin_permisos.findUniqueOrThrow({ where: { id: datos.permisoId } });
    if (!PERMISOS_OTORGABLES.includes(permiso.permiso)) {
      throw new AppError(400, "Ese permiso no se puede revocar desde aquí", "PERMISO_NO_REVOCABLE");
    }
    if (permiso.usuario_id === propietarioId) {
      // Sin auto-otorgamiento no podría recuperarlo: se evita que el propietario se bloquee solo.
      throw new AppError(409, "No puedes revocar tu propio permiso", "AUTO_REVOCACION");
    }
    if (permiso.revocado_en) throw new AppError(409, "Ese permiso ya estaba revocado", "PERMISO_YA_REVOCADO");
    const ahora = relojDominio.ahora();
    await tx.admin_permisos.update({
      where: { id: permiso.id },
      data: { revocado_en: ahora, revocado_por: propietarioId, motivo_revocacion: datos.motivo },
    });
    await registrarEvento(tx, {
      actor: { adminId: propietarioId, permisoId: permisoPropietario },
      objetivo: { entidad: "PERMISO", permisoId: permiso.id },
      operacion: "REVOCAR",
      antes: { usuario_id: permiso.usuario_id, permiso: permiso.permiso, vigente: true },
      despues: { usuario_id: permiso.usuario_id, permiso: permiso.permiso, vigente: false, revocado_por: propietarioId, revocado_en: ahora },
      motivo: datos.motivo,
    });
    return { id: permiso.id, revocadoEn: ahora.toISOString() };
  });
}

/**
 * Asignación INICIAL auditada al propietario (D63a): ADMINISTRAR_PERMISOS + MODERAR_CONTENIDO,
 * sin otorgante, con motivo y con su evento ASIGNACION_INICIAL. Exige UNA sola cuenta ADMIN
 * ACTIVA con ese correo y que no haya otro propietario vigente. No crea cuentas ni cambia roles.
 */
export async function asignacionInicialPropietario(correo: string, motivo: string) {
  return prisma.$transaction(async (tx) => {
    const coincidencias = await tx.usuarios.findMany({ where: { correo }, select: { id: true, rol: true, estado_cuenta: true } });
    if (coincidencias.length === 0) throw new AppError(404, "No existe ninguna cuenta con ese correo", "PROPIETARIO_NO_ENCONTRADO");
    if (coincidencias.length > 1) throw new AppError(409, "Hay más de una cuenta con ese correo", "PROPIETARIO_AMBIGUO");
    const cuenta = coincidencias[0]!;
    if (cuenta.rol !== "ADMIN") throw new AppError(409, "La cuenta no es de administrador", "PROPIETARIO_NO_ES_ADMIN");
    if (cuenta.estado_cuenta !== "ACTIVA") throw new AppError(409, "La cuenta está suspendida", "PROPIETARIO_SUSPENDIDO");
    const vigentes = await tx.$queryRaw<{ n: bigint }[]>`
      SELECT COUNT(*) AS n FROM admin_permisos WHERE permiso = 'ADMINISTRAR_PERMISOS' AND revocado_en IS NULL FOR UPDATE`;
    if (Number(vigentes[0]?.n ?? 0) > 0) throw new AppError(409, "Ya hay un propietario con permisos vigentes", "PROPIETARIO_YA_ASIGNADO");
    const creados = [];
    for (const permiso of [ADMINISTRAR_PERMISOS, MODERAR_CONTENIDO]) {
      const fila = await tx.admin_permisos.create({
        data: { usuario_id: cuenta.id, permiso, origen: "ASIGNACION_INICIAL", otorgado_por: null, motivo, otorgado_en: relojDominio.ahora() },
      });
      await registrarEvento(tx, {
        actor: null,
        objetivo: { entidad: "PERMISO", permisoId: fila.id },
        operacion: "ASIGNACION_INICIAL",
        antes: { usuario_id: cuenta.id, permiso, vigente: false },
        despues: { usuario_id: cuenta.id, permiso, vigente: true, origen: "ASIGNACION_INICIAL" },
        motivo,
      });
      creados.push({ id: fila.id, permiso });
    }
    return { usuarioId: cuenta.id, permisos: creados };
  });
}
