import { useCallback, useState, type ReactNode } from "react";

import { useActualizacionPeriodica } from "../hooks/useActualizacionPeriodica";
import { usePermisos } from "./permisos";
import { SolicitudesContext } from "./SolicitudesContext";
import { consultarSolicitudes, ETIQUETA_DE_ESTADO, FILTROS_DE_SUPERVISION_VACIOS, type SolicitudEnLista } from "./solicitudesAdmin";

import type { EstadoDeSolicitud, SolicitudListado } from "./tipos";

// Cada 20 s, solo con la página visible (docs/backend/25 v2).
export const INTERVALO_DE_ACTUALIZACION_MS = 20_000;

// Formato que ya usaban Inicio y Colaboradores (estados en español).
function aListado(s: SolicitudEnLista): SolicitudListado {
  return {
    id: String(s.id),
    idCliente: String(s.cliente.id),
    idServicio: "",
    idTrabajador: s.trabajador ? String(s.trabajador.id) : null,
    servicio: s.servicio,
    direccion: s.direccion,
    estado: ETIQUETA_DE_ESTADO[s.estado] as EstadoDeSolicitud,
    fechaCreacion: s.creadaEn,
    fechaProgramada: s.fechaProgramada,
    precioReferencia: s.precio,
    cliente: { id: String(s.cliente.id), nombre: s.cliente.nombre, correo: s.cliente.correo, telefono: s.cliente.telefono },
    trabajador: s.trabajador ? { id: String(s.trabajador.id), nombre: s.trabajador.nombre, estado: s.trabajador.estado === "ACTIVO" ? "ACTIVO" : "INACTIVO" } : null,
  };
}

export function SolicitudesProvider({ children }: { children: ReactNode }) {
  const { tiene, cargando: cargandoPermisos } = usePermisos();
  const puedeVer = tiene("SUPERVISAR_SOLICITUDES");
  const [solicitudes, setSolicitudes] = useState<SolicitudListado[]>([]);
  const [cargandoDatos, setCargando] = useState(true);
  // Sin el permiso no se consulta nada: no hay nada que esperar.
  const cargando = puedeVer ? cargandoDatos : cargandoPermisos;
  const [errorCarga, setErrorCarga] = useState<string | null>(null);
  const [actualizadoEn, setActualizadoEn] = useState<string | null>(null);

  const recargarSolicitudes = useCallback(async () => {
    if (!puedeVer) return;
    try {
      const datos = await consultarSolicitudes(FILTROS_DE_SUPERVISION_VACIOS, 100);
      setSolicitudes(datos.solicitudes.map(aListado));
      setActualizadoEn(datos.actualizadoEn);
      setErrorCarga(null);
    } catch (error) {
      setErrorCarga(error instanceof Error ? error.message : "No se pudieron cargar las solicitudes");
    } finally {
      setCargando(false);
    }
  }, [puedeVer]);

  useActualizacionPeriodica(recargarSolicitudes, INTERVALO_DE_ACTUALIZACION_MS, puedeVer && !cargandoPermisos, true);

  return (
    <SolicitudesContext.Provider value={{ solicitudes, cargando, errorCarga, actualizadoEn, puedeVer, recargarSolicitudes }}>{children}</SolicitudesContext.Provider>
  );
}
