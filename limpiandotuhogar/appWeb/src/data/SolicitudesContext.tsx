import { createContext } from "react";

import type { SolicitudListado } from "./tipos";

// Solicitudes REALES (GET /api/admin/solicitudes) en el formato que usan Inicio y Colaboradores.
// La pantalla de Solicitudes consulta el backend por su cuenta, con filtros y detalle.
// El panel NO asigna, confirma, finaliza ni cancela solicitudes (D24, docs/backend/25 v2): no hay
// acciones aquí. La única intervención es la resolución del servicio (en el detalle).
export type ValorDelContextoDeSolicitudes = {
  solicitudes: SolicitudListado[];
  cargando: boolean;
  errorCarga: string | null;
  // Fecha (ISO) de la última consulta correcta al backend.
  actualizadoEn: string | null;
  // false si el admin no tiene SUPERVISAR_SOLICITUDES (no se consulta nada).
  puedeVer: boolean;
  recargarSolicitudes: () => Promise<void>;
};

export const SolicitudesContext = createContext<ValorDelContextoDeSolicitudes | null>(null);
