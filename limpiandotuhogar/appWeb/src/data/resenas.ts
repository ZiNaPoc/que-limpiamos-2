import { apiFetch } from "./api";
import type { Reputacion } from "../utils/consultasDeTrabajadores";

// RESEÑAS (vista de MODERACIÓN del administrador). Especificación: docs/backend/20_ESPECIFICACION_RESENAS_Y_REPORTES.md
// Conectado a la API real (Fase 3a). Solo un admin con MODERAR_CONTENIDO recibe estas reseñas
// (el backend responde 403 sin el permiso). Es la ÚNICA vista que muestra al AUTOR (X0).
export const RESENAS_CONECTADAS_AL_BACKEND: boolean = true;

export const RUTA_DE_RESENAS_ADMIN = "/api/admin/resenas";

// Quién escribe o recibe la reseña. El cliente califica al trabajador y el trabajador al cliente.
export type RolEnLaResena = "CLIENTE" | "TRABAJADOR";

export type ParticipanteDeLaResena = {
  id: string;
  rol: RolEnLaResena;
  nombre: string;
};

// Reseña tal como la entrega GET /api/admin/resenas.
// El autor solo lo ve el administrador con el permiso MODERAR_CONTENIDO (decisión X0, doc 20 §10):
// sin él → 403. Clientes y trabajadores nunca lo reciben.
export type ResenaParaAdmin = {
  id: string;
  idSolicitud: string;
  servicio: string;
  autor: ParticipanteDeLaResena;
  calificado: ParticipanteDeLaResena;
  puntuacion: 1 | 2 | 3 | 4 | 5;
  comentario: string | null;
  fechaCreacion: string;
  // true si un administrador la corrigió (lo anterior queda en la auditoría).
  editadaPorAdministracion: boolean;
  // Eliminación LÓGICA: la reseña se conserva y deja de contar en los promedios.
  eliminada: boolean;
  eliminadaEn: string | null;
};

type RespuestaDeResenas = {
  total: number;
  resenas: ResenaParaAdmin[];
};

export type EstadoDeLasResenas =
  | { tipo: "pendiente-de-backend" }
  | { tipo: "sin-permiso" }
  | { tipo: "cargando" }
  | { tipo: "error"; mensaje: string }
  | { tipo: "listo"; resenas: ResenaParaAdmin[] };

export async function consultarResenasAdmin(opciones: { incluirEliminadas?: boolean } = {}): Promise<ResenaParaAdmin[]> {
  const datos = await apiFetch<RespuestaDeResenas>(`${RUTA_DE_RESENAS_ADMIN}${opciones.incluirEliminadas ? "?incluirEliminadas=1" : ""}`);
  return datos.resenas;
}

// Moderación. El motivo es OBLIGATORIO: el backend lo guarda en la auditoría con lo anterior y lo nuevo.
export async function corregirResena(id: string, cambios: { puntuacion?: number; comentario?: string | null }, motivo: string): Promise<void> {
  await apiFetch(`${RUTA_DE_RESENAS_ADMIN}/${encodeURIComponent(id)}`, { method: "PATCH", body: JSON.stringify({ ...cambios, motivo }) });
}

export async function eliminarResena(id: string, motivo: string): Promise<void> {
  await apiFetch(`${RUTA_DE_RESENAS_ADMIN}/${encodeURIComponent(id)}`, { method: "DELETE", body: JSON.stringify({ motivo }) });
}

export const MAX_COMENTARIO = 500;

// Promedio de las reseñas VÁLIDAS (no eliminadas) que recibió un trabajador.
export function calcularReputacionDelTrabajador(resenas: ResenaParaAdmin[], idTrabajador: string): Reputacion {
  const puntuaciones = resenas
    .filter((resena) => !resena.eliminada && resena.calificado.rol === "TRABAJADOR" && resena.calificado.id === idTrabajador)
    .map((resena) => resena.puntuacion);
  if (puntuaciones.length === 0) {
    return { promedio: null, cantidad: 0 };
  }
  const suma = puntuaciones.reduce<number>((total, puntuacion) => total + puntuacion, 0);
  return { promedio: suma / puntuaciones.length, cantidad: puntuaciones.length };
}

// Las reseñas más recientes (válidas) que recibió un trabajador.
export function ultimasResenasDelTrabajador(resenas: ResenaParaAdmin[], idTrabajador: string, cantidad: number): ResenaParaAdmin[] {
  return resenas
    .filter((resena) => !resena.eliminada && resena.calificado.rol === "TRABAJADOR" && resena.calificado.id === idTrabajador)
    .sort((a, b) => new Date(b.fechaCreacion).getTime() - new Date(a.fechaCreacion).getTime())
    .slice(0, cantidad);
}

export const MENSAJE_RESENAS_PENDIENTES =
  "Las reseñas todavía no están conectadas al backend. No se muestran datos de ejemplo.";
export const MENSAJE_SIN_PERMISO_DE_MODERACION =
  "Tu cuenta no tiene el permiso MODERAR_CONTENIDO. Solo el propietario puede otorgarlo.";
