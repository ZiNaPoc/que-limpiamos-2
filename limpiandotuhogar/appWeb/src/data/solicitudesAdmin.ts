import { API_URL, apiFetch } from "./api";

// Supervisión de solicitudes (docs/backend/25 v2 §5 y §7.2). Solo LECTURA: el panel no asigna,
// reasigna, confirma, finaliza ni cancela solicitudes (D24). La única intervención es la
// resolución del servicio cuando hay un reporte, con el permiso de incidencias.

export type EstadoApi = "PENDIENTE" | "CONFIRMADO" | "EN_PROCESO" | "REALIZADO" | "CANCELADO" | "RECHAZADO";
export type ModoApi = "INVITACION" | "BOLSA";
export type AlertaApi = "REPORTE_ACTIVO" | "SIN_INICIAR" | "ESPERANDO_CONFIRMACION" | "POR_VENCER";

export const ETIQUETA_DE_ESTADO: Record<EstadoApi, string> = {
  PENDIENTE: "Pendiente",
  CONFIRMADO: "Confirmado",
  EN_PROCESO: "En proceso",
  REALIZADO: "Realizado",
  CANCELADO: "Cancelado",
  RECHAZADO: "Rechazado",
};

export const ETIQUETA_DE_MODO: Record<ModoApi, string> = { INVITACION: "Invitación", BOLSA: "Bolsa abierta" };

export const ETIQUETA_DE_ALERTA: Record<AlertaApi, string> = {
  REPORTE_ACTIVO: "Reporte activo",
  SIN_INICIAR: "Sin iniciar (más de 30 min tarde)",
  ESPERANDO_CONFIRMACION: "Esperando confirmación",
  POR_VENCER: "Vence en menos de 2 h",
};

export const ETIQUETA_DE_ESTADO_DEL_TRABAJADOR: Record<string, string> = {
  PENDIENTE: "Invitación pendiente",
  ACEPTADA: "Aceptó",
  RECHAZADA: "Rechazó",
  CERRADA: "Cerrada",
  CANCELADA: "Canceló",
};

export const ETIQUETA_DE_MOTIVO_DE_CIERRE: Record<string, string> = {
  OTRO_TRABAJADOR_ACEPTO: "otro colaborador aceptó",
  CLIENTE_CANCELO: "el cliente canceló",
  CAMBIO_A_AUTOMATICA: "se envió a la bolsa",
  TRABAJADOR_OCUPADO: "ocupado en ese horario",
  TRABAJADOR_CANCELO: "el colaborador canceló",
  TRABAJADOR_DADO_DE_BAJA: "colaborador dado de baja",
  VENCIDA: "la solicitud venció",
};

export const ETIQUETA_DE_ACTOR: Record<string, string> = { CLIENTE: "Cliente", TRABAJADOR: "Colaborador", ADMIN: "Administración", SISTEMA: "Sistema" };

export const ETIQUETA_DE_VIA: Record<string, string> = {
  CLIENTE: "confirmado por el cliente",
  EVIDENCIA_TRABAJADOR: "con la evidencia del colaborador",
  AUTOMATICO: "confirmación automática",
  RESOLUCION_ADMIN: "resolución administrativa",
};

export type SolicitudEnLista = {
  id: number;
  estado: EstadoApi;
  modo: ModoApi;
  servicio: string;
  direccion: string;
  fechaProgramada: string;
  finEstimado: string | null;
  creadaEn: string;
  precio: number;
  cliente: { id: number; nombre: string; correo: string; telefono: string | null };
  trabajador: { id: number; nombre: string; estado: string } | null;
  invitaciones: { pendientes: number; rechazadas: number };
  reportesActivos: number;
  alertas: AlertaApi[];
};

export type ListadoDeSupervision = { total: number; pagina: number; tamano: number; actualizadoEn: string; solicitudes: SolicitudEnLista[] };

export type FotoDeSolicitud = { id: number; tipoMime: string | null; tamanoBytes: number | null; fecha?: string };

export type DetalleDeSupervision = {
  id: number;
  estado: EstadoApi;
  modo: ModoApi;
  servicio: string;
  fechaProgramada: string;
  finEstimado: string | null;
  duracionMin: number | null;
  creadaEn: string;
  actualizadoEn: string;
  direccion: string;
  inmueble: { nombre: string | null; tipo: string | null; habitaciones: number | null; banos: number | null; mediosBanos: number | null; pisos: number | null; guardado: boolean };
  notas: string | null;
  areas: string[];
  extras: { nombre: string; precio: number; duracionMin: number }[];
  especialidades: string[];
  precio: { total: number; base: number; extras: number; metodoPago: string; estadoPago: string };
  cliente: { id: number; nombre: string; correo: string; telefono: string | null; verificacion: string | null };
  trabajador: { id: number; nombre: string; estado: string; telefono: string } | null;
  trabajadores: { trabajador: { id: number; nombre: string }; origen: "INVITACION" | "BOLSA"; estado: string; motivoCierre: string | null; creadaEn: string; respondidaEn: string | null }[];
  historial: { fecha: string; estadoAnterior: EstadoApi | null; estadoNuevo: EstadoApi; actor: string; actorNombre: string; motivo: string | null }[];
  marcas: {
    trabajadorTerminoEn: string | null;
    clienteConfirmoEn: string | null;
    confirmacionSolicitadaEn: string | null;
    avisoEvidenciaEn: string | null;
    realizadoEn: string | null;
    realizadoVia: string | null;
  };
  fotosTerminado: FotoDeSolicitud[];
  verContenidoDeReportes: boolean;
  reportes: { id: number; reportadoPor: "CLIENTE" | "TRABAJADOR"; tipo: string; estado: string; fecha: string; eliminado: boolean; activo: boolean; descripcion?: string | null; fotos?: FotoDeSolicitud[] }[];
  resolucion: { id: number; resultadoServicio: "REALIZADO" | "NO_REALIZADO"; motivo: string; admin: string; fecha: string } | null;
  alertas: AlertaApi[];
  puedeResolver: boolean;
};

export type FiltrosDeSupervision = { estado: EstadoApi | ""; modo: ModoApi | ""; busqueda: string; desde: string; hasta: string; atencion: boolean };

export const FILTROS_DE_SUPERVISION_VACIOS: FiltrosDeSupervision = { estado: "", modo: "", busqueda: "", desde: "", hasta: "", atencion: false };

const RUTA = "/api/admin/solicitudes";

export async function consultarSolicitudes(filtros: FiltrosDeSupervision, tamano = 100): Promise<ListadoDeSupervision> {
  const q = new URLSearchParams({ tamano: String(tamano) });
  if (filtros.estado) q.set("estado", filtros.estado);
  if (filtros.modo) q.set("modo", filtros.modo);
  if (filtros.busqueda.trim()) q.set("q", filtros.busqueda.trim());
  // Las fechas del filtro son días locales: desde el inicio del primero hasta el final del último.
  if (filtros.desde) q.set("desde", new Date(`${filtros.desde}T00:00:00`).toISOString());
  if (filtros.hasta) q.set("hasta", new Date(`${filtros.hasta}T23:59:59`).toISOString());
  if (filtros.atencion) q.set("atencion", "1");
  return apiFetch<ListadoDeSupervision>(`${RUTA}?${q.toString()}`);
}

export async function consultarDetalle(id: number): Promise<DetalleDeSupervision> {
  return (await apiFetch<{ solicitud: DetalleDeSupervision }>(`${RUTA}/${id}`)).solicitud;
}

/** URL absoluta y temporal (60 s) de una foto de la solicitud. */
export async function urlDeFotoDeSolicitud(idSolicitud: number, idFoto: number): Promise<string> {
  const r = await apiFetch<{ url: string }>(`${RUTA}/${idSolicitud}/evidencias/${idFoto}`);
  return `${API_URL}${r.url}`;
}

/** Resolución del servicio: inmutable; si otro admin resolvió antes, el backend responde 409. */
export async function resolverServicio(idSolicitud: number, resultadoServicio: "REALIZADO" | "NO_REALIZADO", motivo: string) {
  return apiFetch<{ resolucion: { id: number } }>(`${RUTA}/${idSolicitud}/resolucion`, { method: "POST", body: JSON.stringify({ resultadoServicio, motivo }) });
}
