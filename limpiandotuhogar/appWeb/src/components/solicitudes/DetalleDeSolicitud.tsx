import { useCallback, useState, type ReactNode } from "react";

import { ErrorDeApi } from "../../data/api";
import { usePermisos } from "../../data/permisos";
import { ETIQUETA_DE_TIPO } from "../../data/reportes";
import {
  consultarDetalle,
  type DetalleDeSupervision,
  ETIQUETA_DE_ACTOR,
  ETIQUETA_DE_ESTADO,
  ETIQUETA_DE_ESTADO_DEL_TRABAJADOR,
  ETIQUETA_DE_MODO,
  ETIQUETA_DE_MOTIVO_DE_CIERRE,
  ETIQUETA_DE_VIA,
  resolverServicio,
  urlDeFotoDeSolicitud,
} from "../../data/solicitudesAdmin";
import { INTERVALO_DE_ACTUALIZACION_MS } from "../../data/SolicitudesProvider";
import type { Navegar, ResultadoDeOperacion } from "../../data/tipos";
import { useActualizacionPeriodica } from "../../hooks/useActualizacionPeriodica";
import { useAhora } from "../../hooks/useAhora";
import { formatearFechaYHora, haceCuanto } from "../../utils/fechasDeSolicitudes";
import { AvisoTemporal } from "../comunes/AvisoTemporal";
import { CampoDeFormulario } from "../comunes/CampoDeFormulario";
import { Icono } from "../comunes/Icono";
import { VentanaModal } from "../comunes/VentanasModales";
import { InsigniaDeEstadoDeSolicitud, InsigniasDeAlerta } from "./ListaDeSolicitudes";

const MOTIVO = { min: 10, max: 500 };
const TIPO_DE_INMUEBLE: Record<string, string> = { CASA: "Casa", OFICINA: "Oficina", DEPARTAMENTO: "Departamento" };
const dinero = (n: number) => n.toLocaleString("es-MX", { style: "currency", currency: "MXN" });

function Tarjeta({ titulo, children, className = "" }: { titulo: string; children: ReactNode; className?: string }) {
  return (
    <section className={`surface leaf-sm p-6 ${className}`}>
      <h2 className="text-xs font-bold uppercase tracking-wider text-slate">{titulo}</h2>
      <div className="mt-3 space-y-1.5 text-sm text-navy">{children}</div>
    </section>
  );
}

function Dato({ etiqueta, children }: { etiqueta: string; children: ReactNode }) {
  return (
    <p>
      <span className="text-slate">{etiqueta}: </span>
      <span className="font-bold">{children}</span>
    </p>
  );
}

type DetalleDeSolicitudProps = { idSolicitud: number; onVolver: () => void; onNavegar: Navegar };

// Detalle para SUPERVISAR (D24: no se asigna, confirma, finaliza ni cancela desde aquí). Se
// actualiza cada 20 s con la página visible. La única acción es resolver el servicio cuando hay un
// reporte activo, con el permiso de incidencias; la resolución es inmutable (docs/backend/25 v2 §4).
export function DetalleDeSolicitud({ idSolicitud, onVolver, onNavegar }: DetalleDeSolicitudProps) {
  const ahora = useAhora();
  const { tiene } = usePermisos();
  const [detalle, setDetalle] = useState<DetalleDeSupervision | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<ResultadoDeOperacion | null>(null);
  const [resolviendo, setResolviendo] = useState(false);

  const cargar = useCallback(async () => {
    try {
      setDetalle(await consultarDetalle(idSolicitud));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo cargar la solicitud");
    }
  }, [idSolicitud]);

  useActualizacionPeriodica(cargar, INTERVALO_DE_ACTUALIZACION_MS, true, true);

  async function abrirFoto(idFoto: number) {
    try {
      window.open(await urlDeFotoDeSolicitud(idSolicitud, idFoto), "_blank", "noopener");
    } catch (e) {
      setAviso({ exito: false, mensaje: e instanceof Error ? e.message : "No se pudo abrir la foto" });
    }
  }

  if (!detalle) {
    return (
      <div>
        <button onClick={onVolver} className="btn btn-quiet">
          <Icono nombre="volver" /> Volver
        </button>
        <p role={error ? "alert" : "status"} className="mt-6 rounded-2xl bg-white p-8 text-center text-sm text-slate">
          {error ?? "Cargando la solicitud…"}
        </p>
      </div>
    );
  }

  const d = detalle;
  const i = d.inmueble;
  const tieneIncidencias = tiene("GESTIONAR_INCIDENCIAS_FINANZAS");
  let motivoNoResolver = "";
  if (!d.resolucion && !d.puedeResolver) {
    if (!tieneIncidencias) motivoNoResolver = "Resolver una incidencia requiere el permiso de incidencias y finanzas.";
    else if (d.estado !== "CONFIRMADO" && d.estado !== "EN_PROCESO") motivoNoResolver = "Solo se resuelve un servicio confirmado o en proceso.";
    else motivoNoResolver = "No hay reportes activos: no hay una incidencia que resolver.";
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <button onClick={onVolver} className="btn btn-quiet">
          <Icono nombre="volver" /> Volver a la lista
        </button>
        <div className="flex items-center gap-3 text-xs text-slate">
          <span aria-live="polite">Actualizado {haceCuanto(d.actualizadoEn, ahora)} · cada 20 s</span>
          <button onClick={() => void cargar()} className="btn btn-quiet">
            <Icono nombre="restablecer" /> Actualizar
          </button>
        </div>
      </div>

      <header className="flex flex-wrap items-center gap-3">
        <h1 className="text-4xl font-extrabold text-navy">Solicitud {d.id}</h1>
        <InsigniaDeEstadoDeSolicitud estado={d.estado} />
        <InsigniasDeAlerta alertas={d.alertas} />
      </header>
      {error && (
        <p role="alert" className="rounded-2xl bg-moon p-4 text-sm text-clay">
          No se pudo actualizar: {error}. Se muestran los últimos datos cargados.
        </p>
      )}

      <div className="grid gap-6 md:grid-cols-2">
        <Tarjeta titulo="Cliente">
          <Dato etiqueta="Nombre">{d.cliente.nombre}</Dato>
          <Dato etiqueta="Correo">{d.cliente.correo}</Dato>
          <Dato etiqueta="Teléfono">{d.cliente.telefono ?? "—"}</Dato>
          <Dato etiqueta="Identidad">{d.cliente.verificacion ?? "—"}</Dato>
        </Tarjeta>
        <Tarjeta titulo="Servicio">
          <Dato etiqueta="Servicio">{d.servicio}</Dato>
          <Dato etiqueta="Programada">{formatearFechaYHora(d.fechaProgramada)}</Dato>
          <Dato etiqueta="Fin estimado">{formatearFechaYHora(d.finEstimado)}</Dato>
          <Dato etiqueta="Duración">{d.duracionMin ? `${d.duracionMin} min` : "—"}</Dato>
          <Dato etiqueta="Precio (informativo)">
            {dinero(d.precio.total)} · base {dinero(d.precio.base)} + extras {dinero(d.precio.extras)}
          </Dato>
          <p className="text-xs text-slate">Pago en efectivo. En esta fase no se registran pagos ni movimientos (estado del pago: {d.precio.estadoPago}).</p>
        </Tarjeta>
        <Tarjeta titulo="Inmueble (copia guardada al crear la solicitud)">
          {i.nombre && <Dato etiqueta="Nombre">{i.nombre}</Dato>}
          <Dato etiqueta="Tipo">{i.tipo ? TIPO_DE_INMUEBLE[i.tipo] ?? i.tipo : "—"}</Dato>
          <Dato etiqueta="Dirección">{d.direccion}</Dato>
          <Dato etiqueta="Medidas">
            {i.habitaciones ?? 0} habitaciones · {i.banos ?? 0} baños · {i.mediosBanos ?? 0} medios baños · {i.pisos ?? 1} pisos
          </Dato>
          <p className="text-xs text-slate">{i.guardado ? "Tomado de «Mis inmuebles» del cliente." : "Capturado solo para esta solicitud."}</p>
        </Tarjeta>
        <Tarjeta titulo="Detalle del pedido">
          <Dato etiqueta="Áreas">{d.areas.length ? d.areas.join(", ") : "—"}</Dato>
          <Dato etiqueta="Extras">{d.extras.length ? d.extras.map((e) => `${e.nombre} (${dinero(e.precio)})`).join(", ") : "—"}</Dato>
          <Dato etiqueta="Especialidades requeridas">{d.especialidades.length ? d.especialidades.join(", ") : "—"}</Dato>
          <Dato etiqueta="Notas">{d.notas ?? "—"}</Dato>
        </Tarjeta>
      </div>

      <Tarjeta titulo={`Asignación · ${ETIQUETA_DE_MODO[d.modo]}`}>
        <Dato etiqueta="Colaborador asignado">{d.trabajador ? `${d.trabajador.nombre} (${d.trabajador.telefono})` : "Ninguno todavía"}</Dato>
        {d.modo === "BOLSA" && !d.trabajador && <p className="text-slate">En la bolsa: la ven los colaboradores activos, verificados, con las especialidades y sin otro servicio en ese horario.</p>}
        {d.trabajadores.length > 0 ? (
          <ul className="mt-3 divide-y divide-mist/70">
            {d.trabajadores.map((t) => (
              <li key={t.trabajador.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                <span className="font-bold">{t.trabajador.nombre}</span>
                <span className="text-slate">
                  {t.origen === "INVITACION" ? "Invitado" : "Desde la bolsa"} · {ETIQUETA_DE_ESTADO_DEL_TRABAJADOR[t.estado] ?? t.estado}
                  {t.motivoCierre ? ` (${ETIQUETA_DE_MOTIVO_DE_CIERRE[t.motivoCierre] ?? t.motivoCierre})` : ""} · {formatearFechaYHora(t.respondidaEn ?? t.creadaEn)}
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-slate">Ningún colaborador ha respondido todavía.</p>
        )}
      </Tarjeta>

      <div className="grid gap-6 md:grid-cols-2">
        <Tarjeta titulo="Seguimiento del servicio">
          <Dato etiqueta="El colaborador marcó terminado">{formatearFechaYHora(d.marcas.trabajadorTerminoEn)}</Dato>
          <Dato etiqueta="El cliente confirmó">{formatearFechaYHora(d.marcas.clienteConfirmoEn)}</Dato>
          <Dato etiqueta="Se pidió confirmar (D54)">{formatearFechaYHora(d.marcas.confirmacionSolicitadaEn)}</Dato>
          <Dato etiqueta="Aviso con evidencia (D54)">{formatearFechaYHora(d.marcas.avisoEvidenciaEn)}</Dato>
          <Dato etiqueta="Realizado">
            {d.marcas.realizadoEn ? `${formatearFechaYHora(d.marcas.realizadoEn)} (${ETIQUETA_DE_VIA[d.marcas.realizadoVia ?? ""] ?? d.marcas.realizadoVia})` : "—"}
          </Dato>
        </Tarjeta>
        <Tarjeta titulo="Fotos del trabajo terminado">
          {d.fotosTerminado.length ? (
            <div className="flex flex-wrap gap-2">
              {d.fotosTerminado.map((f, n) => (
                <button key={f.id} onClick={() => void abrirFoto(f.id)} className="btn btn-quiet">
                  <Icono nombre="imagen" /> Foto {n + 1}
                </button>
              ))}
            </div>
          ) : (
            <p className="text-slate">El colaborador aún no ha subido fotos.</p>
          )}
          <p className="text-xs text-slate">Se abren con un enlace temporal de 60 s.</p>
        </Tarjeta>
      </div>

      <Tarjeta titulo="Reportes de esta solicitud">
        {d.reportes.length === 0 && <p className="text-slate">Sin reportes.</p>}
        {!d.verContenidoDeReportes && d.reportes.length > 0 && (
          <p className="text-xs text-slate">El contenido de los reportes solo lo ven la moderación (página Reportes) y quien tiene el permiso de incidencias.</p>
        )}
        <ul className="divide-y divide-mist/70">
          {d.reportes.map((r) => (
            <li key={r.id} className="py-3">
              <p className="flex flex-wrap items-center gap-2">
                <span className="font-bold">#{r.id}</span>
                <span>{ETIQUETA_DE_TIPO[r.tipo as keyof typeof ETIQUETA_DE_TIPO] ?? r.tipo}</span>
                <span className="text-slate">
                  · lo reportó el {r.reportadoPor === "CLIENTE" ? "cliente" : "colaborador"} · {formatearFechaYHora(r.fecha)} · {r.eliminado ? "eliminado" : r.estado.toLowerCase().replace("_", " ")}
                </span>
                {r.activo && <span className="rounded-full bg-err/10 px-2.5 py-0.5 text-xs font-bold text-err">Bloquea la confirmación automática</span>}
              </p>
              {r.descripcion !== undefined && <p className="mt-1 text-slate">{r.descripcion ?? "(sin descripción)"}</p>}
              {r.fotos && r.fotos.length > 0 && (
                <div className="mt-2 flex flex-wrap gap-2">
                  {r.fotos.map((f, n) => (
                    <button key={f.id} onClick={() => void abrirFoto(f.id)} className="btn btn-quiet">
                      <Icono nombre="imagen" /> Foto {n + 1}
                    </button>
                  ))}
                </div>
              )}
            </li>
          ))}
        </ul>
        {d.reportes.length > 0 && tiene("MODERAR_CONTENIDO") && (
          <button onClick={() => onNavegar("reportes")} className="btn btn-quiet mt-2">
            Ir a Reportes
          </button>
        )}
      </Tarjeta>

      <Tarjeta titulo="Resolución administrativa">
        {d.resolucion ? (
          <>
            <Dato etiqueta="Resultado">{d.resolucion.resultadoServicio === "REALIZADO" ? "Realizado" : "No realizado (cancelada)"}</Dato>
            <Dato etiqueta="Motivo">{d.resolucion.motivo}</Dato>
            <Dato etiqueta="Por">
              {d.resolucion.admin} · {formatearFechaYHora(d.resolucion.fecha)}
            </Dato>
            <p className="text-xs text-slate">Las resoluciones son definitivas: no se pueden modificar desde el panel.</p>
          </>
        ) : d.puedeResolver ? (
          <>
            <p>Revisa las pruebas de ambas partes y decide si el servicio se realizó. La decisión es definitiva y queda en la auditoría.</p>
            <button onClick={() => setResolviendo(true)} className="btn btn-primary mt-2">
              Resolver el servicio
            </button>
          </>
        ) : (
          <p className="text-slate">{motivoNoResolver}</p>
        )}
      </Tarjeta>

      <Tarjeta titulo="Historial">
        <ol className="space-y-3">
          {d.historial.map((h, n) => (
            <li key={n} className="border-l-2 border-mist pl-4">
              <p className="font-bold">
                {h.estadoAnterior && h.estadoAnterior !== h.estadoNuevo ? `${ETIQUETA_DE_ESTADO[h.estadoAnterior]} → ` : ""}
                {ETIQUETA_DE_ESTADO[h.estadoNuevo]}
              </p>
              <p className="text-xs text-slate">
                {formatearFechaYHora(h.fecha)} · {ETIQUETA_DE_ACTOR[h.actor] ?? h.actor}: {h.actorNombre}
              </p>
              {h.motivo && <p className="text-sm text-slate">{h.motivo}</p>}
            </li>
          ))}
        </ol>
      </Tarjeta>

      {resolviendo && (
        <VentanaDeResolucion
          onCerrar={() => setResolviendo(false)}
          onConfirmar={async (resultado, motivo) => {
            try {
              await resolverServicio(d.id, resultado, motivo);
              setResolviendo(false);
              setAviso({ exito: true, mensaje: "Resolución registrada." });
              await cargar();
              return null;
            } catch (e) {
              if (e instanceof ErrorDeApi && e.codigo === "RESOLUCION_EXISTENTE") {
                setResolviendo(false);
                setAviso({ exito: false, mensaje: "Otro administrador ya resolvió esta solicitud. Se muestra su resolución." });
                await cargar();
                return null;
              }
              return e instanceof Error ? e.message : "No se pudo registrar la resolución";
            }
          }}
        />
      )}
      {aviso && <AvisoTemporal aviso={aviso} onTerminar={() => setAviso(null)} />}
    </div>
  );
}

function VentanaDeResolucion({ onCerrar, onConfirmar }: { onCerrar: () => void; onConfirmar: (r: "REALIZADO" | "NO_REALIZADO", motivo: string) => Promise<string | null> }) {
  const [resultado, setResultado] = useState<"REALIZADO" | "NO_REALIZADO" | "">("");
  const [motivo, setMotivo] = useState("");
  const [error, setError] = useState("");
  const [enviando, setEnviando] = useState(false);

  async function confirmar() {
    const limpio = motivo.trim();
    if (!resultado) return setError("Elige si el servicio se realizó o no.");
    if (limpio.length < MOTIVO.min) return setError(`Escribe el motivo (mínimo ${MOTIVO.min} caracteres): queda en la auditoría.`);
    setEnviando(true);
    setError("");
    const fallo = await onConfirmar(resultado, limpio);
    setEnviando(false);
    if (fallo) setError(fallo);
  }

  return (
    <VentanaModal idDelTitulo="titulo-resolucion" onCerrar={onCerrar} claseDeAncho="max-w-lg">
      <h2 id="titulo-resolucion" className="text-2xl font-extrabold text-navy">
        Resolver el servicio
      </h2>
      <p className="mt-2 text-sm text-slate">
        «Realizado» lo da por realizado; «No realizado» lo cancela. Los reportes activos quedarán resueltos. Es definitivo: no se podrá corregir desde el panel. No se registra ningún pago.
      </p>
      <fieldset className="mt-5 space-y-2 text-sm text-navy">
        <legend className="sr-only">Resultado del servicio</legend>
        {(["REALIZADO", "NO_REALIZADO"] as const).map((r) => (
          <label key={r} className="flex cursor-pointer items-center gap-2">
            <input type="radio" name="resultado" checked={resultado === r} onChange={() => setResultado(r)} />
            {r === "REALIZADO" ? "Realizado" : "No realizado (se cancela)"}
          </label>
        ))}
      </fieldset>
      <div className="mt-5">
        <CampoDeFormulario id="motivo-resolucion" etiqueta="Motivo (queda en la auditoría)" error={error}>
          <textarea id="motivo-resolucion" rows={3} maxLength={MOTIVO.max} value={motivo} onChange={(e) => setMotivo(e.target.value)} className="field resize-y" />
        </CampoDeFormulario>
        <p className="mt-1.5 text-right text-xs text-slate">
          {motivo.trim().length}/{MOTIVO.max}
        </p>
      </div>
      <div className="mt-5 flex justify-end gap-3">
        <button onClick={onCerrar} className="btn btn-quiet" disabled={enviando}>
          Cancelar
        </button>
        <button onClick={() => void confirmar()} className="btn btn-primary" disabled={enviando}>
          {enviando ? "Guardando…" : "Registrar resolución"}
        </button>
      </div>
    </VentanaModal>
  );
}
