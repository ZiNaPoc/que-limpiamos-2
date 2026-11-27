import { API_URL, apiFetch } from "./api";

// REPORTES entre usuarios — vista de MODERACIÓN (doc 20 §3–§5). Solo admins con MODERAR_CONTENIDO
// (sin él, el backend responde 403). Toda acción exige un motivo y queda en la auditoría.

export type TipoDeReporte = "NO_SE_PUDO_COMPLETAR" | "INASISTENCIA" | "PROBLEMA_UBICACION" | "UBICACION_FALSA" | "PAGO_EN_DISPUTA" | "OTRO";
export type EstadoDeReporte = "ABIERTO" | "EN_REVISION" | "RESUELTO";

export const ETIQUETA_DE_TIPO: Record<TipoDeReporte, string> = {
  NO_SE_PUDO_COMPLETAR: "No se pudo completar",
  INASISTENCIA: "Inasistencia",
  PROBLEMA_UBICACION: "Problema con la ubicación",
  UBICACION_FALSA: "Ubicación falsa",
  PAGO_EN_DISPUTA: "Pago en disputa",
  OTRO: "Otro",
};
export const ETIQUETA_DE_ESTADO: Record<EstadoDeReporte, string> = { ABIERTO: "Abierto", EN_REVISION: "En revisión", RESUELTO: "Resuelto" };

export type ParticipanteDelReporte = { id: string; rol: "CLIENTE" | "TRABAJADOR"; nombre: string };

export type ReporteParaAdmin = {
  id: string;
  idSolicitud: string;
  servicio: string;
  reportante: ParticipanteDelReporte;
  reportado: ParticipanteDelReporte;
  tipo: TipoDeReporte;
  descripcion: string | null;
  estado: EstadoDeReporte;
  fecha: string;
  cantidadFotos: number;
  editadoPorAdministracion: boolean;
  eliminado: boolean;
  // docs/backend/25 v2 §4: con la solicitud abierta, el reporte se resuelve con la resolución del servicio.
  estadoSolicitud: string | null;
  resolverConServicio: boolean;
};

export type FotoDelReporte = {
  id: string;
  tipoMime: string | null;
  tamanoBytes: number | null;
  aportadaPor: "CLIENTE" | "TRABAJADOR";
  eliminada: boolean;
  url: string | null; // URL TEMPORAL (5 min) o null si la foto se retiró
};

export type EventoDeModeracion = {
  id: string;
  operacion: string;
  admin: { id: string; nombre: string } | null;
  datosAnteriores: Record<string, unknown>;
  datosNuevos: Record<string, unknown>;
  motivo: string;
  fecha: string;
};

export type DetalleDeReporte = ReporteParaAdmin & { fotos: FotoDelReporte[]; eventos: EventoDeModeracion[] };

const RUTA = "/api/admin/reportes";

export async function consultarReportes(filtros: { estado?: EstadoDeReporte; tipo?: TipoDeReporte; incluirEliminados?: boolean }) {
  const q = new URLSearchParams();
  if (filtros.estado) q.set("estado", filtros.estado);
  if (filtros.tipo) q.set("tipo", filtros.tipo);
  if (filtros.incluirEliminados) q.set("incluirEliminados", "1");
  const texto = q.toString();
  return (await apiFetch<{ total: number; reportes: ReporteParaAdmin[] }>(`${RUTA}${texto ? `?${texto}` : ""}`)).reportes;
}

export async function consultarDetalleDeReporte(id: string): Promise<DetalleDeReporte> {
  return (await apiFetch<{ reporte: DetalleDeReporte }>(`${RUTA}/${encodeURIComponent(id)}`)).reporte;
}

// URL absoluta de una foto (la temporal es relativa al backend).
export function urlDeFoto(foto: FotoDelReporte): string | null {
  return foto.url ? `${API_URL}${foto.url}` : null;
}

const enviar = (ruta: string, metodo: string, cuerpo: Record<string, unknown>) =>
  apiFetch(`${RUTA}${ruta}`, { method: metodo, body: JSON.stringify(cuerpo) });

export const accionesDeReporte = {
  cambiarEstado: (id: string, estado: "ABIERTO" | "EN_REVISION", motivo: string) => enviar(`/${id}/estado`, "POST", { estado, motivo }),
  agregarNota: (id: string, nota: string) => enviar(`/${id}/seguimiento`, "POST", { nota }),
  editar: (id: string, cambios: { tipo?: TipoDeReporte; descripcion?: string | null }, motivo: string) => enviar(`/${id}`, "PATCH", { ...cambios, motivo }),
  retirarFoto: (id: string, fotoId: string, motivo: string) => enviar(`/${id}/fotos/${fotoId}`, "DELETE", { motivo }),
  resolver: (id: string, resolucion: string) => enviar(`/${id}/resolucion`, "POST", { resolucion }),
  eliminar: (id: string, motivo: string) => enviar(`/${id}`, "DELETE", { motivo }),
};
