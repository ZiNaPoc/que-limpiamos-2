import { useCallback, useEffect, useState } from "react";

import { AvisoTemporal } from "../components/comunes/AvisoTemporal";
import { CampoDeFormulario } from "../components/comunes/CampoDeFormulario";
import { VentanaDeConfirmacion, VentanaModal } from "../components/comunes/VentanasModales";
import { catalogo, type CatalogoAdmin, consultarCatalogo, dinero, type ExtraAdmin, type ServicioAdmin } from "../data/plataforma";
import type { ResultadoDeOperacion } from "../data/tipos";

type Edicion =
  | { tipo: "servicio"; actual: ServicioAdmin | null }
  | { tipo: "extra"; actual: ExtraAdmin | null }
  | { tipo: "area" };
type Cambio = { titulo: string; lineas: string[]; ejecutar: () => Promise<unknown> };

const ESTADO = (e: string) => (e === "ACTIVO" ? "Activo" : "Inactivo");

// Catálogo REAL (D24: el admin lo administra). Crear, editar y activar/desactivar servicios, extras y
// áreas. No se borra nada: lo desactivado deja de ofrecerse y las solicitudes guardan su propia copia.
export function CatalogoPage() {
  const [c, setC] = useState<CatalogoAdmin | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [edicion, setEdicion] = useState<Edicion | null>(null);
  const [cambio, setCambio] = useState<Cambio | null>(null);
  const [aviso, setAviso] = useState<ResultadoDeOperacion | null>(null);

  const cargar = useCallback(async () => {
    try {
      setC(await consultarCatalogo());
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo cargar el catálogo");
    }
  }, []);
  useEffect(() => {
    const t = window.setTimeout(() => void cargar(), 0);
    return () => window.clearTimeout(t);
  }, [cargar]);

  async function aplicar(f: () => Promise<unknown>, ok: string): Promise<string | null> {
    try {
      await f();
      setAviso({ exito: true, mensaje: ok });
      await cargar();
      return null;
    } catch (e) {
      return e instanceof Error ? e.message : "No se pudo guardar";
    }
  }

  const alternar = (nombre: string, estado: string, f: (nuevo: string) => Promise<unknown>) => {
    const nuevo = estado === "ACTIVO" ? "INACTIVO" : "ACTIVO";
    setCambio({
      titulo: nuevo === "INACTIVO" ? `¿Desactivar «${nombre}»?` : `¿Activar «${nombre}»?`,
      lineas: [nuevo === "INACTIVO" ? "Dejará de ofrecerse en la app. Las solicitudes existentes no cambian." : "Volverá a ofrecerse en la app."],
      ejecutar: () => f(nuevo),
    });
  };

  if (error && !c) {
    return (
      <div role="alert" className="rounded-2xl border border-red-200 bg-white p-8 text-center">
        <p className="font-bold text-err">No se pudo cargar el catálogo</p>
        <p className="mt-2 text-sm text-slate">{error}</p>
        <button onClick={() => void cargar()} className="btn btn-primary mt-4">Reintentar</button>
      </div>
    );
  }
  if (!c) return <p className="rounded-2xl bg-white p-8 text-center text-sm text-slate">Cargando catálogo…</p>;
  const nombreEsp = (id: number) => c.especialidades.find((e) => e.id === id)?.nombre ?? `#${id}`;

  return (
    <div className="space-y-10">
      <header>
        <h1 className="text-4xl font-extrabold text-navy">Catálogo</h1>
        <p className="mt-2 max-w-3xl text-sm text-slate">Lo que ve el cliente en la app. El precio de una solicitud es el precio base del servicio más los extras (D4). Cambiar el catálogo no modifica solicitudes ya creadas.</p>
      </header>

      <section className="surface leaf-sm p-6">
        <div className="flex items-center justify-between">
          <h2 className="font-display text-xl font-extrabold text-navy">Servicios</h2>
          <button onClick={() => setEdicion({ tipo: "servicio", actual: null })} className="btn btn-primary">Nuevo servicio</button>
        </div>
        <ul className="mt-4 divide-y divide-mist/70">
          {c.servicios.map((s) => (
            <li key={s.id} className="flex flex-wrap items-center justify-between gap-3 py-4">
              <div className="min-w-0 flex-1">
                <p className="font-bold text-navy">
                  {s.nombre} <span className="ml-2 rounded-full bg-moon px-2.5 py-0.5 text-xs">{ESTADO(s.estado)}</span>
                </p>
                <p className="text-sm text-slate">{s.descripcion}</p>
                <p className="text-xs text-slate">
                  {dinero(s.precioBase)} · {s.duracionMin} min · {s.especialidadIds.map(nombreEsp).join(", ")} · {s.solicitudes} solicitud(es)
                </p>
              </div>
              <div className="flex gap-2">
                <button onClick={() => setEdicion({ tipo: "servicio", actual: s })} className="btn btn-quiet">Editar</button>
                <button onClick={() => alternar(s.nombre, s.estado, (estado) => catalogo.editarServicio(s.id, { estado }))} className="btn btn-quiet">
                  {s.estado === "ACTIVO" ? "Desactivar" : "Activar"}
                </button>
              </div>
            </li>
          ))}
        </ul>
      </section>

      <section className="surface leaf-sm p-6">
        <div className="flex items-center justify-between">
          <h2 className="font-display text-xl font-extrabold text-navy">Servicios extra</h2>
          <button onClick={() => setEdicion({ tipo: "extra", actual: null })} className="btn btn-primary">Nuevo extra</button>
        </div>
        <ul className="mt-4 divide-y divide-mist/70">
          {c.extras.map((x) => (
            <li key={x.id} className="flex flex-wrap items-center justify-between gap-3 py-3">
              <p className="text-navy">
                <strong>{x.nombre}</strong> · {dinero(x.precio)} · {x.duracionMin} min <span className="ml-2 rounded-full bg-moon px-2.5 py-0.5 text-xs">{ESTADO(x.estado)}</span>
              </p>
              <div className="flex gap-2">
                <button onClick={() => setEdicion({ tipo: "extra", actual: x })} className="btn btn-quiet">Editar</button>
                <button onClick={() => alternar(x.nombre, x.estado, (estado) => catalogo.editarExtra(x.id, { estado }))} className="btn btn-quiet">
                  {x.estado === "ACTIVO" ? "Desactivar" : "Activar"}
                </button>
              </div>
            </li>
          ))}
        </ul>
      </section>

      <section className="surface leaf-sm p-6">
        <div className="flex items-center justify-between">
          <h2 className="font-display text-xl font-extrabold text-navy">Áreas de la casa</h2>
          <button onClick={() => setEdicion({ tipo: "area" })} className="btn btn-primary">Nueva área</button>
        </div>
        <div className="mt-4 flex flex-wrap gap-2">
          {c.areas.map((a) => (
            <button key={a.id} onClick={() => alternar(a.nombre, a.estado, (estado) => catalogo.editarArea(a.id, { estado }))} className={`btn ${a.estado === "ACTIVO" ? "btn-quiet" : "btn-quiet opacity-60"}`} title="Activar o desactivar">
              {a.nombre} · {ESTADO(a.estado)}
            </button>
          ))}
        </div>
      </section>

      {edicion?.tipo === "servicio" && (
        <FormularioServicio
          actual={edicion.actual}
          especialidades={c.especialidades}
          onCerrar={() => setEdicion(null)}
          onGuardar={async (datos) => {
            const r = await aplicar(() => (edicion.actual ? catalogo.editarServicio(edicion.actual.id, datos) : catalogo.crearServicio(datos)), edicion.actual ? "Servicio actualizado." : "Servicio creado.");
            if (!r) setEdicion(null);
            return r;
          }}
        />
      )}
      {edicion?.tipo === "extra" && (
        <FormularioSimple
          titulo={edicion.actual ? "Editar extra" : "Nuevo extra"}
          campos={[
            { id: "nombre", etiqueta: "Nombre", valor: edicion.actual?.nombre ?? "" },
            { id: "precio", etiqueta: "Precio (MXN)", valor: String(edicion.actual?.precio ?? ""), numero: true },
            { id: "duracionMin", etiqueta: "Minutos adicionales", valor: String(edicion.actual?.duracionMin ?? 0), numero: true },
          ]}
          onCerrar={() => setEdicion(null)}
          onGuardar={async (v) => {
            const datos = { nombre: v.nombre, precio: Number(v.precio), duracionMin: Number(v.duracionMin) };
            const r = await aplicar(() => (edicion.actual ? catalogo.editarExtra(edicion.actual.id, datos) : catalogo.crearExtra(datos)), "Extra guardado.");
            if (!r) setEdicion(null);
            return r;
          }}
        />
      )}
      {edicion?.tipo === "area" && (
        <FormularioSimple
          titulo="Nueva área"
          campos={[{ id: "nombre", etiqueta: "Nombre", valor: "" }]}
          onCerrar={() => setEdicion(null)}
          onGuardar={async (v) => {
            const r = await aplicar(() => catalogo.crearArea({ nombre: v.nombre }), "Área creada.");
            if (!r) setEdicion(null);
            return r;
          }}
        />
      )}
      {cambio && (
        <VentanaDeConfirmacion
          titulo={cambio.titulo}
          lineasDeCambios={cambio.lineas}
          etiquetaDeConfirmar="Confirmar"
          onCancelar={() => setCambio(null)}
          onConfirmar={() => {
            const f = cambio.ejecutar;
            setCambio(null);
            void aplicar(f, "Cambio guardado.").then((e) => e && setAviso({ exito: false, mensaje: e }));
          }}
        />
      )}
      {aviso && <AvisoTemporal aviso={aviso} onTerminar={() => setAviso(null)} />}
    </div>
  );
}

function FormularioServicio({
  actual,
  especialidades,
  onCerrar,
  onGuardar,
}: {
  actual: ServicioAdmin | null;
  especialidades: CatalogoAdmin["especialidades"];
  onCerrar: () => void;
  onGuardar: (d: Record<string, unknown>) => Promise<string | null>;
}) {
  const [nombre, setNombre] = useState(actual?.nombre ?? "");
  const [descripcion, setDescripcion] = useState(actual?.descripcion ?? "");
  const [precio, setPrecio] = useState(String(actual?.precioBase ?? ""));
  const [duracion, setDuracion] = useState(String(actual?.duracionMin ?? 180));
  const [esp, setEsp] = useState<number[]>(actual?.especialidadIds ?? []);
  const [error, setError] = useState("");
  const [enviando, setEnviando] = useState(false);

  async function guardar() {
    if (nombre.trim().length < 2) return setError("Escribe el nombre (2 a 100 caracteres).");
    if (descripcion.trim().length < 5) return setError("Escribe una descripción (5 caracteres o más).");
    if (!(Number(precio) > 0)) return setError("El precio base debe ser mayor que 0.");
    if (!(Number(duracion) >= 30 && Number(duracion) <= 1440)) return setError("La duración debe ser de 30 a 1440 minutos.");
    if (!esp.length) return setError("Elige al menos una especialidad.");
    setEnviando(true);
    setError("");
    const r = await onGuardar({ nombre, descripcion, precioBase: Number(precio), duracionMin: Number(duracion), especialidadIds: esp });
    setEnviando(false);
    if (r) setError(r);
  }

  return (
    <VentanaModal idDelTitulo="titulo-servicio" onCerrar={onCerrar} claseDeAncho="max-w-lg">
      <h2 id="titulo-servicio" className="text-2xl font-extrabold text-navy">{actual ? "Editar servicio" : "Nuevo servicio"}</h2>
      <div className="mt-5 space-y-4">
        <CampoDeFormulario id="s-nombre" etiqueta="Nombre">
          <input id="s-nombre" value={nombre} maxLength={100} onChange={(e) => setNombre(e.target.value)} className="field" />
        </CampoDeFormulario>
        <CampoDeFormulario id="s-desc" etiqueta="Descripción">
          <textarea id="s-desc" value={descripcion} maxLength={1000} rows={3} onChange={(e) => setDescripcion(e.target.value)} className="field" />
        </CampoDeFormulario>
        <div className="grid grid-cols-2 gap-4">
          <CampoDeFormulario id="s-precio" etiqueta="Precio base (MXN)">
            <input id="s-precio" type="number" min={1} value={precio} onChange={(e) => setPrecio(e.target.value)} className="field" />
          </CampoDeFormulario>
          <CampoDeFormulario id="s-dur" etiqueta="Duración (min)">
            <input id="s-dur" type="number" min={30} max={1440} value={duracion} onChange={(e) => setDuracion(e.target.value)} className="field" />
          </CampoDeFormulario>
        </div>
        <fieldset>
          <legend className="text-sm font-bold text-navy">Especialidades requeridas</legend>
          <div className="mt-2 flex flex-wrap gap-3">
            {especialidades.map((e) => (
              <label key={e.id} className="inline-flex items-center gap-2 text-sm text-navy">
                <input type="checkbox" checked={esp.includes(e.id)} onChange={(ev) => setEsp(ev.target.checked ? [...esp, e.id] : esp.filter((x) => x !== e.id))} />
                {e.nombre}
              </label>
            ))}
          </div>
        </fieldset>
        {error && <p role="alert" className="text-sm text-err">{error}</p>}
      </div>
      <div className="mt-6 flex justify-end gap-3">
        <button onClick={onCerrar} className="btn btn-quiet" disabled={enviando}>Cancelar</button>
        <button onClick={() => void guardar()} className="btn btn-primary" disabled={enviando}>{enviando ? "Guardando…" : "Guardar"}</button>
      </div>
    </VentanaModal>
  );
}

function FormularioSimple({
  titulo,
  campos,
  onCerrar,
  onGuardar,
}: {
  titulo: string;
  campos: { id: string; etiqueta: string; valor: string; numero?: boolean }[];
  onCerrar: () => void;
  onGuardar: (v: Record<string, string>) => Promise<string | null>;
}) {
  const [valores, setValores] = useState<Record<string, string>>(Object.fromEntries(campos.map((c) => [c.id, c.valor])));
  const [error, setError] = useState("");
  const [enviando, setEnviando] = useState(false);

  async function guardar() {
    if (!valores.nombre?.trim()) return setError("Escribe el nombre.");
    for (const c of campos) if (c.numero && (valores[c.id] === "" || Number(valores[c.id]) < 0)) return setError(`${c.etiqueta}: escribe un número válido.`);
    setEnviando(true);
    setError("");
    const r = await onGuardar(valores);
    setEnviando(false);
    if (r) setError(r);
  }

  return (
    <VentanaModal idDelTitulo="titulo-simple" onCerrar={onCerrar}>
      <h2 id="titulo-simple" className="text-2xl font-extrabold text-navy">{titulo}</h2>
      <div className="mt-5 space-y-4">
        {campos.map((c) => (
          <CampoDeFormulario key={c.id} id={`f-${c.id}`} etiqueta={c.etiqueta}>
            <input id={`f-${c.id}`} type={c.numero ? "number" : "text"} min={0} value={valores[c.id] ?? ""} onChange={(e) => setValores({ ...valores, [c.id]: e.target.value })} className="field" />
          </CampoDeFormulario>
        ))}
        {error && <p role="alert" className="text-sm text-err">{error}</p>}
      </div>
      <div className="mt-6 flex justify-end gap-3">
        <button onClick={onCerrar} className="btn btn-quiet" disabled={enviando}>Cancelar</button>
        <button onClick={() => void guardar()} className="btn btn-primary" disabled={enviando}>{enviando ? "Guardando…" : "Guardar"}</button>
      </div>
    </VentanaModal>
  );
}
