import { useCallback, useEffect, useState } from "react";

import { BarraDeFiltrosDeSolicitudes } from "../components/solicitudes/BarraDeFiltrosDeSolicitudes";
import { DetalleDeSolicitud } from "../components/solicitudes/DetalleDeSolicitud";
import { ListaDeSolicitudes } from "../components/solicitudes/ListaDeSolicitudes";
import { FormaOrganica } from "../components/comunes/FormasOrganicas";
import { Icono } from "../components/comunes/Icono";
import { usePermisos } from "../data/permisos";
import { consultarSolicitudes, FILTROS_DE_SUPERVISION_VACIOS, type FiltrosDeSupervision, type ListadoDeSupervision } from "../data/solicitudesAdmin";
import { INTERVALO_DE_ACTUALIZACION_MS } from "../data/SolicitudesProvider";
import type { AperturaDelPanel, FiltrosDeSolicitudes, Navegar } from "../data/tipos";
import { useActualizacionPeriodica } from "../hooks/useActualizacionPeriodica";
import { useAhora } from "../hooks/useAhora";
import { haceCuanto } from "../utils/fechasDeSolicitudes";

type SolicitudesPageProps = {
  apertura: AperturaDelPanel;
  onNavegar: Navegar;
};

// Filtros con los que llegan los atajos de Inicio (formato anterior) → filtros del backend.
function filtrosDesdeApertura(f?: FiltrosDeSolicitudes): FiltrosDeSupervision {
  if (!f) return FILTROS_DE_SUPERVISION_VACIOS;
  const hoy = new Date().toLocaleDateString("en-CA");
  return {
    ...FILTROS_DE_SUPERVISION_VACIOS,
    busqueda: f.busqueda,
    estado: f.etapa === "Solicitud enviada" || f.etapa === "Asignando colaborador" ? "PENDIENTE" : f.etapa === "Servicio confirmado" ? "CONFIRMADO" : f.etapa === "Servicio en proceso" ? "EN_PROCESO" : "",
    desde: f.fechaDelTrabajo === "hoy" ? hoy : "",
    hasta: f.fechaDelTrabajo === "hoy" ? hoy : "",
  };
}

// Supervisión de las solicitudes REALES (docs/backend/25 v2 §7.2): filtros en el backend,
// actualización cada 20 s con la página visible y el detalle de cada una.
export function SolicitudesPage({ apertura, onNavegar }: SolicitudesPageProps) {
  const { tiene, cargando: cargandoPermisos } = usePermisos();
  const ahora = useAhora(10_000);
  const [filtros, setFiltros] = useState<FiltrosDeSupervision>(() => ({ ...filtrosDesdeApertura(apertura.filtrosDeSolicitudes), atencion: apertura.soloAtencion ?? false }));
  const [datos, setDatos] = useState<ListadoDeSupervision | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const [idAbierta, setIdAbierta] = useState<number | null>(apertura.idDeSolicitud ? Number(apertura.idDeSolicitud) : null);
  const puedeVer = tiene("SUPERVISAR_SOLICITUDES");

  const cargar = useCallback(async () => {
    try {
      setDatos(await consultarSolicitudes(filtros));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudieron cargar las solicitudes");
    } finally {
      setCargando(false);
    }
  }, [filtros]);

  // Los filtros de texto esperan un momento antes de consultar.
  useEffect(() => {
    if (!puedeVer) return;
    const t = window.setTimeout(() => void cargar(), 300);
    return () => window.clearTimeout(t);
  }, [cargar, puedeVer]);
  useActualizacionPeriodica(cargar, INTERVALO_DE_ACTUALIZACION_MS, puedeVer && idAbierta === null);

  if (cargandoPermisos) return <p className="rounded-2xl bg-white p-8 text-center text-sm text-slate">Cargando…</p>;
  if (!puedeVer) {
    return (
      <div role="alert" className="rounded-2xl border border-mist bg-white p-8 text-center">
        <p className="font-bold text-navy">No tienes permiso para supervisar solicitudes</p>
        <p className="mt-2 text-sm text-slate">Pídeselo al propietario de la cuenta (permiso «Supervisar solicitudes»).</p>
      </div>
    );
  }

  if (idAbierta !== null) {
    return (
      <DetalleDeSolicitud
        idSolicitud={idAbierta}
        onNavegar={onNavegar}
        onVolver={() => {
          setIdAbierta(null);
          void cargar();
        }}
      />
    );
  }

  const solicitudes = datos?.solicitudes ?? [];
  return (
    <div>
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-4xl font-extrabold text-navy">Gestión de solicitudes</h1>
          <p className="mt-2 max-w-3xl text-sm text-slate">
            Solicitudes reales que los clientes envían desde la app: estado, invitaciones o bolsa, seguimiento y reportes. El panel supervisa; no asigna ni cambia el estado de las solicitudes.
          </p>
        </div>
        <div className="flex items-center gap-3 text-xs text-slate">
          <span aria-live="polite">{datos ? `Actualizado ${haceCuanto(datos.actualizadoEn, ahora)}` : "Cargando…"} · cada 20 s</span>
          <button onClick={() => void cargar()} className="btn btn-quiet">
            <Icono nombre="restablecer" /> Actualizar
          </button>
        </div>
      </div>

      <div className="mt-8">
        <BarraDeFiltrosDeSolicitudes
          filtros={filtros}
          total={datos?.total ?? 0}
          visibles={solicitudes.length}
          onCambiarFiltros={setFiltros}
          onRestablecerFiltros={() => setFiltros(FILTROS_DE_SUPERVISION_VACIOS)}
        />
      </div>

      <div className="mt-6">
        {cargando && !datos && <div className="rounded-2xl bg-white p-8 text-center text-sm text-slate">Cargando solicitudes...</div>}
        {error && (
          <div role="alert" className="mb-4 rounded-2xl border border-red-200 bg-white p-6 text-center">
            <p className="font-bold text-err">No se pudieron cargar las solicitudes</p>
            <p className="mt-2 text-sm text-slate">{error}</p>
            <button onClick={() => void cargar()} className="btn btn-primary mt-4">
              Reintentar
            </button>
          </div>
        )}
        {datos && solicitudes.length === 0 && (
          <div className="leaf relative overflow-hidden border border-dashed border-frost bg-white/70 p-12 text-center">
            <FormaOrganica className="-right-10 -top-12 h-44 w-44 text-sky/70" />
            <div className="relative">
              <p className="font-display text-2xl font-extrabold text-navy">No encontramos solicitudes</p>
              <p className="mx-auto mt-2 max-w-sm text-sm text-slate">Prueba con otra búsqueda o quita algunos filtros.</p>
            </div>
          </div>
        )}
        {solicitudes.length > 0 && <ListaDeSolicitudes solicitudes={solicitudes} onAbrir={setIdAbierta} />}
        {datos && datos.total > solicitudes.length && <p className="mt-3 text-center text-xs text-slate">Se muestran las {solicitudes.length} más recientes de {datos.total}. Usa los filtros para acotar.</p>}
      </div>
    </div>
  );
}
