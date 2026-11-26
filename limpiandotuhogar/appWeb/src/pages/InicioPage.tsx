import { useCallback, useState } from "react";

import { Icono, type NombreDeIcono } from "../components/comunes/Icono";
import { OlasDeFondo } from "../components/comunes/FormasOrganicas";
import { usePermisos } from "../data/permisos";
import { consultarResumen, type Resumen } from "../data/plataforma";
import { ETIQUETA_DE_ALERTA, ETIQUETA_DE_ESTADO, type AlertaApi, type EstadoApi } from "../data/solicitudesAdmin";
import { INTERVALO_DE_ACTUALIZACION_MS } from "../data/SolicitudesProvider";
import type { Navegar, Sesion } from "../data/tipos";
import { useActualizacionPeriodica } from "../hooks/useActualizacionPeriodica";
import { useAhora } from "../hooks/useAhora";
import { useSolicitudes } from "../hooks/useSolicitudes";
import { formatearFechaYHora, haceCuanto } from "../utils/fechasDeSolicitudes";
import { formatearFechaDeHoy } from "../utils/formato";

type Indicador = { etiqueta: string; valor: number; detalle: string; icono: NombreDeIcono; boton?: { texto: string; onClick: () => void }; destacar?: boolean };

function TarjetaIndicador({ i }: { i: Indicador }) {
  return (
    <div className={`surface leaf-sm flex flex-col p-6 ${i.destacar ? "ring-2 ring-err/40" : ""}`}>
      <div className="flex items-center justify-between">
        <span className="grid h-10 w-10 place-items-center rounded-full bg-moon text-navy">
          <Icono nombre={i.icono} />
        </span>
        <span className="font-display text-4xl font-extrabold text-navy">{i.valor}</span>
      </div>
      <p className="mt-4 font-bold text-navy">{i.etiqueta}</p>
      <p className="mt-1 text-xs text-slate">{i.detalle}</p>
      {i.boton && (
        <button onClick={i.boton.onClick} className="mt-4 w-fit cursor-pointer text-sm font-bold text-lagoon hover:underline">
          {i.boton.texto} →
        </button>
      )}
    </div>
  );
}

// Inicio con datos REALES (GET /api/admin/resumen y las solicitudes reales). Se actualiza cada 20 s
// con la página visible. Sin datos de demostración.
export function InicioPage({ sesion, onNavegar }: { sesion: Sesion; onNavegar: Navegar }) {
  const ahora = useAhora(10_000);
  const { tiene } = usePermisos();
  const { solicitudes, puedeVer } = useSolicitudes();
  const [r, setR] = useState<Resumen | null>(null);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    try {
      setR(await consultarResumen());
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo cargar el resumen");
    }
  }, []);
  useActualizacionPeriodica(cargar, INTERVALO_DE_ACTUALIZACION_MS, true, true);

  const supervisa = tiene("SUPERVISAR_SOLICITUDES");
  const irASolicitudes = (atencion = false) => onNavegar("solicitudes", atencion ? { soloAtencion: true } : {});
  const e = r?.solicitudes.porEstado ?? {};
  const indicadores: Indicador[] = r
    ? [
        {
          etiqueta: "Solicitudes activas",
          valor: (e.PENDIENTE ?? 0) + (e.CONFIRMADO ?? 0) + (e.EN_PROCESO ?? 0),
          detalle: `${e.PENDIENTE ?? 0} pendientes · ${e.CONFIRMADO ?? 0} confirmadas · ${e.EN_PROCESO ?? 0} en proceso`,
          icono: "bandeja",
          boton: supervisa ? { texto: "Ver solicitudes", onClick: () => irASolicitudes() } : undefined,
        },
        {
          etiqueta: "Requieren atención",
          valor: r.solicitudes.requierenAtencion,
          detalle: (Object.entries(r.solicitudes.alertas) as [AlertaApi, number][]).filter(([, n]) => n > 0).map(([a, n]) => `${n} ${ETIQUETA_DE_ALERTA[a].toLowerCase()}`).join(" · ") || "Nada pendiente",
          icono: "alerta",
          destacar: r.solicitudes.requierenAtencion > 0,
          boton: supervisa ? { texto: "Revisar", onClick: () => irASolicitudes(true) } : undefined,
        },
        {
          etiqueta: "Colaboradores disponibles",
          valor: r.trabajadores.disponibles,
          detalle: `Activos y verificados, de ${r.trabajadores.total} registrados`,
          icono: "trabajadores",
          boton: supervisa ? { texto: "Ver colaboradores", onClick: () => onNavegar("trabajadores") } : undefined,
        },
        {
          etiqueta: "Clientes",
          valor: r.clientes.total,
          detalle: `${r.clientes.verificados} con identidad verificada`,
          icono: "clientes",
          boton: supervisa ? { texto: "Ver clientes", onClick: () => onNavegar("clientes") } : undefined,
        },
        {
          etiqueta: "Reportes abiertos",
          valor: r.reportesAbiertos,
          detalle: "Sin resolver ni eliminar",
          icono: "reportes",
          destacar: r.reportesAbiertos > 0,
          boton: tiene("MODERAR_CONTENIDO") ? { texto: "Ver reportes", onClick: () => onNavegar("reportes") } : undefined,
        },
        {
          etiqueta: "Reseñas publicadas",
          valor: r.resenas,
          detalle: "Clientes y colaboradores",
          icono: "estrella",
          boton: tiene("MODERAR_CONTENIDO") ? { texto: "Ver reseñas", onClick: () => onNavegar("resenas") } : undefined,
        },
      ]
    : [];
  const recientes = [...solicitudes].sort((a, b) => new Date(b.fechaCreacion).getTime() - new Date(a.fechaCreacion).getTime()).slice(0, 5);

  return (
    <div className="space-y-12">
      <header className="leaf rise relative overflow-hidden bg-storm px-7 pb-10 pt-8 text-white shadow-lift sm:px-12 sm:pb-14 sm:pt-10">
        <OlasDeFondo />
        <div className="relative max-w-xl">
          <p className="text-sm font-semibold text-moss first-letter:uppercase">{formatearFechaDeHoy(ahora)}</p>
          <h1 className="mt-3 text-4xl font-extrabold leading-tight sm:text-5xl">
            ¡Bienvenido de nuevo, <span className="text-moss">{sesion.nombre}</span>!
          </h1>
          <p className="mt-4 text-sm text-frost">{r ? `Datos reales · actualizado ${haceCuanto(r.actualizadoEn, ahora)} · cada 20 s` : "Cargando…"}</p>
        </div>
      </header>

      {error && (
        <div role="alert" className="rounded-2xl border border-red-200 bg-white p-6 text-center">
          <p className="font-bold text-err">No se pudo cargar el resumen</p>
          <p className="mt-1 text-sm text-slate">{error}</p>
          <button onClick={() => void cargar()} className="btn btn-primary mt-4">
            Reintentar
          </button>
        </div>
      )}

      <section aria-labelledby="titulo-indicadores">
        <h2 id="titulo-indicadores" className="font-display text-2xl font-extrabold text-navy">
          Indicadores principales
        </h2>
        <div className="mt-6 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {!r && !error && <p className="text-sm text-slate">Cargando indicadores…</p>}
          {indicadores.map((i) => (
            <TarjetaIndicador key={i.etiqueta} i={i} />
          ))}
        </div>
      </section>

      {r && (
        <section aria-labelledby="titulo-estados" className="surface leaf-sm p-6">
          <h2 id="titulo-estados" className="font-display text-xl font-extrabold text-navy">
            Solicitudes por estado
          </h2>
          <div className="mt-4 flex flex-wrap gap-3">
            {(Object.keys(ETIQUETA_DE_ESTADO) as EstadoApi[]).map((estado) => (
              <span key={estado} className="rounded-full bg-moon px-4 py-2 text-sm text-navy">
                {ETIQUETA_DE_ESTADO[estado]}: <strong>{e[estado] ?? 0}</strong>
              </span>
            ))}
          </div>
        </section>
      )}

      {puedeVer && (
        <section aria-labelledby="titulo-recientes" className="surface leaf-sm p-6">
          <div className="flex items-center justify-between">
            <h2 id="titulo-recientes" className="font-display text-xl font-extrabold text-navy">
              Solicitudes recientes
            </h2>
            <button onClick={() => irASolicitudes()} className="cursor-pointer text-sm font-bold text-lagoon hover:underline">
              Ver todas →
            </button>
          </div>
          {recientes.length === 0 ? (
            <p className="mt-4 text-sm text-slate">Todavía no hay solicitudes.</p>
          ) : (
            <ul className="mt-4 divide-y divide-mist/70">
              {recientes.map((s) => (
                <li key={s.id}>
                  <button onClick={() => onNavegar("solicitudes", { idDeSolicitud: s.id })} className="flex w-full cursor-pointer items-center justify-between gap-3 py-3 text-left text-sm hover:bg-sky/20">
                    <span>
                      <span className="font-bold text-navy">#{s.id} · {s.servicio}</span>
                      <span className="block text-xs text-slate">
                        {s.cliente.nombre} · {formatearFechaYHora(s.fechaProgramada)}
                      </span>
                    </span>
                    <span className="rounded-full bg-moon px-3 py-1 text-xs font-bold text-navy">{s.estado}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </div>
  );
}
