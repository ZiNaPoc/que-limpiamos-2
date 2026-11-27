import { useCallback, useEffect, useState } from "react";
import { usePermisos } from "../data/permisos";
import {
  accionesDeReporte,
  consultarDetalleDeReporte,
  consultarReportes,
  ETIQUETA_DE_ESTADO,
  ETIQUETA_DE_TIPO,
  urlDeFoto,
  type DetalleDeReporte,
  type EstadoDeReporte,
  type ParticipanteDelReporte,
  type ReporteParaAdmin,
  type TipoDeReporte,
} from "../data/reportes";
import { MENSAJE_SIN_PERMISO_DE_MODERACION } from "../data/resenas";
import type { Navegar, ResultadoDeOperacion } from "../data/tipos";
import { formatearFechaNumerica, formatearHora } from "../utils/formato";
import { AvisoTemporal } from "../components/comunes/AvisoTemporal";
import { CampoDeFormulario } from "../components/comunes/CampoDeFormulario";
import { Icono } from "../components/comunes/Icono";
import { VentanaDeMotivo } from "../components/moderacion/VentanaDeMotivo";

const TIPOS = Object.keys(ETIQUETA_DE_TIPO) as TipoDeReporte[];
const ESTADOS = Object.keys(ETIQUETA_DE_ESTADO) as EstadoDeReporte[];

const mensajeDeError = (error: unknown) => (error instanceof Error ? error.message : "No se pudo completar la operación");
const persona = (p: ParticipanteDelReporte) => `${p.rol === "CLIENTE" ? "Cliente" : "Trabajador"} · ${p.nombre}`;

const COLOR_DE_ESTADO: Record<EstadoDeReporte, string> = { ABIERTO: "bg-moon text-clay", EN_REVISION: "bg-sky/60 text-navy", RESUELTO: "bg-moss/40 text-storm" };

function InsigniaDeReporte({ reporte }: { reporte: Pick<ReporteParaAdmin, "estado" | "eliminado"> }) {
  if (reporte.eliminado) return <span className="rounded-full bg-mist px-3 py-1 text-xs font-bold text-slate">Eliminado</span>;
  return <span className={`rounded-full px-3 py-1 text-xs font-bold ${COLOR_DE_ESTADO[reporte.estado]}`}>{ETIQUETA_DE_ESTADO[reporte.estado]}</span>;
}

type Accion =
  | { tipo: "estado"; estado: "ABIERTO" | "EN_REVISION" }
  | { tipo: "nota" }
  | { tipo: "editar" }
  | { tipo: "foto"; fotoId: string }
  | { tipo: "resolver" }
  | { tipo: "eliminar" }
  | null;

// Detalle de un reporte con todas las acciones de moderación (cada una pide motivo y queda auditada).
function DetalleDelReporte({ id, onVolver, onNavegar, onAviso }: { id: string; onVolver: () => void; onNavegar: Navegar; onAviso: (aviso: ResultadoDeOperacion) => void }) {
  const [detalle, setDetalle] = useState<DetalleDeReporte | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [accion, setAccion] = useState<Accion>(null);
  const [tipoEditado, setTipoEditado] = useState<TipoDeReporte>("OTRO");
  const [descripcionEditada, setDescripcionEditada] = useState("");

  const cargar = useCallback(async () => {
    try {
      setDetalle(await consultarDetalleDeReporte(id));
      setError(null);
    } catch (e) {
      setError(mensajeDeError(e));
    }
  }, [id]);

  useEffect(() => {
    let activo = true;
    consultarDetalleDeReporte(id)
      .then((d) => {
        if (activo) setDetalle(d);
      })
      .catch((e: unknown) => {
        if (activo) setError(mensajeDeError(e));
      });
    return () => {
      activo = false;
    };
  }, [id]);

  async function ejecutar(fn: () => Promise<unknown>, mensaje: string): Promise<string | null> {
    try {
      await fn();
      setAccion(null);
      onAviso({ exito: true, mensaje });
      await cargar();
      return null;
    } catch (e) {
      return mensajeDeError(e);
    }
  }

  if (error) {
    return (
      <div role="alert" className="rounded-2xl bg-moon p-6 text-sm text-clay">
        {error}
        <button onClick={onVolver} className="btn btn-quiet ml-3">
          Volver
        </button>
      </div>
    );
  }
  if (!detalle) return <p className="rounded-2xl bg-white p-8 text-center text-sm text-slate">Cargando reporte…</p>;

  const activo = !detalle.eliminado;
  const abierto = activo && detalle.estado !== "RESUELTO";

  return (
    <div>
      <button onClick={onVolver} className="btn btn-quiet">
        <Icono nombre="volver" className="h-4 w-4" />
        Volver a reportes
      </button>
      <header className="mt-6 flex flex-wrap items-center gap-3">
        <span className="rounded-full bg-navy px-3 py-1 text-xs font-bold text-white">Reporte {detalle.id}</span>
        <InsigniaDeReporte reporte={detalle} />
        <h1 className="w-full text-3xl font-extrabold text-navy">{ETIQUETA_DE_TIPO[detalle.tipo]}</h1>
        <p className="w-full text-sm text-slate">
          {formatearFechaNumerica(detalle.fecha)} · {formatearHora(detalle.fecha)} ·{" "}
          <button onClick={() => onNavegar("solicitudes", { idDeSolicitud: detalle.idSolicitud })} className="cursor-pointer text-lagoon hover:underline">
            Solicitud {detalle.idSolicitud} · {detalle.servicio}
          </button>
        </p>
      </header>

      <div className="mt-6 grid gap-6 lg:grid-cols-12">
        <section className="surface leaf-sm p-6 lg:col-span-7">
          <dl className="grid gap-3 sm:grid-cols-2">
            <div className="rounded-2xl bg-beige px-4 py-3">
              <dt className="text-xs font-bold uppercase tracking-wider text-slate">Reporta</dt>
              <dd className="mt-1 text-sm font-bold text-navy">{persona(detalle.reportante)}</dd>
            </div>
            <div className="rounded-2xl bg-beige px-4 py-3">
              <dt className="text-xs font-bold uppercase tracking-wider text-slate">Reportado</dt>
              <dd className="mt-1 text-sm font-bold text-navy">{persona(detalle.reportado)}</dd>
            </div>
          </dl>
          <h2 className="mt-6 font-display text-lg font-bold text-navy">Descripción</h2>
          <p className="mt-2 whitespace-pre-line rounded-2xl bg-beige p-4 text-sm text-storm">{detalle.descripcion ?? "Sin descripción."}</p>
          {detalle.editadoPorAdministracion && <p className="mt-2 text-xs font-bold text-clay">Editado por administración (lo anterior está en el historial).</p>}

          <h2 className="mt-6 font-display text-lg font-bold text-navy">Fotografías</h2>
          {detalle.fotos.length === 0 && <p className="mt-2 text-sm text-slate">Sin fotografías.</p>}
          <ul className="mt-3 grid gap-3 sm:grid-cols-3">
            {detalle.fotos.map((foto) => (
              <li key={foto.id} className="rounded-2xl bg-beige p-2 text-xs text-slate">
                {foto.eliminada || !urlDeFoto(foto) ? (
                  <div className="grid h-32 place-items-center rounded-xl bg-mist text-center">Retirada por moderación</div>
                ) : (
                  <a href={urlDeFoto(foto)!} target="_blank" rel="noreferrer">
                    <img src={urlDeFoto(foto)!} alt={`Foto ${foto.id} del reporte`} className="h-32 w-full rounded-xl object-cover" />
                  </a>
                )}
                <span className="mt-1 block">
                  {foto.tipoMime ?? "—"} · {foto.tamanoBytes !== null ? `${(foto.tamanoBytes / 1_000_000).toFixed(2)} MB` : "—"}
                </span>
                {!foto.eliminada && activo && (
                  <button onClick={() => setAccion({ tipo: "foto", fotoId: foto.id })} className="mt-1 cursor-pointer font-bold text-err hover:underline">
                    Retirar foto
                  </button>
                )}
              </li>
            ))}
          </ul>
          <p className="mt-2 text-xs text-slate">Los enlaces de las fotos son temporales (5 minutos). Recarga el reporte si expiran.</p>
        </section>

        <section className="surface leaf-sm h-fit p-6 lg:col-span-5">
          <h2 className="font-display text-lg font-bold text-navy">Seguimiento</h2>
          {!activo && <p className="mt-2 text-sm text-slate">El reporte fue eliminado: ya no admite cambios.</p>}
          {activo && (
            <div className="mt-3 flex flex-wrap gap-2">
              {abierto && detalle.estado === "ABIERTO" && (
                <button onClick={() => setAccion({ tipo: "estado", estado: "EN_REVISION" })} className="btn btn-quiet">
                  Poner en revisión
                </button>
              )}
              {abierto && detalle.estado === "EN_REVISION" && (
                <button onClick={() => setAccion({ tipo: "estado", estado: "ABIERTO" })} className="btn btn-quiet">
                  Volver a abierto
                </button>
              )}
              <button onClick={() => setAccion({ tipo: "nota" })} className="btn btn-quiet">
                Agregar nota
              </button>
              <button
                onClick={() => {
                  setTipoEditado(detalle.tipo);
                  setDescripcionEditada(detalle.descripcion ?? "");
                  setAccion({ tipo: "editar" });
                }}
                className="btn btn-quiet"
              >
                <Icono nombre="editar" className="h-4 w-4" />
                Editar
              </button>
              {abierto && (
                <button
                  onClick={() => setAccion({ tipo: "resolver" })}
                  className="btn btn-primary"
                  disabled={detalle.tipo === "PAGO_EN_DISPUTA" || detalle.resolverConServicio}
                  title={
                    detalle.tipo === "PAGO_EN_DISPUTA"
                      ? "Un pago en disputa se resuelve en el flujo financiero (D62)"
                      : detalle.resolverConServicio
                        ? "La solicitud sigue abierta: este reporte se resuelve con la resolución del servicio (Solicitudes, permiso de incidencias)"
                        : undefined
                  }
                >
                  <Icono nombre="palomita" className="h-4 w-4" />
                  Registrar resolución
                </button>
              )}
              <button onClick={() => setAccion({ tipo: "eliminar" })} className="btn btn-quiet text-err">
                <Icono nombre="prohibido" className="h-4 w-4" />
                Eliminar
              </button>
            </div>
          )}

          <h3 className="mt-6 text-xs font-bold uppercase tracking-widest text-slate">Historial de auditoría</h3>
          {detalle.eventos.length === 0 && <p className="mt-2 text-sm text-slate">Sin modificaciones.</p>}
          <ol className="mt-2 space-y-2">
            {detalle.eventos.map((evento) => (
              <li key={evento.id} className="rounded-2xl bg-beige p-3 text-xs text-storm">
                <span className="font-bold text-navy">{evento.operacion}</span> · {evento.admin?.nombre ?? "Sistema"} · {formatearFechaNumerica(evento.fecha)} {formatearHora(evento.fecha)}
                <span className="mt-1 block">Motivo: {evento.motivo}</span>
              </li>
            ))}
          </ol>
        </section>
      </div>

      {accion?.tipo === "estado" && (
        <VentanaDeMotivo
          titulo={accion.estado === "EN_REVISION" ? "Poner en revisión" : "Volver a abierto"}
          descripcion="El cambio de estado queda en el historial del reporte."
          etiquetaDeConfirmar="Cambiar estado"
          onCerrar={() => setAccion(null)}
          onConfirmar={(motivo) => ejecutar(() => accionesDeReporte.cambiarEstado(detalle.id, accion.estado, motivo), "Estado actualizado.")}
        />
      )}
      {accion?.tipo === "nota" && (
        <VentanaDeMotivo
          titulo="Nota de seguimiento"
          descripcion="La nota queda en el historial del reporte; no cambia su estado."
          etiquetaDelMotivo="Nota"
          etiquetaDeConfirmar="Agregar nota"
          onCerrar={() => setAccion(null)}
          onConfirmar={(nota) => ejecutar(() => accionesDeReporte.agregarNota(detalle.id, nota), "Nota agregada.")}
        />
      )}
      {accion?.tipo === "editar" && (
        <VentanaDeMotivo
          titulo="Editar reporte"
          descripcion="Lo anterior queda guardado en la auditoría."
          etiquetaDeConfirmar="Guardar cambios"
          onCerrar={() => setAccion(null)}
          onConfirmar={(motivo) => {
            const cambios: { tipo?: TipoDeReporte; descripcion?: string | null } = {};
            if (tipoEditado !== detalle.tipo) cambios.tipo = tipoEditado;
            const descripcion = descripcionEditada.trim() || null;
            if (descripcion !== detalle.descripcion) cambios.descripcion = descripcion;
            if (Object.keys(cambios).length === 0) return Promise.resolve("No hay cambios que guardar.");
            return ejecutar(() => accionesDeReporte.editar(detalle.id, cambios, motivo), "Reporte editado.");
          }}
        >
          <CampoDeFormulario id="tipo-editado" etiqueta="Tipo">
            <select id="tipo-editado" value={tipoEditado} onChange={(evento) => setTipoEditado(evento.target.value as TipoDeReporte)} className="field cursor-pointer">
              {TIPOS.map((tipo) => (
                <option key={tipo} value={tipo}>
                  {ETIQUETA_DE_TIPO[tipo]}
                </option>
              ))}
            </select>
          </CampoDeFormulario>
          <CampoDeFormulario id="descripcion-editada" etiqueta="Descripción (vacía = sin descripción)">
            <textarea id="descripcion-editada" rows={4} value={descripcionEditada} onChange={(evento) => setDescripcionEditada(evento.target.value)} className="field resize-y" />
          </CampoDeFormulario>
        </VentanaDeMotivo>
      )}
      {accion?.tipo === "foto" && (
        <VentanaDeMotivo
          titulo="Retirar fotografía"
          descripcion="Eliminación lógica: la foto deja de mostrarse (también al reportante), pero el registro se conserva."
          etiquetaDeConfirmar="Retirar"
          peligrosa
          onCerrar={() => setAccion(null)}
          onConfirmar={(motivo) => ejecutar(() => accionesDeReporte.retirarFoto(detalle.id, accion.fotoId, motivo), "Fotografía retirada.")}
        />
      )}
      {accion?.tipo === "resolver" && (
        <VentanaDeMotivo
          titulo="Registrar resolución"
          descripcion="El reporte pasa a Resuelto y deja de bloquear la confirmación automática del servicio (D57). No modifica pagos."
          etiquetaDelMotivo="Resolución"
          etiquetaDeConfirmar="Resolver"
          onCerrar={() => setAccion(null)}
          onConfirmar={(resolucion) => ejecutar(() => accionesDeReporte.resolver(detalle.id, resolucion), "Resolución registrada.")}
        />
      )}
      {accion?.tipo === "eliminar" && (
        <VentanaDeMotivo
          titulo="Eliminar reporte"
          descripcion="Eliminación lógica: el reporte y su historial se conservan, deja de verse y deja de bloquear la confirmación automática (X5)."
          etiquetaDeConfirmar="Sí, eliminar"
          peligrosa
          onCerrar={() => setAccion(null)}
          onConfirmar={(motivo) => ejecutar(() => accionesDeReporte.eliminar(detalle.id, motivo), "Reporte eliminado.")}
        />
      )}
    </div>
  );
}

// REPORTES: incidencias entre clientes y trabajadores (doc 20 §3–§5). Solo con MODERAR_CONTENIDO.
export function ReportesPage({ onNavegar }: { onNavegar: Navegar }) {
  const { cargando: cargandoPermisos, tiene } = usePermisos();
  const puedeModerar = tiene("MODERAR_CONTENIDO");
  const [reportes, setReportes] = useState<ReporteParaAdmin[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [estado, setEstado] = useState<EstadoDeReporte | "">("");
  const [tipo, setTipo] = useState<TipoDeReporte | "">("");
  const [incluirEliminados, setIncluirEliminados] = useState(false);
  const [abierto, setAbierto] = useState<string | null>(null);
  const [aviso, setAviso] = useState<ResultadoDeOperacion | null>(null);

  useEffect(() => {
    if (cargandoPermisos || !puedeModerar || abierto) return;
    let activo = true;
    consultarReportes({ estado: estado || undefined, tipo: tipo || undefined, incluirEliminados })
      .then((lista) => {
        if (activo) {
          setReportes(lista);
          setError(null);
        }
      })
      .catch((e: unknown) => {
        if (activo) setError(mensajeDeError(e));
      });
    return () => {
      activo = false;
    };
  }, [cargandoPermisos, puedeModerar, estado, tipo, incluirEliminados, abierto]);

  return (
    <div>
      {abierto ? (
        <DetalleDelReporte id={abierto} onVolver={() => setAbierto(null)} onNavegar={onNavegar} onAviso={setAviso} />
      ) : (
        <>
          <h1 className="text-4xl font-extrabold text-navy">Reportes</h1>
          <p className="mt-2 max-w-3xl text-sm text-slate">
            Reportes que se hacen cliente y trabajador sobre un servicio (desde la hora programada, aunque no haya terminado). Solo los ve quien los creó y la moderación: el usuario reportado no puede consultarlos. Toda acción pide un motivo y queda en la auditoría.
          </p>

          {!cargandoPermisos && !puedeModerar && (
            <div role="status" className="mt-8 flex items-start gap-3 rounded-2xl bg-moon p-5 text-sm text-clay">
              <Icono nombre="alerta" className="mt-0.5 h-5 w-5 shrink-0" />
              <div>
                <p className="font-bold text-navy">Sin permiso de moderación</p>
                <p className="mt-1">{MENSAJE_SIN_PERMISO_DE_MODERACION}</p>
              </div>
            </div>
          )}

          {puedeModerar && (
            <>
              <div className="mt-8 grid gap-4 md:grid-cols-[12rem_14rem_auto] md:items-end">
                <CampoDeFormulario id="filtro-estado-reporte" etiqueta="Estado">
                  <select id="filtro-estado-reporte" value={estado} onChange={(evento) => setEstado(evento.target.value as EstadoDeReporte | "")} className="field cursor-pointer">
                    <option value="">Todos</option>
                    {ESTADOS.map((e) => (
                      <option key={e} value={e}>
                        {ETIQUETA_DE_ESTADO[e]}
                      </option>
                    ))}
                  </select>
                </CampoDeFormulario>
                <CampoDeFormulario id="filtro-tipo-reporte" etiqueta="Tipo">
                  <select id="filtro-tipo-reporte" value={tipo} onChange={(evento) => setTipo(evento.target.value as TipoDeReporte | "")} className="field cursor-pointer">
                    <option value="">Todos</option>
                    {TIPOS.map((t) => (
                      <option key={t} value={t}>
                        {ETIQUETA_DE_TIPO[t]}
                      </option>
                    ))}
                  </select>
                </CampoDeFormulario>
                <label className="flex cursor-pointer items-center gap-2 pb-3 text-sm text-slate">
                  <input type="checkbox" checked={incluirEliminados} onChange={(evento) => setIncluirEliminados(evento.target.checked)} />
                  Incluir eliminados
                </label>
              </div>

              {error && (
                <p role="alert" className="mt-6 rounded-2xl bg-moon p-5 text-sm text-clay">
                  {error}
                </p>
              )}
              {!error && reportes === null && <p className="mt-6 rounded-2xl bg-white p-8 text-center text-sm text-slate">Cargando reportes…</p>}
              {!error && reportes?.length === 0 && <p className="mt-6 rounded-2xl bg-white p-10 text-center text-sm text-slate">No hay reportes que coincidan.</p>}
              <ul className="mt-6 space-y-3">
                {reportes?.map((reporte) => (
                  <li key={reporte.id}>
                    <button onClick={() => setAbierto(reporte.id)} className={`surface leaf-sm grid w-full cursor-pointer gap-3 px-5 py-4 text-left transition duration-300 ease-soft hover:-translate-y-0.5 hover:shadow-lift md:grid-cols-[8rem_1fr_14rem_7rem] md:items-center md:gap-6 ${reporte.eliminado ? "opacity-60" : ""}`}>
                      <span>
                        <InsigniaDeReporte reporte={reporte} />
                        <span className="mt-1 block text-xs text-slate">{formatearFechaNumerica(reporte.fecha)}</span>
                      </span>
                      <span className="min-w-0">
                        <span className="block text-sm font-bold text-navy">{ETIQUETA_DE_TIPO[reporte.tipo]}</span>
                        <span className="block truncate text-xs text-slate">{reporte.descripcion ?? "Sin descripción"}</span>
                      </span>
                      <span className="text-xs text-slate">
                        <span className="block">
                          <span className="font-bold text-navy">Reporta:</span> {persona(reporte.reportante)}
                        </span>
                        <span className="block">
                          <span className="font-bold text-navy">Reportado:</span> {persona(reporte.reportado)}
                        </span>
                      </span>
                      <span className="text-xs text-slate">
                        <Icono nombre="imagen" className="mr-1 inline h-4 w-4" />
                        {reporte.cantidadFotos} {reporte.cantidadFotos === 1 ? "foto" : "fotos"}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            </>
          )}
        </>
      )}
      {aviso && <AvisoTemporal aviso={aviso} onTerminar={() => setAviso(null)} />}
    </div>
  );
}
