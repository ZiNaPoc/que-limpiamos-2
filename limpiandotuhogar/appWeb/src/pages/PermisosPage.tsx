import { useCallback, useEffect, useState } from "react";

import { AvisoTemporal } from "../components/comunes/AvisoTemporal";
import { CampoDeFormulario } from "../components/comunes/CampoDeFormulario";
import { VentanaDeMotivo } from "../components/moderacion/VentanaDeMotivo";
import {
  type AdministradorConPermisos,
  consultarAdministradores,
  ETIQUETA_DE_PERMISO,
  otorgarPermiso,
  type PermisoDeAdmin,
  PERMISOS_OTORGABLES,
  revocarPermiso,
  usePermisos,
} from "../data/permisos";
import type { ResultadoDeOperacion, Sesion } from "../data/tipos";

type Accion = { tipo: "otorgar"; admin: AdministradorConPermisos; permiso: PermisoDeAdmin } | { tipo: "revocar"; admin: AdministradorConPermisos; permisoId: number; permiso: PermisoDeAdmin };

// Permisos de los administradores (solo el PROPIETARIO, ADMINISTRAR_PERMISOS). Otorga y revoca
// los permisos otorgables a OTROS admins, con motivo y auditoría (docs/backend/20 §6 y 25 v2 §5).
// Nadie se otorga un permiso a sí mismo. El propietario supervisa solicitudes sin asignárselo.
export function PermisosPage({ sesion }: { sesion: Sesion }) {
  const { tiene, implicitos } = usePermisos();
  const [admins, setAdmins] = useState<AdministradorConPermisos[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [accion, setAccion] = useState<Accion | null>(null);
  const [aviso, setAviso] = useState<ResultadoDeOperacion | null>(null);

  const cargar = useCallback(async () => {
    try {
      setAdmins(await consultarAdministradores());
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudieron cargar los administradores");
    }
  }, []);
  const esPropietario = tiene("ADMINISTRAR_PERMISOS");
  useEffect(() => {
    if (!esPropietario) return;
    const t = window.setTimeout(() => void cargar(), 0);
    return () => window.clearTimeout(t);
  }, [cargar, esPropietario]);

  if (!tiene("ADMINISTRAR_PERMISOS")) {
    return (
      <p role="alert" className="rounded-2xl bg-white p-8 text-center text-sm text-slate">
        Solo el propietario administra los permisos.
      </p>
    );
  }

  return (
    <div>
      <h1 className="text-4xl font-extrabold text-navy">Permisos de administración</h1>
      <p className="mt-2 max-w-3xl text-sm text-slate">
        Cada otorgamiento y revocación exige un motivo y queda en la auditoría. Nadie puede otorgarse un permiso a sí mismo.
        {implicitos.includes("SUPERVISAR_SOLICITUDES") && " Como propietario, supervisas las solicitudes sin necesidad de asignártelo."}
      </p>
      {error && (
        <p role="alert" className="mt-6 rounded-2xl bg-moon p-4 text-sm text-clay">
          {error}
        </p>
      )}
      <div className="mt-8 space-y-4">
        {admins?.map((a) => {
          const esYo = a.id === sesion.id;
          return (
            <section key={a.id} className="surface leaf-sm p-6">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <h2 className="text-lg font-extrabold text-navy">
                  {a.nombre} {esYo && <span className="text-sm font-bold text-slate">(tú)</span>}
                </h2>
                <span className="text-xs text-slate">
                  {a.correo} · {a.estadoCuenta === "ACTIVA" ? "Activa" : "Suspendida"}
                </span>
              </div>
              <ul className="mt-3 flex flex-wrap gap-2">
                {a.permisos.length === 0 && <li className="text-sm text-slate">Sin permisos.</li>}
                {a.permisos.map((p) => (
                  <li key={p.id} className="inline-flex items-center gap-2 rounded-full bg-sky/50 px-3 py-1 text-xs font-bold text-storm">
                    {ETIQUETA_DE_PERMISO[p.permiso] ?? p.permiso}
                    {!esYo && PERMISOS_OTORGABLES.includes(p.permiso) && (
                      <button onClick={() => setAccion({ tipo: "revocar", admin: a, permisoId: p.id, permiso: p.permiso })} className="text-err underline" aria-label={`Revocar ${ETIQUETA_DE_PERMISO[p.permiso]} a ${a.nombre}`}>
                        revocar
                      </button>
                    )}
                  </li>
                ))}
              </ul>
              {!esYo && a.estadoCuenta === "ACTIVA" && (
                <div className="mt-4 flex flex-wrap gap-2">
                  {PERMISOS_OTORGABLES.filter((p) => !a.permisos.some((x) => x.permiso === p)).map((p) => (
                    <button key={p} onClick={() => setAccion({ tipo: "otorgar", admin: a, permiso: p })} className="btn btn-quiet">
                      Otorgar «{ETIQUETA_DE_PERMISO[p]}»
                    </button>
                  ))}
                </div>
              )}
            </section>
          );
        })}
      </div>

      {accion && (
        <VentanaDeMotivo
          titulo={accion.tipo === "otorgar" ? "Otorgar permiso" : "Revocar permiso"}
          descripcion={`${accion.tipo === "otorgar" ? "Otorgar" : "Revocar"} «${ETIQUETA_DE_PERMISO[accion.permiso]}» a ${accion.admin.nombre}.`}
          etiquetaDeConfirmar={accion.tipo === "otorgar" ? "Otorgar" : "Revocar"}
          peligrosa={accion.tipo === "revocar"}
          onCerrar={() => setAccion(null)}
          onConfirmar={async (motivo) => {
            try {
              if (accion.tipo === "otorgar") await otorgarPermiso(accion.admin.id, accion.permiso, motivo);
              else await revocarPermiso(accion.permisoId, motivo);
              setAccion(null);
              setAviso({ exito: true, mensaje: accion.tipo === "otorgar" ? "Permiso otorgado." : "Permiso revocado." });
              await cargar();
              return null;
            } catch (e) {
              return e instanceof Error ? e.message : "No se pudo completar la operación";
            }
          }}
        >
          <CampoDeFormulario id="permiso-elegido" etiqueta="Permiso">
            <input id="permiso-elegido" readOnly value={ETIQUETA_DE_PERMISO[accion.permiso]} className="field" />
          </CampoDeFormulario>
        </VentanaDeMotivo>
      )}
      {aviso && <AvisoTemporal aviso={aviso} onTerminar={() => setAviso(null)} />}
    </div>
  );
}
