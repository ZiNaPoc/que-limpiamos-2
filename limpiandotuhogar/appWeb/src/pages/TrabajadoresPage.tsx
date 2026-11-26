import { useCallback, useEffect, useState } from "react";

import { Icono } from "../components/comunes/Icono";
import { Puntuacion } from "../components/comunes/Insignias";
import { usePermisos } from "../data/permisos";
import { consultarTrabajadores, type TrabajadorAdmin } from "../data/plataforma";
import type { Navegar } from "../data/tipos";
import { formatearFechaYHora } from "../utils/fechasDeSolicitudes";

const VERIFICACION: Record<string, string> = { PENDIENTE: "Pendiente", VERIFICADO: "Verificado", RECHAZADO: "Rechazado" };
const ESTADO: Record<string, string> = { ACTIVO: "Activo", INACTIVO: "Inactivo", BAJA: "Dado de baja" };

// Colaboradores REALES (GET /api/admin/trabajadores): solo lectura, con supervisión de solicitudes.
// Se registran solos desde su app (decisión v3); el admin no los crea. Verificarlos requiere revisar sus
// documentos (fase de documentos, permiso de identidad): no se simula aquí.
export function TrabajadoresPage({ onNavegar }: { onNavegar: Navegar }) {
  const { tiene, cargando: cargandoPermisos } = usePermisos();
  const [q, setQ] = useState("");
  const [lista, setLista] = useState<TrabajadorAdmin[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const puedeVer = tiene("SUPERVISAR_SOLICITUDES");

  const cargar = useCallback(async () => {
    try {
      setLista(await consultarTrabajadores(q));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudieron cargar los colaboradores");
    }
  }, [q]);

  useEffect(() => {
    if (!puedeVer) return;
    const t = window.setTimeout(() => void cargar(), 300);
    return () => window.clearTimeout(t);
  }, [cargar, puedeVer]);

  if (cargandoPermisos) return <p className="rounded-2xl bg-white p-8 text-center text-sm text-slate">Cargando…</p>;
  if (!puedeVer) return <p role="alert" className="rounded-2xl bg-white p-8 text-center text-sm text-slate">Ver colaboradores requiere el permiso «Supervisar solicitudes».</p>;

  return (
    <div>
      <h1 className="text-4xl font-extrabold text-navy">Colaboradores</h1>
      <p className="mt-2 max-w-3xl text-sm text-slate">
        Colaboradores registrados desde su app, con su reputación y actividad reales. Solo los activos y verificados reciben solicitudes. La verificación de documentos llega con la fase de documentos.
      </p>
      <div className="surface leaf-sm mt-8 p-5">
        <label className="block">
          <span className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate">Buscar</span>
          <span className="relative block">
            <Icono nombre="buscar" className="absolute left-3 top-1/2 -translate-y-1/2 text-slate" />
            <input type="search" value={q} onChange={(e) => setQ(e.target.value)} maxLength={100} placeholder="Nombre, correo o teléfono" className="field pl-10" />
          </span>
        </label>
      </div>
      {error && (
        <p role="alert" className="mt-6 rounded-2xl bg-moon p-4 text-sm text-clay">
          {error} <button onClick={() => void cargar()} className="font-bold underline">Reintentar</button>
        </p>
      )}
      {!lista && !error && <p className="mt-6 text-sm text-slate">Cargando colaboradores…</p>}
      {lista && lista.length === 0 && <p className="mt-6 rounded-2xl bg-white p-8 text-center text-sm text-slate">No hay colaboradores con esa búsqueda.</p>}
      <div className="mt-6 grid gap-4 md:grid-cols-2">
        {lista?.map((t) => (
          <article key={t.id} className="surface leaf-sm p-6">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-lg font-extrabold text-navy">{t.nombre}</h2>
                <p className="text-xs text-slate">
                  #{t.id} · {t.correo} · {t.telefono}
                </p>
              </div>
              <span className={`rounded-full px-3 py-1 text-xs font-bold ${t.disponibleParaSolicitudes ? "bg-moss/45 text-storm" : "bg-mist text-slate"}`}>
                {t.disponibleParaSolicitudes ? "Recibe solicitudes" : "No recibe solicitudes"}
              </span>
            </div>
            <p className="mt-3 text-sm text-navy">
              Estado: <strong>{ESTADO[t.estado] ?? t.estado}</strong> · Verificación: <strong>{VERIFICACION[t.verificacion] ?? t.verificacion}</strong>
            </p>
            <p className="mt-1 text-sm text-navy">Especialidades: {t.especialidades.length ? t.especialidades.join(", ") : "—"}</p>
            <div className="mt-2 flex items-center gap-2 text-sm text-navy">
              {t.reputacion.promedio === null ? <span className="text-slate">Sin calificaciones</span> : <Puntuacion valor={Math.round(t.reputacion.promedio)} />}
              {t.reputacion.promedio !== null && (
                <span className="text-xs text-slate">
                  {t.reputacion.promedio.toFixed(1)} · {t.reputacion.cantidad} reseña(s)
                </span>
              )}
            </div>
            <p className="mt-2 text-xs text-slate">
              {t.servicios.activos} servicio(s) activo(s) · {t.servicios.realizados} realizado(s) · registro {formatearFechaYHora(t.registradoEn)}
            </p>
            <button onClick={() => onNavegar("solicitudes")} className="mt-3 cursor-pointer text-sm font-bold text-lagoon hover:underline">
              Ver solicitudes →
            </button>
          </article>
        ))}
      </div>
    </div>
  );
}
