import { useCallback, useEffect, useState } from "react";

import { Icono } from "../components/comunes/Icono";
import { usePermisos } from "../data/permisos";
import { type ClienteAdmin, consultarClientes } from "../data/plataforma";
import type { AperturaDelPanel } from "../data/tipos";
import { formatearFechaYHora } from "../utils/fechasDeSolicitudes";

const VERIFICACION: Record<string, string> = { PENDIENTE: "Pendiente", VERIFICADO: "Verificada", RECHAZADO: "Rechazada" };

// Clientes REALES (GET /api/admin/clientes): solo lectura, con supervisión de solicitudes. Los clientes
// se registran desde la app. La revisión de la INE pertenece a la fase de documentos (no se simula aquí).
export function ClientesPage({ apertura }: { apertura: AperturaDelPanel }) {
  const { tiene, cargando: cargandoPermisos } = usePermisos();
  const [q, setQ] = useState("");
  const [verificacion, setVerificacion] = useState(apertura.filtroDeVerificacion === "Pendiente" ? "PENDIENTE" : "");
  const [clientes, setClientes] = useState<ClienteAdmin[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const puedeVer = tiene("SUPERVISAR_SOLICITUDES");

  const cargar = useCallback(async () => {
    try {
      setClientes(await consultarClientes(q, verificacion));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudieron cargar los clientes");
    }
  }, [q, verificacion]);

  useEffect(() => {
    if (!puedeVer) return;
    const t = window.setTimeout(() => void cargar(), 300);
    return () => window.clearTimeout(t);
  }, [cargar, puedeVer]);

  if (cargandoPermisos) return <p className="rounded-2xl bg-white p-8 text-center text-sm text-slate">Cargando…</p>;
  if (!puedeVer) return <p role="alert" className="rounded-2xl bg-white p-8 text-center text-sm text-slate">Ver clientes requiere el permiso «Supervisar solicitudes».</p>;

  return (
    <div>
      <h1 className="text-4xl font-extrabold text-navy">Clientes</h1>
      <p className="mt-2 max-w-3xl text-sm text-slate">Clientes registrados desde la app, con su actividad real. La revisión de la INE llega con la fase de documentos.</p>
      <div className="surface leaf-sm mt-8 flex flex-wrap items-end gap-4 p-5">
        <label className="min-w-[14rem] flex-1">
          <span className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate">Buscar</span>
          <span className="relative block">
            <Icono nombre="buscar" className="absolute left-3 top-1/2 -translate-y-1/2 text-slate" />
            <input type="search" value={q} onChange={(e) => setQ(e.target.value)} maxLength={100} placeholder="Nombre, correo o teléfono" className="field pl-10" />
          </span>
        </label>
        <label>
          <span className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate">Identidad</span>
          <select value={verificacion} onChange={(e) => setVerificacion(e.target.value)} className="field">
            <option value="">Todas</option>
            <option value="PENDIENTE">Pendiente</option>
            <option value="VERIFICADO">Verificada</option>
            <option value="RECHAZADO">Rechazada</option>
          </select>
        </label>
      </div>
      {error && (
        <p role="alert" className="mt-6 rounded-2xl bg-moon p-4 text-sm text-clay">
          {error} <button onClick={() => void cargar()} className="font-bold underline">Reintentar</button>
        </p>
      )}
      {!clientes && !error && <p className="mt-6 text-sm text-slate">Cargando clientes…</p>}
      {clientes && clientes.length === 0 && <p className="mt-6 rounded-2xl bg-white p-8 text-center text-sm text-slate">No hay clientes con esos filtros.</p>}
      {clientes && clientes.length > 0 && (
        <div className="surface leaf-sm mt-6 overflow-x-auto">
          <table className="w-full min-w-[48rem] text-left text-sm">
            <thead className="bg-moon/60 text-xs uppercase tracking-wider text-slate">
              <tr>
                <th className="px-5 py-4">Cliente</th>
                <th className="px-4 py-4">Contacto</th>
                <th className="px-4 py-4">Identidad</th>
                <th className="px-4 py-4">Solicitudes</th>
                <th className="px-4 py-4">Inmuebles</th>
                <th className="px-5 py-4">Registro</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-mist/70">
              {clientes.map((c) => (
                <tr key={c.id}>
                  <td className="px-5 py-4">
                    <span className="block font-bold text-navy">{c.nombre}</span>
                    <span className="text-xs text-slate">#{c.id} · cuenta {c.estadoCuenta === "ACTIVA" ? "activa" : "suspendida"}</span>
                  </td>
                  <td className="px-4 py-4 text-slate">
                    {c.correo}
                    <span className="block text-xs">{c.telefono ?? "—"}</span>
                  </td>
                  <td className="px-4 py-4">
                    <span className="rounded-full bg-moon px-3 py-1 text-xs font-bold text-navy">{VERIFICACION[c.verificacion] ?? c.verificacion}</span>
                  </td>
                  <td className="px-4 py-4 text-navy">
                    {c.solicitudes.total} <span className="text-xs text-slate">({c.solicitudes.activas} activas · {c.solicitudes.realizadas} realizadas)</span>
                  </td>
                  <td className="px-4 py-4 text-navy">{c.inmueblesGuardados}</td>
                  <td className="px-5 py-4 text-xs text-slate">{formatearFechaYHora(c.registradoEn)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
