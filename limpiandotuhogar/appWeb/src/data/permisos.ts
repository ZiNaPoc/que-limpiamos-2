import { createContext, useContext } from "react";

import { apiFetch } from "./api";

// Permisos EFECTIVOS del admin que inició sesión, tal como los devuelve el backend
// (GET /api/admin/permisos/mios). El propietario tiene SUPERVISAR_SOLICITUDES de forma implícita.
// El panel solo MUESTRA u OCULTA según esto; quien decide es el backend (responde 403 sin permiso).
export type PermisoDeAdmin =
  | "MODERAR_CONTENIDO"
  | "ADMINISTRAR_PERMISOS"
  | "GESTIONAR_INCIDENCIAS_FINANZAS"
  | "REVISAR_DOCUMENTOS_IDENTIDAD"
  | "SUPERVISAR_SOLICITUDES";

export const ETIQUETA_DE_PERMISO: Record<PermisoDeAdmin, string> = {
  SUPERVISAR_SOLICITUDES: "Supervisar solicitudes",
  GESTIONAR_INCIDENCIAS_FINANZAS: "Incidencias y finanzas",
  MODERAR_CONTENIDO: "Moderar reseñas y reportes",
  ADMINISTRAR_PERMISOS: "Propietario (administra permisos)",
  REVISAR_DOCUMENTOS_IDENTIDAD: "Revisar documentos de identidad",
};

// Los que el propietario puede otorgar y revocar desde el panel (el backend decide igual).
export const PERMISOS_OTORGABLES: PermisoDeAdmin[] = ["SUPERVISAR_SOLICITUDES", "GESTIONAR_INCIDENCIAS_FINANZAS", "MODERAR_CONTENIDO"];

export async function consultarMisPermisos(): Promise<{ permisos: PermisoDeAdmin[]; implicitos: PermisoDeAdmin[] }> {
  const datos = await apiFetch<{ permisos: PermisoDeAdmin[]; implicitos?: PermisoDeAdmin[] }>("/api/admin/permisos/mios");
  return { permisos: datos.permisos, implicitos: datos.implicitos ?? [] };
}

export type AdministradorConPermisos = {
  id: number;
  nombre: string;
  correo: string;
  estadoCuenta: string;
  permisos: { id: number; permiso: PermisoDeAdmin; origen: string; otorgadoEn: string; otorgadoPor: number | null }[];
};

export async function consultarAdministradores(): Promise<AdministradorConPermisos[]> {
  return (await apiFetch<{ administradores: AdministradorConPermisos[] }>("/api/admin/permisos")).administradores;
}

export async function otorgarPermiso(usuarioId: number, permiso: PermisoDeAdmin, motivo: string) {
  return apiFetch("/api/admin/permisos", { method: "POST", body: JSON.stringify({ usuarioId, permiso, motivo }) });
}

export async function revocarPermiso(permisoId: number, motivo: string) {
  return apiFetch(`/api/admin/permisos/${permisoId}/revocar`, { method: "POST", body: JSON.stringify({ motivo }) });
}

export type ValorDelContextoDePermisos = {
  cargando: boolean;
  error: string | null;
  permisos: PermisoDeAdmin[];
  implicitos: PermisoDeAdmin[];
  tiene: (permiso: PermisoDeAdmin) => boolean;
};

export const PermisosContext = createContext<ValorDelContextoDePermisos | null>(null);

export function usePermisos(): ValorDelContextoDePermisos {
  const valor = useContext(PermisosContext);
  if (!valor) throw new Error("usePermisos debe usarse dentro de PermisosProvider");
  return valor;
}
