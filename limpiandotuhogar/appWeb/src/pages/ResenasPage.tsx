import { useState } from "react";
import { useResenas } from "../data/ResenasContext";
import {
  calcularReputacionDelTrabajador,
  corregirResena,
  eliminarResena,
  MAX_COMENTARIO,
  MENSAJE_RESENAS_PENDIENTES,
  MENSAJE_SIN_PERMISO_DE_MODERACION,
  type ParticipanteDeLaResena,
  type ResenaParaAdmin,
  type RolEnLaResena,
} from "../data/resenas";
import type { Navegar, ResultadoDeOperacion } from "../data/tipos";
import { formatearFechaNumerica, normalizarTexto } from "../utils/formato";
import { AvisoTemporal } from "../components/comunes/AvisoTemporal";
import { CampoDeFormulario } from "../components/comunes/CampoDeFormulario";
import { Icono } from "../components/comunes/Icono";
import { Puntuacion } from "../components/comunes/Insignias";
import { VentanaDeMotivo } from "../components/moderacion/VentanaDeMotivo";

const OPCIONES_DE_PUNTUACION = ["Todas", "5", "4", "3", "2", "1"];

// Dirección de la reseña: el cliente califica al trabajador o el trabajador al cliente.
type FiltroDeDireccion = "todas" | RolEnLaResena;
const OPCIONES_DE_DIRECCION: { valor: FiltroDeDireccion; etiqueta: string }[] = [
  { valor: "todas", etiqueta: "Todas" },
  { valor: "CLIENTE", etiqueta: "Cliente → trabajador" },
  { valor: "TRABAJADOR", etiqueta: "Trabajador → cliente" },
];

type AccionAbierta = { tipo: "corregir"; resena: ResenaParaAdmin } | { tipo: "eliminar"; resena: ResenaParaAdmin } | null;

function describirParticipante(participante: ParticipanteDeLaResena): string {
  return `${participante.rol === "CLIENTE" ? "Cliente" : "Trabajador"} · ${participante.nombre}`;
}

// Trabajadores que aparecen como calificados en las reseñas (sin repetir).
function trabajadoresCalificados(resenas: ResenaParaAdmin[]): ParticipanteDeLaResena[] {
  const porId = new Map<string, ParticipanteDeLaResena>();
  for (const resena of resenas) {
    if (resena.calificado.rol === "TRABAJADOR") {
      porId.set(resena.calificado.id, resena.calificado);
    }
  }
  return [...porId.values()].sort((a, b) => a.nombre.localeCompare(b.nombre));
}

const mensajeDeError = (error: unknown) => (error instanceof Error ? error.message : "No se pudo completar la operación");

// Aviso de estado cuando no hay datos que mostrar (sin permiso, cargando o error).
function AvisoDeEstado({ titulo, texto, esError = false, onReintentar }: { titulo: string; texto: string; esError?: boolean; onReintentar?: () => void }) {
  return (
    <div role={esError ? "alert" : "status"} className="mt-8 flex items-start gap-3 rounded-2xl bg-moon p-5 text-sm text-clay">
      <Icono nombre="alerta" className="mt-0.5 h-5 w-5 shrink-0" />
      <div>
        <p className="font-bold text-navy">{titulo}</p>
        <p className="mt-1">{texto}</p>
        {onReintentar && (
          <button onClick={onReintentar} className="btn btn-quiet mt-3">
            Reintentar
          </button>
        )}
      </div>
    </div>
  );
}

// Formulario para corregir una reseña (calificación y/o comentario) con motivo obligatorio.
function VentanaDeCorreccion({ resena, onCerrar, onHecho }: { resena: ResenaParaAdmin; onCerrar: () => void; onHecho: () => void }) {
  const [puntuacion, setPuntuacion] = useState<number>(resena.puntuacion);
  const [comentario, setComentario] = useState(resena.comentario ?? "");
  return (
    <VentanaDeMotivo
      titulo="Corregir reseña"
      descripcion={`De ${describirParticipante(resena.autor)} para ${describirParticipante(resena.calificado)}. Lo anterior queda guardado en la auditoría.`}
      etiquetaDeConfirmar="Guardar corrección"
      onCerrar={onCerrar}
      onConfirmar={async (motivo) => {
        const cambios: { puntuacion?: number; comentario?: string | null } = {};
        if (puntuacion !== resena.puntuacion) cambios.puntuacion = puntuacion;
        const nuevoComentario = comentario.trim() || null;
        if (nuevoComentario !== resena.comentario) cambios.comentario = nuevoComentario;
        if (Object.keys(cambios).length === 0) return "No hay cambios que guardar.";
        try {
          await corregirResena(resena.id, cambios, motivo);
          onHecho();
          return null;
        } catch (error) {
          return mensajeDeError(error);
        }
      }}
    >
      <CampoDeFormulario id="puntuacion-corregida" etiqueta="Calificación">
        <select id="puntuacion-corregida" value={puntuacion} onChange={(evento) => setPuntuacion(Number(evento.target.value))} className="field cursor-pointer">
          {[5, 4, 3, 2, 1].map((valor) => (
            <option key={valor} value={valor}>
              {valor} de 5
            </option>
          ))}
        </select>
      </CampoDeFormulario>
      <CampoDeFormulario id="comentario-corregido" etiqueta={`Comentario (máx. ${MAX_COMENTARIO} caracteres; vacío = sin comentario)`}>
        <textarea id="comentario-corregido" rows={3} maxLength={MAX_COMENTARIO} value={comentario} onChange={(evento) => setComentario(evento.target.value)} className="field resize-y" />
      </CampoDeFormulario>
    </VentanaDeMotivo>
  );
}

// Reseñas: moderación de las calificaciones entre clientes y trabajadores (doc 20 §4).
// Solo con MODERAR_CONTENIDO (el backend lo exige). El administrador sí ve al autor (X0).
export function ResenasPage({ onNavegar }: { onNavegar: Navegar }) {
  const { estado, recargarResenas } = useResenas();
  const [busqueda, setBusqueda] = useState("");
  const [puntuacion, setPuntuacion] = useState("Todas");
  const [direccion, setDireccion] = useState<FiltroDeDireccion>("todas");
  const [idDelTrabajador, setIdDelTrabajador] = useState("todos");
  const [mostrarEliminadas, setMostrarEliminadas] = useState(false);
  const [accion, setAccion] = useState<AccionAbierta>(null);
  const [aviso, setAviso] = useState<ResultadoDeOperacion | null>(null);

  const hayDatos = estado.tipo === "listo";
  const todas = hayDatos ? [...estado.resenas].sort((a, b) => new Date(b.fechaCreacion).getTime() - new Date(a.fechaCreacion).getTime()) : [];
  const resenas = todas.filter((resena) => mostrarEliminadas || !resena.eliminada);
  const validas = todas.filter((resena) => !resena.eliminada);

  const textoBuscado = normalizarTexto(busqueda);
  const resenasVisibles = resenas.filter((resena) => {
    const coincidePuntuacion = puntuacion === "Todas" || resena.puntuacion === Number(puntuacion);
    const coincideDireccion = direccion === "todas" || resena.autor.rol === direccion;
    const coincideTrabajador = idDelTrabajador === "todos" || (resena.calificado.rol === "TRABAJADOR" && resena.calificado.id === idDelTrabajador);
    const coincideTexto = normalizarTexto(`${resena.idSolicitud} ${resena.servicio} ${resena.autor.nombre} ${resena.calificado.nombre} ${resena.comentario ?? ""}`).includes(textoBuscado);
    return coincidePuntuacion && coincideDireccion && coincideTrabajador && coincideTexto;
  });

  const resenasATrabajadores = validas.filter((resena) => resena.calificado.rol === "TRABAJADOR");
  const promedioATrabajadores = resenasATrabajadores.length > 0 ? resenasATrabajadores.reduce<number>((total, resena) => total + resena.puntuacion, 0) / resenasATrabajadores.length : null;
  const trabajadores = trabajadoresCalificados(validas);
  const reputaciones = trabajadores
    .map((trabajador) => ({ trabajador, reputacion: calcularReputacionDelTrabajador(validas, trabajador.id) }))
    .sort((a, b) => (b.reputacion.promedio ?? -1) - (a.reputacion.promedio ?? -1));
  const hayFiltros = busqueda.trim() !== "" || puntuacion !== "Todas" || direccion !== "todas" || idDelTrabajador !== "todos";
  const valorDelIndicador = (valor: string) => (hayDatos ? valor : "—");

  function terminarAccion(mensaje: string) {
    setAccion(null);
    setAviso({ exito: true, mensaje });
    void recargarResenas();
  }

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="text-4xl font-extrabold text-navy">Reseñas y reputación</h1>
      </div>
      <p className="mt-2 max-w-3xl text-sm text-slate">
        Calificaciones de 1 a 5 estrellas que se dan cliente y trabajador cuando el servicio ya finalizó (hasta 168 horas después). Calificar es opcional y se publica al instante. Los usuarios nunca ven quién escribió cada reseña; aquí sí, para moderarlas. Toda corrección o eliminación pide un motivo y queda en la auditoría.
      </p>

      {estado.tipo === "pendiente-de-backend" && <AvisoDeEstado titulo="Reseñas sin conectar" texto={MENSAJE_RESENAS_PENDIENTES} />}
      {estado.tipo === "sin-permiso" && <AvisoDeEstado titulo="Sin permiso de moderación" texto={MENSAJE_SIN_PERMISO_DE_MODERACION} />}
      {estado.tipo === "cargando" && <AvisoDeEstado titulo="Cargando reseñas…" texto="Consultando el servidor." />}
      {estado.tipo === "error" && <AvisoDeEstado titulo="No se pudieron cargar las reseñas" texto={estado.mensaje} esError onReintentar={() => void recargarResenas()} />}

      <div className="mt-8 grid gap-4 sm:grid-cols-3">
        <div className="surface leaf-sm p-5 sm:p-6">
          <p className="flex items-center gap-3 font-display text-3xl font-extrabold text-navy">
            {promedioATrabajadores !== null ? promedioATrabajadores.toFixed(1) : "—"}
            {promedioATrabajadores !== null && <Puntuacion valor={promedioATrabajadores} tamano="h-5 w-5" />}
          </p>
          <p className="mt-1 text-xs font-bold uppercase tracking-widest text-slate">Promedio de los colaboradores</p>
        </div>
        <div className="surface leaf-sm p-5 sm:p-6">
          <p className="font-display text-3xl font-extrabold text-navy">{valorDelIndicador(String(validas.length))}</p>
          <p className="mt-1 text-xs font-bold uppercase tracking-widest text-slate">Reseñas válidas</p>
          {hayDatos && todas.length > validas.length && <p className="mt-1 text-xs text-slate">{todas.length - validas.length} eliminadas por moderación</p>}
        </div>
        <div className="surface leaf-sm p-5 sm:p-6">
          <p className="font-display text-3xl font-extrabold text-navy">{valorDelIndicador(String(validas.filter((resena) => resena.calificado.rol === "CLIENTE").length))}</p>
          <p className="mt-1 text-xs font-bold uppercase tracking-widest text-slate">Reseñas a clientes</p>
          <p className="mt-1 text-xs text-slate">Las escriben los trabajadores.</p>
        </div>
      </div>

      <section aria-labelledby="titulo-de-reputacion" className="mt-10">
        <h2 id="titulo-de-reputacion" className="font-display text-2xl font-extrabold text-navy">
          Reputación por colaborador
        </h2>
        {reputaciones.length === 0 && <p className="mt-4 rounded-2xl bg-white p-6 text-center text-sm text-slate">{hayDatos ? "Todavía ningún colaborador tiene reseñas." : "Sin datos."}</p>}
        <ul className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {reputaciones.map(({ trabajador, reputacion }) => (
            <li key={trabajador.id}>
              <button onClick={() => setIdDelTrabajador(trabajador.id)} aria-pressed={idDelTrabajador === trabajador.id} className={`surface leaf-sm w-full cursor-pointer p-4 text-left transition duration-300 hover:-translate-y-0.5 hover:shadow-lift ${idDelTrabajador === trabajador.id ? "ring-2 ring-lagoon" : ""}`}>
                <span className="block truncate text-sm font-bold text-navy">{trabajador.nombre}</span>
                {reputacion.promedio !== null && (
                  <span className="mt-2 flex items-center gap-2">
                    <Puntuacion valor={reputacion.promedio} />
                    <span className="text-sm font-bold text-navy">{reputacion.promedio.toFixed(1)}</span>
                    <span className="text-xs text-slate">({reputacion.cantidad})</span>
                  </span>
                )}
              </button>
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="titulo-de-resenas" className="mt-10">
        <h2 id="titulo-de-resenas" className="font-display text-2xl font-extrabold text-navy">
          Reseñas
        </h2>
        <fieldset disabled={!hayDatos} className="mt-4 grid gap-4 disabled:opacity-60 md:grid-cols-[1fr_10rem_12rem_12rem] md:items-end">
          <div className="relative">
            <Icono nombre="buscar" className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-slate" />
            <input type="search" value={busqueda} onChange={(evento) => setBusqueda(evento.target.value)} placeholder="Buscar por solicitud, persona o comentario" aria-label="Buscar reseñas" className="field pl-11" />
          </div>
          <CampoDeFormulario id="filtro-de-puntuacion" etiqueta="Puntuación">
            <select id="filtro-de-puntuacion" value={puntuacion} onChange={(evento) => setPuntuacion(evento.target.value)} className="field cursor-pointer">
              {OPCIONES_DE_PUNTUACION.map((opcion) => (
                <option key={opcion} value={opcion}>
                  {opcion === "Todas" ? "Todas" : `${opcion} de 5`}
                </option>
              ))}
            </select>
          </CampoDeFormulario>
          <CampoDeFormulario id="filtro-de-direccion" etiqueta="Quién califica">
            <select id="filtro-de-direccion" value={direccion} onChange={(evento) => setDireccion(evento.target.value as FiltroDeDireccion)} className="field cursor-pointer">
              {OPCIONES_DE_DIRECCION.map((opcion) => (
                <option key={opcion.valor} value={opcion.valor}>
                  {opcion.etiqueta}
                </option>
              ))}
            </select>
          </CampoDeFormulario>
          <CampoDeFormulario id="filtro-de-colaborador" etiqueta="Colaborador calificado">
            <select id="filtro-de-colaborador" value={idDelTrabajador} onChange={(evento) => setIdDelTrabajador(evento.target.value)} className="field cursor-pointer">
              <option value="todos">Todos</option>
              {trabajadores.map((trabajador) => (
                <option key={trabajador.id} value={trabajador.id}>
                  {trabajador.nombre}
                </option>
              ))}
            </select>
          </CampoDeFormulario>
        </fieldset>

        <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-slate" aria-live="polite">
            {hayDatos ? (
              <>
                Mostrando <strong className="text-navy">{resenasVisibles.length}</strong> de {resenas.length} reseñas
              </>
            ) : (
              "Sin reseñas que mostrar."
            )}
          </p>
          <div className="flex flex-wrap items-center gap-3">
            <label className="flex cursor-pointer items-center gap-2 text-sm text-slate">
              <input type="checkbox" checked={mostrarEliminadas} onChange={(evento) => setMostrarEliminadas(evento.target.checked)} disabled={!hayDatos} />
              Mostrar eliminadas
            </label>
            {hayFiltros && (
              <button
                onClick={() => {
                  setBusqueda("");
                  setPuntuacion("Todas");
                  setDireccion("todas");
                  setIdDelTrabajador("todos");
                }}
                className="btn btn-quiet"
              >
                <Icono nombre="restablecer" className="h-4 w-4" />
                Restablecer filtros
              </button>
            )}
          </div>
        </div>

        {hayDatos && resenasVisibles.length === 0 && <p className="mt-4 rounded-2xl bg-white p-10 text-center text-sm text-slate">No hay reseñas que coincidan.</p>}
        <ul className="mt-4 space-y-3">
          {resenasVisibles.map((resena) => (
            <li key={resena.id} className={`surface leaf-sm grid gap-3 px-5 py-4 md:grid-cols-[9rem_1fr_13rem_auto] md:items-center md:gap-6 ${resena.eliminada ? "opacity-60" : ""}`}>
              <span>
                <Puntuacion valor={resena.puntuacion} />
                <span className="mt-1 block text-xs text-slate">{formatearFechaNumerica(resena.fechaCreacion)}</span>
                {resena.editadaPorAdministracion && <span className="mt-1 block text-xs font-bold text-clay">Corregida por administración</span>}
                {resena.eliminada && <span className="mt-1 block text-xs font-bold text-err">Eliminada por moderación</span>}
              </span>
              <span className="min-w-0">
                <span className="block text-sm text-storm">{resena.comentario ? `“${resena.comentario}”` : "Sin comentario"}</span>
                <button onClick={() => onNavegar("solicitudes", { idDeSolicitud: resena.idSolicitud })} className="mt-1 block cursor-pointer text-left text-xs text-lagoon hover:underline">
                  Solicitud {resena.idSolicitud} · {resena.servicio}
                </button>
              </span>
              <span className="text-xs text-slate">
                <span className="block">
                  <span className="font-bold text-navy">De:</span> {describirParticipante(resena.autor)}
                </span>
                <span className="block">
                  <span className="font-bold text-navy">Para:</span> {describirParticipante(resena.calificado)}
                </span>
              </span>
              {!resena.eliminada && (
                <span className="flex gap-2 md:flex-col">
                  <button onClick={() => setAccion({ tipo: "corregir", resena })} className="btn btn-quiet">
                    <Icono nombre="editar" className="h-4 w-4" />
                    Corregir
                  </button>
                  <button onClick={() => setAccion({ tipo: "eliminar", resena })} className="btn btn-quiet text-err">
                    <Icono nombre="prohibido" className="h-4 w-4" />
                    Eliminar
                  </button>
                </span>
              )}
            </li>
          ))}
        </ul>
      </section>

      {accion?.tipo === "corregir" && <VentanaDeCorreccion resena={accion.resena} onCerrar={() => setAccion(null)} onHecho={() => terminarAccion("Reseña corregida. El cambio quedó en la auditoría.")} />}
      {accion?.tipo === "eliminar" && (
        <VentanaDeMotivo
          titulo="Eliminar reseña"
          descripcion="Eliminación lógica: la reseña se conserva en el historial, deja de verse y de contar en los promedios. El usuario no podrá volver a calificar este servicio."
          etiquetaDeConfirmar="Sí, eliminar"
          peligrosa
          onCerrar={() => setAccion(null)}
          onConfirmar={async (motivo) => {
            try {
              await eliminarResena(accion.resena.id, motivo);
              terminarAccion("Reseña eliminada. Queda registrada en la auditoría.");
              return null;
            } catch (error) {
              return mensajeDeError(error);
            }
          }}
        />
      )}
      {aviso && <AvisoTemporal aviso={aviso} onTerminar={() => setAviso(null)} />}
    </div>
  );
}
